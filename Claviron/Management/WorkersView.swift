import ClavironControlPlane
import SwiftUI

struct WorkersView: View {
    @Environment(\.isWorkspacePageActive) private var isWorkspacePageActive
    let serverID: ServerID
    @Bindable var connectionModel: ConnectionModel
    @State private var actionModel: WorkerActionModel
    @State private var pendingWorkerAction: PendingWorkerAction?
    @State private var pendingFleetAction: PendingWorkerAction?
    @State private var submittedAction: WorkerManagementAction?
    @State private var selectedWorkerID: UInt32?
    @NavigationDetailPath(.workers) private var navigationPath: [UInt32] = []

    init(
        serverID: ServerID,
        connectionModel: ConnectionModel,
        initialWorkerID: UInt32? = nil
    ) {
        self.serverID = serverID
        self.connectionModel = connectionModel
        _actionModel = State(
            initialValue: WorkerActionModel(
                serverID: serverID,
                connectionModel: connectionModel
            )
        )
        _navigationPath = NavigationDetailPath(wrappedValue: initialWorkerID.map { [$0] } ?? [], .workers)
    }

    private var state: WorkerObservationState {
        connectionModel.workerObservationState(for: serverID)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if let snapshot = state.snapshot {
                    workerList(snapshot)
                } else {
                    unavailableContent
                }
            }
            .workspaceNavigationTitle("Workers")
            .managementDestination(for: UInt32.self) { workerID in
                if let snapshot = state.snapshot,
                   let worker = snapshot.workers.first(where: { $0.workerID == workerID }) {
                    workerDetail(worker, snapshot: snapshot)
                        .pageRefreshable(every: .seconds(2)) {
                            await connectionModel.loadWorkers(for: serverID)
                        }
                } else {
                    ContentUnavailableView("Worker Unavailable", systemImage: "questionmark.diamond")
                }
            }
            .toolbar {
                if isWorkspacePageActive, let snapshot = state.snapshot {
                    ToolbarItem {
                        fleetActions(snapshot)
                    }
                }
            }
            .onChange(of: state.snapshot) { _, snapshot in
                if let snapshot {
                    actionModel.incorporate(snapshot)
                }
            }
        }
        .confirmationDialog(
            pendingFleetAction?.intent.confirmationTitle ?? "Confirm fleet action",
            isPresented: fleetConfirmationPresented,
            titleVisibility: .visible,
            presenting: pendingFleetAction
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
        .pageRefreshable(every: .seconds(2)) {
            await connectionModel.loadWorkers(for: serverID)
        }
    }

    private func workerList(_ snapshot: WorkerFleetSnapshot) -> some View {
        ManagementDetailLayout {
            ManagementDetailCard(
                "Command result",
                systemImage: "terminal",
                tint: .orange
            ) {
                WorkerActionStatusView(
                    state: actionModel.state,
                    submittedAction: submittedAction
                )
            }

            ManagementDetailCard(
                "Workers",
                systemImage: "person.3.sequence",
                tint: .blue
            ) {
                if snapshot.workers.isEmpty {
                    if snapshot.coverage == .complete {
                        ContentUnavailableView(
                            "No Worker Slots",
                            systemImage: "person.3.sequence",
                            description: Text("The complete supervisor observation contains no workers.")
                        )
                    } else {
                        ContentUnavailableView(
                            "Worker Observation Incomplete",
                            systemImage: "exclamationmark.triangle",
                            description: Text("No worker status is present in the current incomplete observation.")
                        )
                    }
                } else {
                    ForEach(Array(snapshot.workers.enumerated()), id: \.element.workerID) { index, worker in
                        if index > 0 {
                            Divider()
                        }
                        ManagementResourceRow(
                            name: "Worker \(worker.workerID)",
                            systemImage: "cpu",
                            detail: worker.listMarker,
                            status: worker.lifecycle.title,
                            statusColor: worker.statusColor,
                            isSelected: selectedWorkerID == worker.workerID,
                            select: { selectedWorkerID = worker.workerID },
                            open: { navigationPath.append(worker.workerID) }
                        )
                    }
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
    }

    private func workerDetail(
        _ worker: WorkerObservation,
        snapshot: WorkerFleetSnapshot
    ) -> some View {
        ManagementDetailLayout {
            ManagementResourceHeaderCard(
                kind: "Worker",
                name: "Worker \(worker.workerID)",
                systemImage: "cpu",
                status: worker.lifecycle.title,
                statusColor: worker.statusColor,
                actionsDisabled: !canManage(snapshot) || actionModel.isBusy
            ) {
                workerActionButtons(worker, snapshot: snapshot)
            }

            ManagementDetailCard(
                "Command result",
                systemImage: "terminal",
                tint: .orange
            ) {
                WorkerActionStatusView(
                    state: actionModel.state,
                    submittedAction: submittedAction
                )
            }

            ManagementDetailCard(
                "Identity",
                systemImage: "number",
                tint: .blue
            ) {
                LabeledContent(
                    "PID",
                    value: worker.processID?.formatted() ?? "Not reported"
                )
                LabeledContent(
                    "Start stamp",
                    value: worker.process?.startStampFormatted ?? "Not reported"
                )
                LabeledContent("Incarnation", value: worker.incarnation.formatted())
                LabeledContent("Ownership") {
                    Text(worker.ownership.title)
                        .foregroundStyle(worker.ownership.color)
                }
            }

            ManagementDetailCard(
                "Lifecycle",
                systemImage: "arrow.triangle.2.circlepath",
                tint: .indigo
            ) {
                LabeledContent("Phase", value: aged(worker.phase.title, worker.phaseAge))
                LabeledContent("Desired", value: aged(worker.desired.title, worker.desiredAge))
                if let operation = worker.operation {
                    LabeledContent(
                        "Operation",
                        value: aged("#\(operation.id) \(operation.kind.title)", operation.age)
                    )
                    LabeledContent("Origin", value: operation.origin.title)
                    if let submissionKey = operation.origin.submissionKey {
                        LabeledContent("Submission", value: submissionKey.submissionKeyFormatted)
                    }
                } else {
                    LabeledContent("Operation", value: "None")
                }
                LabeledContent(
                    "Heartbeat",
                    value: worker.heartbeatAge.map { "\($0.formattedAge) ago" } ?? "Not yet received"
                )
                if let blockReason = worker.blockReason {
                    LabeledContent("Blocked", value: blockReason.title)
                }
            }

            ManagementDetailCard(
                "Worker details",
                systemImage: "info.circle",
                tint: .blue
            ) {
                LabeledContent(
                    "Uptime",
                    value: worker.uptime?.formatted ?? "Not reported"
                )
                LabeledContent("Recovery attempts", value: worker.recoveryAttempts.formatted())
                LabeledContent("Reload revision", value: worker.reloadRevision.formatted())
            }

            ManagementDetailCard(
                "Observation",
                systemImage: "clock.arrow.circlepath",
                tint: .teal
            ) {
                LabeledContent(
                    "Worker slots",
                    value: "\(snapshot.workers.count) / \(snapshot.workersExpected) observed"
                )
                LabeledContent("Fleet mode", value: snapshot.fleetMode.title)
                LabeledContent(
                    "Master PID",
                    value: snapshot.master?.process?.pid.formatted() ?? "Not reported"
                )
                LabeledContent(
                    "Master generation",
                    value: snapshot.master?.generation.formatted() ?? "Not reported"
                )
                LabeledContent("Build", value: snapshot.build?.formatted ?? "Not reported")
                LabeledContent(
                    "Captured",
                    value: snapshot.capturedAt?.clavironFormatted ?? "Not reported"
                )
            }
        }
        .workspaceNavigationTitle("Worker \(worker.workerID)")
        .confirmationDialog(
            pendingWorkerAction?.intent.confirmationTitle ?? "Confirm worker action",
            isPresented: workerConfirmationPresented,
            titleVisibility: .visible,
            presenting: pendingWorkerAction
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

    @ViewBuilder
    private func workerActionButtons(
        _ worker: WorkerObservation,
        snapshot: WorkerFleetSnapshot
    ) -> some View {
        Button(WorkerManagementAction.start(workerID: worker.workerID).title) {
            requestWorker(.start(workerID: worker.workerID), baseline: snapshot)
        }
        .disabled(!worker.lifecycle.canStart || !canManage(snapshot) || actionModel.isBusy)

        Button(WorkerManagementAction.reload(workerID: worker.workerID).title) {
            requestWorker(.reload(workerID: worker.workerID), baseline: snapshot)
        }
        .disabled(worker.lifecycle != .running || !canManage(snapshot) || actionModel.isBusy)

        Button(WorkerManagementAction.restart(workerID: worker.workerID).title) {
            requestWorker(.restart(workerID: worker.workerID), baseline: snapshot)
        }
        .disabled(
            worker.lifecycle != .running
                || snapshot.operationalWorkerCount <= 1
                || !canManage(snapshot)
                || actionModel.isBusy
        )

        Divider()

        Button(WorkerManagementAction.stop(workerID: worker.workerID).title) {
            requestWorker(.stop(workerID: worker.workerID), baseline: snapshot)
        }
        .disabled(
            !worker.lifecycle.canStop
                || (worker.lifecycle.countsAsRunning && snapshot.operationalWorkerCount <= 1)
                || !canManage(snapshot)
                || actionModel.isBusy
        )
    }

    private func fleetActions(_ snapshot: WorkerFleetSnapshot) -> some View {
        Menu("Fleet Actions", systemImage: "person.3.sequence") {
            Button(WorkerManagementAction.reloadAll.title) {
                requestFleet(.reloadAll, baseline: snapshot)
            }
            .disabled(snapshot.runningWorkerCount == 0)

            Button(WorkerManagementAction.restartAll.title) {
                requestFleet(.restartAll, baseline: snapshot)
            }
            .disabled(!snapshot.hasStableMembership || snapshot.runningWorkerCount < 2)

            Divider()

            Button(WorkerManagementAction.add.title) {
                requestFleet(.add, baseline: snapshot)
            }
            .disabled(!snapshot.hasStableMembership)

            Button(WorkerManagementAction.remove.title) {
                requestFleet(.remove, baseline: snapshot)
            }
            .disabled(
                !snapshot.hasStableMembership
                    || snapshot.workersExpected <= 1
                    || snapshot.runningWorkerCount < 2
            )
        }
        .disabled(!canManage(snapshot) || actionModel.isBusy)
        .accessibilityLabel("Worker fleet actions")
    }

    /// A fact together with how long it has held, when the master said.
    private func aged(_ title: String, _ age: ProtobufDurationObservation?) -> String {
        age.map { "\(title), for \($0.formattedAge)" } ?? title
    }

    private func canManage(_ snapshot: WorkerFleetSnapshot) -> Bool {
        guard snapshot.coverage == .complete,
              snapshot.hasConfiguredMembership else {
            return false
        }
        switch state {
        case .empty, .loaded:
            return true
        case .disconnected, .loading, .stale, .failed:
            return false
        }
    }

    private func requestWorker(
        _ action: WorkerManagementAction,
        baseline: WorkerFleetSnapshot
    ) {
        guard !actionModel.isBusy else {
            return
        }
        let intent = action.intent
        if intent.impact.requiresConfirmation {
            pendingWorkerAction = PendingWorkerAction(
                action: action,
                baseline: baseline,
                intent: intent
            )
        } else {
            perform(action, baseline: baseline)
        }
    }

    private func requestFleet(
        _ action: WorkerManagementAction,
        baseline: WorkerFleetSnapshot
    ) {
        guard !actionModel.isBusy else {
            return
        }
        let intent = action.intent
        if intent.impact.requiresConfirmation {
            pendingFleetAction = PendingWorkerAction(
                action: action,
                baseline: baseline,
                intent: intent
            )
        } else {
            perform(action, baseline: baseline)
        }
    }

    private func perform(
        _ action: WorkerManagementAction,
        baseline: WorkerFleetSnapshot
    ) {
        pendingWorkerAction = nil
        pendingFleetAction = nil
        submittedAction = action
        Task {
            await actionModel.perform(action, baseline: baseline)
        }
    }

    private var workerConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingWorkerAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingWorkerAction = nil
                }
            }
        )
    }

    private var fleetConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingFleetAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingFleetAction = nil
                }
            }
        )
    }

    @ViewBuilder
    private var unavailableContent: some View {
        switch state {
        case .disconnected:
            ContentUnavailableView {
                Label("Disconnected", systemImage: "network.slash")
            } description: {
                Text("Connect to Claviron to load the worker fleet.")
            } actions: {
                Button("Connect") {
                    Task {
                        await connectionModel.loadWorkers(for: serverID)
                    }
                }
            }
        case .loading(previous: nil):
            ProgressView("Loading workers…")
        case let .failed(failure):
            ContentUnavailableView {
                Label("Workers Unavailable", systemImage: "xmark.circle")
            } description: {
                Text(failure.localizedDescription)
            } actions: {
                Button("Try Again") {
                    Task {
                        await connectionModel.loadWorkers(for: serverID)
                    }
                }
            }
        case .loading(previous: .some), .empty, .loaded, .stale:
            EmptyView()
        }
    }
}

