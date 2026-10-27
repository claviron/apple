import ClavironControlPlane
import Foundation
import SwiftUI

/// Where the Applications list navigates: a native application, or one this
/// edge reaches through a linked control endpoint. Embedded and Linked are separate sections.
enum ApplicationRoute: Hashable {
    case native(ApplicationIDObservation)
    case linked(LinkedApplicationIDObservation)
}

struct ApplicationsView: View {
    let serverID: ServerID
    @Bindable var connectionModel: ConnectionModel
    @State private var actionModel: ApplicationActionModel
    @State private var pendingAction: PendingApplicationAction?
    @State private var actionTargetID: ApplicationIDObservation?
    @State private var selectedApplicationID: ApplicationIDObservation?
    @State private var selectedLinkedID: LinkedApplicationIDObservation?
    @NavigationDetailPath(.applications) private var navigationPath: [ApplicationRoute] = []

    init(
        serverID: ServerID,
        connectionModel: ConnectionModel,
        initialApplicationID: ApplicationIDObservation? = nil
    ) {
        self.serverID = serverID
        self.connectionModel = connectionModel
        _actionModel = State(
            initialValue: ApplicationActionModel(
                serverID: serverID,
                connectionModel: connectionModel
            )
        )
        _navigationPath = NavigationDetailPath(wrappedValue: initialApplicationID.map { [.native($0)] } ?? [], .applications)
    }

