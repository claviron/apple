import ClavironControlPlane
import SwiftUI

struct TasksView: View {
    let serverID: ServerID
    @Bindable var connectionModel: ConnectionModel
    @State private var actionModel: TaskActionModel
    @State private var pendingAction: PendingTaskAction?
    @State private var actionTargetName: String?
    @State private var submittedAction: TaskManagementAction?
    @State private var selectedTaskName: String?
    @State private var selectedTimingGroup: TaskTimingGroup = .daemon
    @NavigationDetailPath(.tasks) private var navigationPath: [String] = []

    init(
        serverID: ServerID,
        connectionModel: ConnectionModel,
        initialTaskName: String? = nil
    ) {
        self.serverID = serverID
        self.connectionModel = connectionModel
        _actionModel = State(
            initialValue: TaskActionModel(
                serverID: serverID,
                connectionModel: connectionModel
            )
        )
        _navigationPath = NavigationDetailPath(wrappedValue: initialTaskName.map { [$0] } ?? [], .tasks)
    }

    private var state: TaskObservationState {
        connectionModel.taskObservationState(for: serverID)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if let snapshot = state.snapshot {
                    taskList(snapshot)
                } else {
                    unavailableContent
                }
            }
            .workspaceNavigationTitle("Tasks")
            .managementDestination(for: String.self) { name in
                if let snapshot = state.snapshot,
                   let task = snapshot.tasks.first(where: { $0.name == name }) {
                    taskDetail(task, snapshot: snapshot)
                        .pageRefreshable(every: .seconds(2)) {
                            await connectionModel.loadTasks(for: serverID)
                        }
                } else {
                    ContentUnavailableView("Task Unavailable", systemImage: "questionmark.diamond")
                }
            }
            .onChange(of: state.snapshot) { _, snapshot in
                if let snapshot {
                    actionModel.incorporate(snapshot)
                }
            }
        }
        .pageRefreshable(every: .seconds(2)) {
            await connectionModel.loadTasks(for: serverID)
        }
    }

    private func taskList(_ snapshot: TaskFleetSnapshot) -> some View {
        let groups = TaskTimingGroup.tabs(
            for: snapshot.tasks,
            preserving: selectedTimingGroup
        )
        let tasks = snapshot.tasks.filter { selectedTimingGroup.contains($0.timing) }

        return ManagementDetailLayout {
            ManagementDetailCard(
                "Command result",
                systemImage: "terminal",
                tint: .orange
            ) {
                TaskActionStatusView(
                    state: actionModel.state,
                    targetName: actionTargetName,
                    submittedAction: submittedAction,
                    submittedAt: actionModel.submittedAt,
                    runExecutionTimeout: actionModel.submittedRunExecutionTimeout
                )
            }

            TaskTimingTabs(
                groups: groups,
                tasks: snapshot.tasks,
                selection: $selectedTimingGroup
            )

            ManagementDetailCard(
                selectedTimingGroup.title,
                systemImage: selectedTimingGroup.systemImage,
                tint: selectedTimingGroup.tint
            ) {
                if tasks.isEmpty {
                    ContentUnavailableView(
                        selectedTimingGroup.emptyTitle,
                        systemImage: selectedTimingGroup.systemImage,
                        description: Text(selectedTimingGroup.emptyDescription)
                    )
                } else {
                    ForEach(Array(tasks.enumerated()), id: \.element.name) { index, task in
                        if index > 0 {
                            Divider()
                        }
                        let status = taskStatus(task)
                        let name = ManagementResourceName.title(
                            task.name,
                            fallback: "Unnamed Task"
                        )
                        let runAction = TaskManagementAction.run(name: task.name)
                        ManagementResourceRow(
                            name: name,
                            systemImage: task.kind.systemImage,
                            assetImage: task.kind.assetImage,
                            assetIsTemplate: task.kind.assetIsTemplate,
                            iconTint: task.kind.iconTint,
                            status: status.title + TaskPresentationStatus.instanceSummary(for: task),
                            statusColor: status.color,
                            quickActionTitle: task.timing.supportsRun ? "Run" : nil,
                            quickActionDisabled: actionModel.isBusy
                                || !TaskActionModel.canSubmit(
                                    action: runAction,
                                    task: task,
                                    snapshot: snapshot
                                ),
                            quickAction: {
                                request(runAction, baseline: snapshot)
                            },
                            isSelected: selectedTaskName == task.name,
                            select: { select(task) },
                            open: { open(task) }
                        )
                        .accessibilityAction {
                            select(task)
                            open(task)
                        }
                    }
                }
            }

            // A member whose TaskService has stopped publishes nothing, and
            // a publisher cannot report its own end. Say that, rather than
            // leaving the rows it last sent on screen: those describe a
            // moment that has passed, and read as tasks stuck mid-stop.
            if snapshot.coverage != .complete {
                ManagementDetailCard(
                    "TaskService is not running everywhere",
                    systemImage: "exclamationmark.triangle",
                    tint: .orange
                ) {
                    Text(
                        snapshot.coverage == .noReports
                            ? "No member is reporting tasks. TaskService is stopped."
                            : "Some members are not reporting tasks; TaskService is stopped there. "
                                + "What is shown below comes only from the members that answered."
                    )
                    .foregroundStyle(.orange)
                }
            }

            if case let .stale(_, failure) = state {
                ManagementDetailCard(
                    "Observation warning",
                    systemImage: "clock.badge.exclamationmark",
                    tint: .orange
                ) {
                    Text(failure.localizedDescription)
                        .foregroundStyle(.orange)
                }
            }
        }
        .overlay {
            if case .loading(previous: .some) = state {
                ProgressView()
                    .padding()
                    .background(.regularMaterial, in: .circle)
            }
        }
    }

    private func taskDetail(
        _ task: TaskObservation,
        snapshot: TaskFleetSnapshot
    ) -> some View {
        let status = taskStatus(task)
        let name = ManagementResourceName.title(task.name, fallback: "Unnamed Task")
        return ManagementDetailLayout {
            ManagementResourceHeaderCard(
                kind: "Task",
                name: name,
                systemImage: task.kind.systemImage,
                assetImage: task.kind.assetImage,
                assetIsTemplate: task.kind.assetIsTemplate,
                iconTint: task.kind.iconTint,
                status: status.title,
                statusColor: status.color,
                actionsDisabled: actionModel.isBusy
            ) {
                taskActionButtons(task, snapshot: snapshot)
            }

            if actionTargetName == task.name, actionModel.state != .idle {
                ManagementDetailCard(
                    "Command result",
                    systemImage: "terminal",
                    tint: .orange
                ) {
                    TaskActionStatusView(
                        state: actionModel.state,
                        targetName: actionTargetName,
                        submittedAction: submittedAction,
                        submittedAt: actionModel.submittedAt,
                        runExecutionTimeout: actionModel.submittedRunExecutionTimeout
                    )
                }
            }

            taskDetailsCard(task)

            taskPlacementsCard(task)

            ManagementDetailCard(
                "Observation",
                systemImage: "clock.arrow.circlepath",
                tint: .teal
            ) {
                LabeledContent(
                    "Fleet members",
                    value: "\(snapshot.membersReporting) / \(snapshot.membersExpected) reporting"
                )
                LabeledContent(
                    "Captured",
                    value: snapshot.capturedAt?.clavironFormatted ?? "Not reported"
                )
            }
        }
        .workspaceNavigationTitle(name)
        .confirmationDialog(
            pendingAction?.intent.confirmationTitle ?? "Confirm task action",
            isPresented: confirmationPresented,
            titleVisibility: .visible,
            presenting: pendingAction
        ) { pending in
            Button(
                pending.intent.actionTitle,
                role: pending.intent.impact.confirmationRole
            ) {
                perform(pending.action, baseline: pending.baseline)
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.intent.confirmationMessage)
        }
    }

    private func open(_ task: TaskObservation) {
        guard navigationPath.last != task.name else {
            return
        }
        navigationPath.append(task.name)
    }

    private func select(_ task: TaskObservation) {
        selectedTaskName = task.name
    }

    @ViewBuilder
    private func taskActionButtons(
        _ task: TaskObservation,
        snapshot: TaskFleetSnapshot
    ) -> some View {
        if task.timing.supportsRun {
            actionButton(.run(name: task.name), task: task, snapshot: snapshot)
            Divider()
        }

        if task.timing.hasScheduleControl {
            actionButton(.start(name: task.name), task: task, snapshot: snapshot)
            actionButton(.stop(name: task.name), task: task, snapshot: snapshot)
        }

        actionButton(.reload(name: task.name), task: task, snapshot: snapshot)
        if task.timing.isDaemon {
            actionButton(.restart(name: task.name), task: task, snapshot: snapshot)
        }
    }

    private func actionButton(
        _ action: TaskManagementAction,
        task: TaskObservation,
        snapshot: TaskFleetSnapshot
    ) -> some View {
        Button(action.title) {
            request(action, baseline: snapshot)
        }
        .disabled(
            actionModel.isBusy
                || !TaskActionModel.canSubmit(
                    action: action,
                    task: task,
                    snapshot: snapshot
                )
        )
    }

    private func request(
        _ action: TaskManagementAction,
        baseline: TaskFleetSnapshot
    ) {
        guard !actionModel.isBusy else {
            return
        }
        let intent = action.intent
        if intent.impact.requiresConfirmation {
            pendingAction = PendingTaskAction(
                action: action,
                baseline: baseline,
                intent: intent
            )
        } else {
            perform(action, baseline: baseline)
        }
    }

    private func perform(
        _ action: TaskManagementAction,
        baseline: TaskFleetSnapshot
    ) {
        pendingAction = nil
        actionTargetName = action.taskName
        submittedAction = action
        Task {
            await actionModel.perform(action, baseline: baseline)
        }
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingAction = nil
                }
            }
        )
    }

    private func taskStatus(_ task: TaskObservation) -> ManagementResourceStatus {
        TaskPresentationStatus.summary(for: task)
    }

    @ViewBuilder
    private func taskDetailsCard(_ task: TaskObservation) -> some View {
        ManagementDetailCard(
            "Task details",
            systemImage: "info.circle",
            tint: .blue
        ) {
            LabeledContent(
                "Name",
                value: ManagementResourceName.title(task.name, fallback: "Unnamed Task")
            )
            LabeledContent("Code", value: task.name.isEmpty ? "Empty string" : task.name)
            LabeledContent("Kind", value: task.kind.title)
            LabeledContent("Scope", value: task.scope.title)
            LabeledContent("Dispatch", value: task.dispatch.title)
            LabeledContent("Concurrency", value: task.concurrency.formatted())
            LabeledContent("Execution summary", value: TaskPresentationStatus.detail(for: task))
            TaskTimingRows(timing: task.timing)
        }
    }

    @ViewBuilder
    private func taskPlacementsCard(_ task: TaskObservation) -> some View {
        ManagementDetailCard(
            "Runs on",
            systemImage: "square.stack.3d.up",
            tint: .indigo
        ) {
            if task.placements.isEmpty {
                Label("No fresh placement report", systemImage: "questionmark.diamond")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(task.placements.enumerated()), id: \.offset) { index, placement in
                    if index > 0 {
                        Divider()
                    }
                    TaskPlacementRow(
                        placement: placement,
                        timing: task.timing,
                        dispatch: task.dispatch
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var unavailableContent: some View {
        switch state {
        case .disconnected:
            ContentUnavailableView {
                Label("Disconnected", systemImage: "network.slash")
            } description: {
                Text("Connect to Claviron to load tasks.")
            } actions: {
                Button("Connect") {
                    Task {
                        await connectionModel.loadTasks(for: serverID)
                    }
                }
            }
        case .loading(previous: nil):
            ProgressView("Loading tasks…")
        case let .failed(failure):
            ContentUnavailableView {
                Label("Tasks Unavailable", systemImage: "xmark.circle")
            } description: {
                Text(failure.localizedDescription)
            } actions: {
                Button("Try Again") {
                    Task {
                        await connectionModel.loadTasks(for: serverID)
                    }
                }
            }
        case .loading(previous: .some), .empty, .loaded, .stale:
            EmptyView()
        }
    }
}

@MainActor
enum TaskTimingGroup: CaseIterable {
    case daemon
    case scheduled
    case manual
    case unspecified

    var title: String {
        switch self {
        case .scheduled: "Scheduled"
        case .daemon: "Daemon"
        case .manual: "Manual"
        case .unspecified: "Unspecified"
        }
    }

    var systemImage: String {
        switch self {
        case .scheduled: "calendar.badge.clock"
        case .daemon: "infinity.circle"
        case .manual: "hand.tap"
        case .unspecified: "questionmark.diamond"
        }
    }

    var emptyTitle: String {
        "No \(title) Tasks"
    }

    var emptyDescription: String {
        "No \(title.lowercased()) tasks are configured."
    }

    var tint: Color {
        switch self {
        case .scheduled: .teal
        case .daemon: .purple
        case .manual: .orange
        case .unspecified: .secondary
        }
    }

    func contains(_ timing: TaskTimingObservation?) -> Bool {
        switch (self, timing) {
        case (.scheduled, .interval), (.scheduled, .cron),
             (.daemon, .daemon), (.manual, .manual):
            true
        case (.unspecified, nil), (.unspecified, .unspecified):
            true
        default:
            false
        }
    }

    static func tabs(
        for tasks: [TaskObservation],
        preserving selection: TaskTimingGroup? = nil
    ) -> [TaskTimingGroup] {
        var tabs: [TaskTimingGroup] = [.daemon, .scheduled, .manual]
        if selection == .unspecified || tasks.contains(where: { unspecified.contains($0.timing) }) {
            tabs.append(.unspecified)
        }
        return tabs
    }
}

private struct TaskTimingTabs: View {
    let groups: [TaskTimingGroup]
    let tasks: [TaskObservation]
    @Binding var selection: TaskTimingGroup

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(groups, id: \.self) { group in
                    TaskTimingTab(
                        group: group,
                        count: tasks.count(where: { group.contains($0.timing) }),
                        isSelected: selection == group
                    ) {
                        selection = group
                    }
                }
            }
            .padding(1)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("task-timing-tabs")
    }
}

/// One timing tab. It owns its hover state so the tab reads as a control
/// before it is clicked: the pointer becomes a link pointer and the tab
/// lifts, the same affordance a management resource row already gives.
private struct TaskTimingTab: View {
    let group: TaskTimingGroup
    let count: Int
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: group.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(group.tint)
                    .frame(width: 30, height: 30)
                    .background(group.tint.opacity(isSelected ? 0.18 : 0.09), in: .rect(cornerRadius: 8))

                Text(group.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isSelected || isHovered ? Color.primary : Color.secondary)

                Spacer(minLength: 8)

                Text(count.formatted())
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(isSelected ? group.tint : Color.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        group.tint.opacity(isSelected ? 0.14 : 0.06),
                        in: .capsule
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(minWidth: 152, alignment: .leading)
            .contentShape(.rect(cornerRadius: 11))
            .background(background, in: .rect(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(border, lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .help(group.title)
#if os(macOS)
        .pointerStyle(.link)
#endif
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .accessibilityLabel(group.title)
        .accessibilityValue("\(count) tasks")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Selection is the group's own tint; hover is a lighter step of the
    /// same tint, so pointing at a tab previews what selecting it looks
    /// like instead of introducing a second colour.
    private var background: Color {
        if isSelected {
            return group.tint.opacity(0.09)
        }
        if isHovered {
            return group.tint.opacity(0.05)
        }
        return Color.primary.opacity(0.025)
    }

    private var border: Color {
        if isSelected {
            return group.tint.opacity(0.48)
        }
        if isHovered {
            return group.tint.opacity(0.3)
        }
        return Color.secondary.opacity(0.16)
    }
}

private struct TaskTimingRows: View {
    let timing: TaskTimingObservation?

    var body: some View {
        switch timing {
        case nil:
            LabeledContent("Timing", value: "Not reported")
        case .unspecified:
            LabeledContent("Timing", value: "Unspecified")
        case let .daemon(enabled):
            LabeledContent("Timing", value: "Daemon")
            LabeledContent("Schedule enabled", value: enabled ? "Yes" : "No")
        case let .interval(every, executionTimeout, enabled):
            LabeledContent("Timing", value: "Interval")
            LabeledContent("Every", value: every?.formatted ?? "Not reported")
            LabeledContent(
                "Execution timeout",
                value: executionTimeout?.formatted ?? "Not reported"
            )
            LabeledContent("Schedule enabled", value: enabled ? "Yes" : "No")
        case let .cron(expression, executionTimeout, enabled):
            LabeledContent("Timing", value: "Cron")
            LabeledContent("Expression", value: expression)
            LabeledContent(
                "Execution timeout",
                value: executionTimeout?.formatted ?? "Not reported"
            )
            LabeledContent("Schedule enabled", value: enabled ? "Yes" : "No")
        case let .manual(executionTimeout):
            LabeledContent("Timing", value: "Manual")
            LabeledContent(
                "Execution timeout",
                value: executionTimeout?.formatted ?? "Not reported"
            )
        }
    }
}

private struct TaskPlacementRow: View {
    let placement: TaskPlacementObservation
    let timing: TaskTimingObservation?
    let dispatch: TaskDispatchObservation

    var body: some View {
        let status = TaskPresentationStatus.placement(
            placement,
            timing: timing,
            dispatch: dispatch
        )
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(memberTitle, systemImage: placement.member?.role.systemImage ?? "questionmark.circle")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(status.title)
                    .foregroundStyle(status.color)
            }

            LabeledContent("In flight", value: placement.inFlight.formatted())
            LabeledContent("Controller", value: placement.lifecycle.title)
            if dispatch == .one || dispatch == .pool {
                LabeledContent("Owned slots", value: placement.ownedSlots.formatted())
            }
            LabeledContent("Generation", value: placement.generation.formatted())
            LabeledContent(
                "Observed",
                value: placement.observedAt?.clavironFormatted ?? "Not reported"
            )

            if let execution = placement.lastExecution {
                LabeledContent("Last result", value: execution.result.title)
                LabeledContent(
                    "Last finished",
                    value: execution.finishedAt?.clavironFormatted ?? "Not reported"
                )
            } else {
                LabeledContent("Last execution", value: "Not reported")
            }
        }
        .padding(.vertical, 4)
    }

    private var memberTitle: String {
        guard let member = placement.member else {
            return "Unknown member"
        }
        return "\(member.role.title) \(member.nodeID)"
    }
}

@MainActor
struct TaskPresentationStatus {
    static func instanceSummary(for task: TaskObservation) -> String {
        let count = runningInstanceCount(for: task)
        guard count > 0 else { return "" }
        return " · \(count.formatted()) \(count == 1 ? "instance" : "instances")"
    }

    static func detail(for task: TaskObservation) -> String {
        let count = runningInstanceCount(for: task)
        var instances = count == 1 ? "(1 instance)" : "(\(count.formatted()) instances)"
        let members = task.placements.compactMap { placement -> String? in
            guard placement.inFlight > 0 || placement.ownedSlots > 0,
                  let member = placement.member else { return nil }
            let activity = placement.inFlight > 0
                ? "\(placement.inFlight) running"
                : "\(placement.ownedSlots) armed"
            return "\(member.role.title) \(member.nodeID): \(activity)"
        }
        if !members.isEmpty {
            instances += " · " + members.joined(separator: ", ")
        }
        // The last result belongs to an earlier completed execution, not the
        // currently running instance(s). Keep both facts explicitly separate.
        let last = task.placements.compactMap { placement in
            placement.lastExecution.flatMap { outcome in
                outcome.finishedAt.map { (result: outcome.result, finishedAt: $0) }
            }
        }.max { $0.finishedAt < $1.finishedAt }
        guard let last else {
            return instances
        }
        return "\(instances) · Last: \(last.result.title) · \(last.finishedAt.clavironFormatted)"
    }

    static func runningInstanceCount(for task: TaskObservation) -> UInt64 {
        task.placements.reduce(0) { count, placement in
            count + placement.inFlight
        }
    }

    static func summary(for task: TaskObservation) -> ManagementResourceStatus {
        if task.placements.contains(where: { $0.inFlight > 0 }) {
            return ManagementResourceStatus(title: "Running", color: .green)
        }
        if !task.placements.contains(where: { $0.lifecycle == .missingRunner }),
           task.placements.contains(where: { $0.lifecycle == .active }) {
            return idleStatus(
                ownedSlots: task.placements.reduce(0) { $0 + $1.ownedSlots },
                timing: task.timing,
                dispatch: task.dispatch
            )
        }

        let targetLifecycles = task.placements
            .map(\.lifecycle)
            .filter { $0 != .ineligible }
        let lifecycles = targetLifecycles.isEmpty
            ? task.placements.map(\.lifecycle)
            : targetLifecycles

        return ManagementResourceStatus.aggregate(
            lifecycles,
            display: lifecycleStatus,
            isFailure: { $0 == .missingRunner }
        )
    }

    static func placement(
        _ placement: TaskPlacementObservation,
        timing: TaskTimingObservation?,
        dispatch: TaskDispatchObservation
    ) -> ManagementResourceStatus {
        if placement.inFlight > 0 {
            return ManagementResourceStatus(title: "Running", color: .green)
        }
        if placement.lifecycle == .active {
            return idleStatus(ownedSlots: placement.ownedSlots, timing: timing, dispatch: dispatch)
        }
        return lifecycleStatus(placement.lifecycle)
    }

    private static func idleStatus(
        ownedSlots: UInt64,
        timing: TaskTimingObservation?,
        dispatch: TaskDispatchObservation
    ) -> ManagementResourceStatus {
        ManagementResourceStatus(
            title: dispatch == .one || dispatch == .pool
                ? (ownedSlots > 0 ? "Armed" : "Waiting")
                : (timing.isDaemon ? "Not running" : "Armed"),
            color: .secondary
        )
    }

    private static func lifecycleStatus(
        _ lifecycle: TaskLifecycleObservation
    ) -> ManagementResourceStatus {
        ManagementResourceStatus(
            title: lifecycle.title,
            color: lifecycle.color
        )
    }
}

extension TaskKindObservation {
    var title: String {
        switch self {
        case .unspecified: "Unspecified"
        case .builtin: "Builtin"
        case .command: "Command"
        case .php: "PHP"
        case .js: "JavaScript"
        case .lua: "Lua"
        case let .unrecognized(rawValue): "Unknown (\(rawValue))"
        }
    }

    var systemImage: String {
        switch self {
        case .builtin: "cube.fill"
        case .command: "terminal"
        case .php: "chevron.left.forwardslash.chevron.right"
        case .js: "curlybraces"
        case .lua: "moon.fill"
        case .unspecified, .unrecognized: "questionmark.diamond"
        }
    }

    var assetImage: String? {
        switch self {
        case .builtin: "TaskIconRust"
        case .php: "TaskIconPHP"
        case .js: "TaskIconJavaScript"
        case .lua: "TaskIconLua"
        case .command, .unspecified, .unrecognized: nil
        }
    }

    var assetIsTemplate: Bool {
        false
    }

    var iconTint: Color? {
        nil
    }
}

private extension TaskScopeObservation {
    var title: String {
        switch self {
        case .unspecified: "Unspecified"
        case .master: "Master"
        case .workers: "Workers"
        case .fleet: "Fleet"
        case let .unrecognized(rawValue): "Unknown (\(rawValue))"
        }
    }
}

private extension TaskDispatchObservation {
    var title: String {
        switch self {
        case .unspecified: "Unspecified"
        case .each: "Each"
        case .one: "One"
        case .pool: "Pool"
        case let .unrecognized(rawValue): "Unknown (\(rawValue))"
        }
    }
}

private extension TaskMemberRoleObservation {
    var title: String {
        switch self {
        case .unspecified: "Unspecified"
        case .master: "Master"
        case .worker: "Worker"
        case .standalone: "Standalone"
        case let .unrecognized(rawValue): "Unknown (\(rawValue))"
        }
    }

    var systemImage: String {
        switch self {
        case .master: "crown"
        case .worker: "gearshape.2"
        case .standalone: "server.rack"
        case .unspecified, .unrecognized: "questionmark.circle"
        }
    }
}

private extension TaskLifecycleObservation {
    var title: String {
        switch self {
        case .unspecified: "Unspecified"
        case .ineligible: "Ineligible"
        case .disabled: "Disabled"
        case .inactive: "Inactive"
        case .active: "Active"
        case .stopping: "Stopping"
        case .finished: "Finished"
        case .missingRunner: "Missing runner"
        case let .unrecognized(rawValue): "Unknown (\(rawValue))"
        }
    }

    var color: Color {
        switch self {
        case .active: .green
        case .stopping: .orange
        case .missingRunner: .red
        case .unspecified, .ineligible, .disabled, .inactive, .finished, .unrecognized: .secondary
        }
    }
}

private extension TaskExecutionResultObservation {
    var title: String {
        switch self {
        case .unspecified: "Unspecified"
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .timedOut: "Timed out"
        case .gaveUp: "Gave up"
        case let .unrecognized(rawValue): "Unknown (\(rawValue))"
        }
    }
}

private struct PendingTaskAction: Identifiable {
    let id = UUID()
    let action: TaskManagementAction
    let baseline: TaskFleetSnapshot
    let intent: ManagementActionIntent
}

nonisolated extension TaskManagementAction {
    var title: String {
        let name = ManagementResourceName.title(taskName, fallback: "Unnamed Task")
        return switch self {
        case .start: "Start \(name)"
        case .stop: "Stop \(name)"
        case .reload: "Reload \(name)"
        case .restart: "Restart \(name)"
        case .run: "Run \(name) Now"
        }
    }

    var intent: ManagementActionIntent {
        switch self {
        case .start:
            ManagementActionIntent(
                actionTitle: title,
                confirmationTitle: "Start this task?",
                confirmationMessage: "Claviron will activate this task's configured timing policy across current fleet capacity.",
                impact: .routine
            )
        case .stop:
            ManagementActionIntent(
                actionTitle: title,
                confirmationTitle: "Stop this task?",
                confirmationMessage: "Claviron will deactivate its timing policy and stop its active task generations across current fleet capacity.",
                impact: .destructive
            )
        case .reload:
            ManagementActionIntent(
                actionTitle: title,
                confirmationTitle: "Reload this task?",
                confirmationMessage: "Claviron will publish a reload command for this task across current fleet capacity.",
                impact: .serviceWide
            )
        case .restart:
            ManagementActionIntent(
                actionTitle: title,
                confirmationTitle: "Restart this task?",
                confirmationMessage: "Claviron will replace every eligible daemon generation across current fleet capacity.",
                impact: .disruptive
            )
        case .run:
            ManagementActionIntent(
                actionTitle: title,
                confirmationTitle: "Run this task now?",
                confirmationMessage: "The Claviron instance handling this request will execute the task once and return its result.",
                impact: .routine
            )
        }
    }
}