private struct PendingWorkerAction: Identifiable {
    let id = UUID()
    let action: WorkerManagementAction
    let baseline: WorkerFleetSnapshot
    let intent: ManagementActionIntent
}

nonisolated extension WorkerManagementAction {
    var title: String {
        switch self {
        case let .start(workerID):
            "Start Worker \(workerID)"
        case let .stop(workerID):
            "Stop Worker \(workerID)"
        case let .reload(workerID):
            "Reload Worker \(workerID)"
        case let .restart(workerID):
            "Restart Worker \(workerID)"
        case .reloadAll:
            "Reload All Workers"
        case .restartAll:
            "Restart All Workers"
        case .add:
            "Add Worker"
        case .remove:
            "Remove Worker"
        }
    }

    var intent: ManagementActionIntent {
        switch self {
        case .start:
            ManagementActionIntent(
                actionTitle: title,
                confirmationTitle: "Start this worker?",
                confirmationMessage: "Claviron will start the selected configured worker slot.",
                impact: .routine
            )
        case .reload:
            ManagementActionIntent(
                actionTitle: title,
                confirmationTitle: "Reload this worker?",
                confirmationMessage: "Claviron will reload the selected running worker in place.",
                impact: .routine
            )
        case .stop:
            ManagementActionIntent(
                actionTitle: title,
                confirmationTitle: "Stop this worker?",
                confirmationMessage: "The selected worker will drain and stop. Its configured slot remains available to start later.",
                impact: .destructive
            )
        case .restart:
            ManagementActionIntent(
                actionTitle: title,
                confirmationTitle: "Restart this worker?",
                confirmationMessage: "The selected worker will drain before Claviron starts its replacement incarnation.",
                impact: .disruptive
            )
        case .reloadAll:
            ManagementActionIntent(
                actionTitle: title,
                confirmationTitle: "Reload all running workers?",
                confirmationMessage: "Claviron will reload every worker that is currently running. Stopped slots stay stopped.",
                impact: .serviceWide
            )
        case .restartAll:
            ManagementActionIntent(
                actionTitle: title,
                confirmationTitle: "Restart all running workers?",
                confirmationMessage: "Claviron will replace running workers one at a time. Stopped slots stay stopped.",
                impact: .serviceWide
            )
        case .add:
            ManagementActionIntent(
                actionTitle: title,
                confirmationTitle: "Add one worker?",
                confirmationMessage: "The logical fleet grows by one. Claviron rolls the retained running workers onto the new fleet size, each through a new incarnation.",
                impact: .serviceWide
            )
        case .remove:
            ManagementActionIntent(
                actionTitle: title,
                confirmationTitle: "Remove the highest worker slot?",
                confirmationMessage: "The logical fleet shrinks by one. Only the highest configured worker drains; retained workers keep their process and incarnation.",
                impact: .destructive
            )
        }
    }
}