    private var state: ApplicationObservationState {
        connectionModel.applicationObservationState(for: serverID)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if let snapshot = state.snapshot {
                    applicationList(snapshot)
                } else {
                    unavailableContent
                }
            }
            .workspaceNavigationTitle("Applications")
            .managementDestination(for: ApplicationRoute.self) { route in
                switch route {
                case let .native(id):
                    if let snapshot = state.snapshot,
                       let application = snapshot.applications.first(where: { $0.applicationID == id }) {
                        applicationDetail(application, snapshot: snapshot)
                            .pageRefreshable(every: .seconds(2)) {
                                await connectionModel.loadApplications(for: serverID)
                            }
                    } else {
                        ContentUnavailableView("Application Unavailable", systemImage: "questionmark.diamond")
                    }
                case let .linked(id):
                    LinkedApplicationDetailView(
                        serverID: serverID,
                        connectionModel: connectionModel,
                        id: id
                    )
                }
            }
            .onChange(of: state.snapshot) { _, snapshot in
                if let snapshot {
                    actionModel.incorporate(snapshot)
                }
            }
        }
        .pageRefreshable(every: .seconds(2)) {
            await connectionModel.loadApplications(for: serverID)
        }
    }

    private var linkedApplications: [LinkedApplicationObservation] {
        connectionModel.linkedApplicationSnapshot(for: serverID)?.applications ?? []
    }

    private func applicationList(_ snapshot: ApplicationFleetSnapshot) -> some View {
        List {
            if snapshot.applications.isEmpty && linkedApplications.isEmpty {
                Section {
                    if snapshot.coverage == .complete {
                        ContentUnavailableView(
                            "No Configured Applications",
                            systemImage: "app.dashed",
                            description: Text("The complete fleet observation contains no applications.")
                        )
                    } else {
                        ContentUnavailableView(
                            "Application Inventory Incomplete",
                            systemImage: "exclamationmark.triangle",
                            description: Text("The current fleet observation contains no applications and is not complete.")
                        )
                    }
                }
            } else {
                if !snapshot.applications.isEmpty {
                    Section {
                        // Stable identities: rows of different lists must never be
                        // matched to each other by position.
                        ForEach(Array(snapshot.applications.enumerated()), id: \.element.rowID) { _, application in
                            nativeRow(application)
                        }
                    } header: {
                        Text("Embedded")
                    } footer: {
                        if case let .stale(_, failure) = state {
                            Label(failure.localizedDescription, systemImage: "clock.badge.exclamationmark")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                if !linkedApplications.isEmpty
                    || connectionModel.linkedApplicationFailure(for: serverID) != nil {
                    Section {
                        ForEach(Array(linkedApplications.enumerated()), id: \.element.rowID) { _, application in
                            linkedRow(application)
                        }
                    } header: {
                        Text("Linked")
                    } footer: {
                        if let failure = connectionModel.linkedApplicationFailure(for: serverID) {
                            Label(failure.localizedDescription, systemImage: "clock.badge.exclamationmark")
                                .foregroundStyle(.orange)
                        }
                    }
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

    private func applicationDetail(
        _ application: ApplicationObservation,
        snapshot: ApplicationFleetSnapshot
    ) -> some View {
        let status = applicationStatus(application)
        let name = application.applicationID.map {
            ManagementResourceName.title($0.name, fallback: "Unnamed Application")
        } ?? "Unidentified Application"
        let runtime = ApplicationIconPresentation(application.description?.icon, runtime: application.description?.runtime ?? application.applicationID?.runtime)
        return ManagementDetailLayout {
            ManagementResourceHeaderCard(
                kind: "Application",
                name: name,
                systemImage: runtime.systemImage,
                assetImage: runtime.assetImage,
                assetIsTemplate: false,
                iconTint: nil,
                status: status.title,
                statusColor: status.color,
                actionsDisabled: application.applicationID == nil || actionModel.isBusy
            ) {
                applicationActionButtons(application, snapshot: snapshot)
            }

            if actionTargetID == application.applicationID, actionModel.state != .idle {
                ManagementDetailCard(
                    "Command result",
                    systemImage: "terminal",
                    tint: .orange
                ) {
                    ManagementActionStatusView(state: actionModel.state) { context in
                        context.receipt.action.title
                    }
                }
            }

            applicationDetailsCard(application)

            applicationPlacementsCard(application)

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
            pendingAction?.intent.confirmationTitle ?? "Confirm application action",
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

    private func nativeRow(_ application: ApplicationObservation) -> some View {
        let status = applicationStatus(application)
        let runtime = ApplicationIconPresentation(application.description?.icon, runtime: application.description?.runtime ?? application.applicationID?.runtime)
        let name = application.applicationID.map {
            ManagementResourceName.title($0.name, fallback: "Unnamed Application")
        } ?? "Unidentified Application"
        return ManagementResourceRow(
            name: name,
            systemImage: runtime.systemImage,
            assetImage: runtime.assetImage,
            assetIsTemplate: false,
            iconTint: nil,
            detail: application.description?.summary ?? runtime.title,
            tags: application.description?.frameworks ?? [],
            status: status.title,
            statusColor: status.color,
            isSelected: selectedApplicationID == application.applicationID,
            select: { select(application) },
            open: { open(application) }
        )
        .accessibilityAction {
            select(application)
            open(application)
        }
    }

    private func linkedRow(_ application: LinkedApplicationObservation) -> some View {
        let presentation = LinkedApplicationPresentation(application: application)
        let open = {
            selectedLinkedID = application.id
            selectedApplicationID = nil
            if let id = application.id, navigationPath.last != .linked(id) {
                navigationPath.append(.linked(id))
            }
        }
        return ManagementResourceRow(
            name: presentation.name,
            systemImage: presentation.runtime.systemImage,
            assetImage: presentation.runtime.assetImage,
            assetIsTemplate: false,
            iconTint: nil,
            detail: presentation.detail,
            tags: application.description?.frameworks ?? [],
            status: presentation.status.title,
            statusColor: presentation.status.color,
            isSelected: application.id != nil && selectedLinkedID == application.id,
            select: {
                selectedLinkedID = application.id
                selectedApplicationID = nil
            },
            open: open
        )
        .accessibilityAction { open() }
    }

    private func open(_ application: ApplicationObservation) {
        guard let id = application.applicationID,
              navigationPath.last != .native(id) else {
            return
        }
        navigationPath.append(.native(id))
    }

    private func select(_ application: ApplicationObservation) {
        selectedApplicationID = application.applicationID
        selectedLinkedID = nil
    }

    @ViewBuilder
    private func applicationActionButtons(
        _ application: ApplicationObservation,
        snapshot: ApplicationFleetSnapshot
    ) -> some View {
        if let id = application.applicationID {
            actionButton(.start(id: id), application: application, snapshot: snapshot)
            actionButton(.restart(id: id), application: application, snapshot: snapshot)

            Divider()

            actionButton(.stop(id: id), application: application, snapshot: snapshot)
        }
    }

    private func actionButton(
        _ action: ApplicationManagementAction,
        application: ApplicationObservation,
        snapshot: ApplicationFleetSnapshot
    ) -> some View {
        Button(action.title) {
            request(action, baseline: snapshot)
        }
        .disabled(
            actionModel.isBusy
                || !ApplicationActionModel.canSubmit(
                    action: action,
                    application: application,
                    snapshot: snapshot
                )
        )
    }

    private func request(
        _ action: ApplicationManagementAction,
        baseline: ApplicationFleetSnapshot
    ) {
        guard !actionModel.isBusy else {
            return
        }
        let intent = action.intent
        if intent.impact.requiresConfirmation {
            pendingAction = PendingApplicationAction(
                action: action,
                baseline: baseline,
                intent: intent
            )
        } else {
            perform(action, baseline: baseline)
        }
    }

    private func perform(
        _ action: ApplicationManagementAction,
        baseline: ApplicationFleetSnapshot
    ) {
        pendingAction = nil
        actionTargetID = action.applicationID
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

    private func applicationStatus(
        _ application: ApplicationObservation
    ) -> ManagementResourceStatus {
        ManagementResourceStatus.aggregate(
            application.placements.map(\.lifecycle),
            display: { ManagementResourceStatus(title: $0.title, color: $0.color) },
            isFailure: { $0 == .failed }
        )
    }

    @ViewBuilder
    private func applicationDetailsCard(_ application: ApplicationObservation) -> some View {
        ManagementDetailCard(
            "Application details",
            systemImage: "info.circle",
            tint: .blue
        ) {
            if let applicationID = application.applicationID {
                LabeledContent(
                    "Name",
                    value: ManagementResourceName.title(
                        applicationID.name,
                        fallback: "Unnamed Application"
                    )
                )
                LabeledContent(
                    "Code",
                    value: applicationID.name.isEmpty ? "Empty string" : applicationID.name
                )
                LabeledContent("Control runtime", value: applicationID.runtime)
            } else {
                Label("Application identity not reported", systemImage: "questionmark.diamond")
                    .foregroundStyle(.secondary)
            }
            if let description = application.description {
                ApplicationDescriptionRows(description: description)
            }
        }
    }

    @ViewBuilder
    private func applicationPlacementsCard(_ application: ApplicationObservation) -> some View {
        ManagementDetailCard(
            "Runs on",
            systemImage: "square.stack.3d.up",
            tint: .indigo
        ) {
            if application.placements.isEmpty {
                Label("No fresh placement report", systemImage: "questionmark.diamond")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(application.placements.enumerated()), id: \.offset) { index, placement in
                    if index > 0 {
                        Divider()
                    }
                    ApplicationPlacementRow(placement: placement)
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
                Text("Connect to Claviron to load configured applications.")
            } actions: {
                Button("Connect") {
                    Task {
                        await connectionModel.loadApplications(for: serverID)
                    }
                }
            }
        case .loading(previous: nil):
            ProgressView("Loading applications…")
        case let .failed(failure):
            ContentUnavailableView {
                Label("Applications Unavailable", systemImage: "xmark.circle")
            } description: {
                Text(failure.localizedDescription)
            } actions: {
                Button("Try Again") {
                    Task {
                        await connectionModel.loadApplications(for: serverID)
                    }
                }
            }
        case .loading(previous: .some), .empty, .loaded, .stale:
            EmptyView()
        }
    }
}

extension ApplicationDescriptionObservation {
    var summary: String? {
        let value = [ApplicationRuntimePresentation(runtime).title, runner, requestMode]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return value.isEmpty ? nil : value
    }
}

struct ApplicationDescriptionRows: View {
    let description: ApplicationDescriptionObservation

    var body: some View {
        LabeledContent("Runtime", value: ApplicationRuntimePresentation(description.runtime).title ?? "Not reported")
        LabeledContent("Frameworks") {
            if description.frameworks.isEmpty {
                Text("Not provided")
            } else {
                ManagementResourceTags(tags: description.frameworks)
            }
        }
        if let icon = description.icon {
            LabeledContent("Icon code", value: icon)
        }
        LabeledContent("Runner", value: description.runner ?? "Not reported")
        LabeledContent("Request mode", value: description.requestMode ?? "Not reported")
    }
}

struct ApplicationRuntimePresentation {
    private let runtime: String?

    init(_ runtime: String?) {
        let trimmed = runtime?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.runtime = trimmed?.isEmpty == false ? trimmed : nil
    }

    var title: String? {
        switch normalizedRuntime {
        case "php":
            "PHP"
        case "js", "javascript":
            "JavaScript"
        case "lua":
            "Lua"
        case "python", "asgi":
            "Python"
        case "rust", "builtin":
            "Rust"
        case nil:
            nil
        default:
            runtime
        }
    }

    var systemImage: String {
        switch normalizedRuntime {
        case "php":
            "chevron.left.forwardslash.chevron.right"
        case "js", "javascript":
            "curlybraces"
        case "lua":
            "moon.stars.fill"
        case "python", "asgi":
            "chevron.left.forwardslash.chevron.right"
        case "rust", "builtin":
            "cube.fill"
        case nil:
            "questionmark.diamond"
        default:
            "app.fill"
        }
    }

    var assetImage: String? {
        switch normalizedRuntime {
        case "php":
            "TaskIconPHP"
        case "js", "javascript":
            "TaskIconJavaScript"
        case "lua":
            "TaskIconLua"
        case "python", "asgi":
            "TaskIconPython"
        case "rust", "builtin":
            "TaskIconRust"
        case nil:
            nil
        default:
            nil
        }
    }

    private var normalizedRuntime: String? {
        runtime?.lowercased()
    }
}

struct ApplicationPlacementRow: View {
    let placement: ApplicationPlacementObservation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(memberTitle, systemImage: placement.member?.role.systemImage ?? "questionmark.circle")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(placement.lifecycle.title)
                    .foregroundStyle(placement.lifecycle.color)
            }

            LabeledContent("Enabled", value: placement.enabled ? "Yes" : "No")
            LabeledContent("Generation", value: placement.generation.formatted())
            if let description = placement.description {
                ApplicationDescriptionRows(description: description)
            }
            LabeledContent(
                "Observed",
                value: placement.observedAt?.clavironFormatted ?? "Not reported"
            )

            if let pool = placement.pool {
                poolDetails(pool)
            } else {
                LabeledContent("Pool", value: "Not reported")
            }

            if let lastError = placement.lastError {
                VStack(alignment: .leading, spacing: 2) {
                    Text(placement.lastErrorTruncated ? "Last error · Truncated" : "Last error")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(lastError)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
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

    private func poolDetails(_ pool: ApplicationPoolObservation) -> some View {
        Group {
            LabeledContent("Pool instances", value: pool.instances.formatted())
            LabeledContent("Accepting", value: pool.accepting.yesNoOrNotReported)
            LabeledContent("Ready", value: pool.ready.formattedOrNotReported)
            LabeledContent("Busy", value: pool.busy.formattedOrNotReported)
            LabeledContent("Retiring", value: pool.retiring.formattedOrNotReported)
            LabeledContent("Backing off", value: pool.backingOff.formattedOrNotReported)
            LabeledContent("Exhausted", value: pool.exhausted.formattedOrNotReported)
        }
    }
}

extension ApplicationLifecycleObservation {
    var title: String {
        switch self {
        case .unspecified:
            "Unspecified"
        case .starting:
            "Starting"
        case .running:
            "Running"
        case .stopping:
            "Stopping"
        case .stopped:
            "Stopped"
        case .failed:
            "Failed"
        case let .unrecognized(rawValue):
            "Unknown (\(rawValue))"
        }
    }

    var color: Color {
        switch self {
        case .running:
            .green
        case .starting, .stopping:
            .orange
        case .failed:
            .red
        case .unspecified, .stopped, .unrecognized:
            .secondary
        }
    }
}

private extension ApplicationMemberRoleObservation {
    var title: String {
        switch self {
        case .unspecified:
            "Unspecified"
        case .master:
            "Master"
        case .worker:
            "Worker"
        case .standalone:
            "Standalone"
        case let .unrecognized(rawValue):
            "Unknown (\(rawValue))"
        }
    }

    var systemImage: String {
        switch self {
        case .master:
            "crown"
        case .worker:
            "gearshape.2"
        case .standalone:
            "server.rack"
        case .unspecified, .unrecognized:
            "questionmark.circle"
        }
    }
}

private extension Optional where Wrapped == Bool {
    var yesNoOrNotReported: String {
        switch self {
        case true:
            "Yes"
        case false:
            "No"
        case nil:
            "Not reported"
        }
    }
}

private extension Optional where Wrapped == UInt32 {
    var formattedOrNotReported: String {
        map { $0.formatted() } ?? "Not reported"
    }
}

private struct PendingApplicationAction: Identifiable {
    let id = UUID()
    let action: ApplicationManagementAction
    let baseline: ApplicationFleetSnapshot
    let intent: ManagementActionIntent
}

nonisolated extension ApplicationManagementAction {
    var title: String {
        switch self {
        case let .start(id):
            "Start \(ManagementResourceName.title(id.name, fallback: "Unnamed Application"))"
        case let .stop(id):
            "Stop \(ManagementResourceName.title(id.name, fallback: "Unnamed Application"))"
        case let .restart(id):
            "Restart \(ManagementResourceName.title(id.name, fallback: "Unnamed Application"))"
        }
    }

    var intent: ManagementActionIntent {
        switch self {
        case .start:
            ManagementActionIntent(
                actionTitle: title,
                confirmationTitle: "Start this application?",
                confirmationMessage: "Claviron will start this application across every configured fleet placement.",
                impact: .serviceWide
            )
        case .stop:
            ManagementActionIntent(
                actionTitle: title,
                confirmationTitle: "Stop this application?",
                confirmationMessage: "Claviron will drain and stop this application across every configured fleet placement.",
                impact: .destructive
            )
        case .restart:
            ManagementActionIntent(
                actionTitle: title,
                confirmationTitle: "Restart this application?",
                confirmationMessage: "Claviron will replace this application's runtime generation across every configured fleet placement.",
                impact: .disruptive
            )
        }
    }
}

/// A list row's identity: the application's own id, never its position, so a
/// row is not drawn with another row's content when the lists change.
extension ApplicationObservation {
    var rowID: String {
        applicationID.map { "native:\($0.runtime)/\($0.name)" } ?? "native:unidentified"
    }
}

extension LinkedApplicationObservation {
    var rowID: String {
        id.map { "linked:\($0.transport)/\($0.fleetName)/\($0.name)" } ?? "linked:unidentified"
    }
}