private extension WorkerLifecycleObservation {
    var canStart: Bool {
        switch self {
        case .stopped, .exited, .crashed:
            true
        case .unspecified, .starting, .running, .reloading, .stopping, .unclaimed,
             .unrecognized:
            false
        }
    }

    var canStop: Bool {
        switch self {
        case .starting, .running, .reloading:
            true
        case .unspecified, .stopping, .stopped, .exited, .crashed, .unclaimed,
             .unrecognized:
            false
        }
    }

    var countsAsRunning: Bool {
        self == .running || self == .reloading
    }
}

private extension ManagementActionState where Response == WorkerActionContext {
    /// The key the control plane gave the submission this state follows.
    var submissionKey: UInt64? {
        switch self {
        case .idle, .submitting:
            nil
        case let .accepted(context), let .acknowledged(context), let .completed(context),
             let .refreshing(context), let .rejected(context):
            context.receipt.submissionKey
        case let .waiting(context, _, _):
            context.receipt.submissionKey
        case let .succeeded(context, _):
            context.receipt.submissionKey
        case let .failed(_, context):
            context?.receipt.submissionKey
        }
    }
}

private extension WorkerFleetSnapshot {
    var runningWorkerCount: Int {
        workers.count { $0.lifecycle == .running }
    }

    var operationalWorkerCount: Int {
        workers.count { $0.lifecycle.countsAsRunning }
    }

    var hasStableMembership: Bool {
        workers.allSatisfy { worker in
            worker.lifecycle == .running || worker.lifecycle == .stopped
        }
    }

    var hasConfiguredMembership: Bool {
        if workersExpected == 0 {
            return workers.isEmpty
        }
        return workers.map(\.workerID) == Array(1...workersExpected)
    }
}
