import ClavironControlPlane
import SwiftUI

struct ServicesView: View {
    let serverID: ServerID
    @Bindable var connectionModel: ConnectionModel
    @State private var actionModels: ManagementResourceActionStore<String, ServiceActionModel>
    @State private var pendingAction: PendingServiceAction?
    @State private var selectedServiceName: String?
    @NavigationDetailPath(.services) private var navigationPath: [String] = []

    init(
        serverID: ServerID,
        connectionModel: ConnectionModel,
        initialServiceName: String? = nil
    ) {
        self.serverID = serverID
        self.connectionModel = connectionModel
        _actionModels = State(
            initialValue: ManagementResourceActionStore {
                ServiceActionModel(
                    serverID: serverID,
                    connectionModel: connectionModel
                )
            }
        )
        _navigationPath = NavigationDetailPath(wrappedValue: initialServiceName.map { [$0] } ?? [], .services)
    }

    private var state: ServiceObservationState {
        connectionModel.serviceObservationState(for: serverID)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if let snapshot = state.snapshot {
                    serviceList(snapshot)
                } else {
                    unavailableContent
                }
            }
            .workspaceNavigationTitle("Services")
            .managementDestination(for: String.self) { name in
                if let snapshot = state.snapshot,
                   let service = snapshot.services.first(where: { $0.name == name }) {
                    serviceDetail(service, snapshot: snapshot)
                        .pageRefreshable(every: .seconds(2)) {
                            await connectionModel.loadServices(for: serverID)
                        }
                } else {
                    ContentUnavailableView("Service Unavailable", systemImage: "questionmark.diamond")
                }
            }
            .onChange(of: state.snapshot) { _, snapshot in
                if let snapshot {
                    for actionModel in actionModels.values {
                        actionModel.incorporate(snapshot)
                    }
                }
            }
        }
        .pageRefreshable(every: .seconds(2)) {
            await connectionModel.loadServices(for: serverID)
        }
    }

    private func open(_ service: ServiceObservation) {
        guard navigationPath.last != service.name else {
            return
        }
        navigationPath.append(service.name)
    }

    private func select(_ service: ServiceObservation) {
        selectedServiceName = service.name
    }

    private func serviceList(_ snapshot: ServiceFleetSnapshot) -> some View {
        List {
            if snapshot.services.isEmpty {
                Section {
                    if snapshot.coverage == .complete {
                        ContentUnavailableView(
                            "No Registered Services",
                            systemImage: "shippingbox",
                            description: Text("The complete fleet observation contains no services.")
                        )
                    } else {
                        ContentUnavailableView(
                            "Service Inventory Incomplete",
                            systemImage: "exclamationmark.triangle",
                            description: Text("The current fleet observation contains no services and is not complete.")
                        )
                    }
                }
            } else {
                Section {
                    ForEach(snapshot.services) { service in
                        let status = ServiceSummaryStatus(service: service)
                        ManagementResourceRow(
                            name: service.name,
                            systemImage: ServicePresentation.systemImage,
                            assetImage: ServicePresentation.assetImage,
                            assetIsTemplate: false,
                            iconTint: nil,
                            status: status.title + ServiceSummaryStatus.instanceSummary(service),
                            statusColor: status.color,
                            isSelected: selectedServiceName == service.name,
                            select: { select(service) },
                            open: { open(service) }
                        )
                        .accessibilityAction {
                            select(service)
                            open(service)
                        }
                    }
                } footer: {
                    if case let .stale(_, failure) = state {
                        Label(failure.localizedDescription, systemImage: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
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

    private func serviceDetail(
        _ service: ServiceObservation,
        snapshot: ServiceFleetSnapshot
    ) -> some View {
        let status = ServiceSummaryStatus(service: service)
        let actionModel = actionModels.value(for: service.name)
        return ManagementDetailLayout {
            ManagementResourceHeaderCard(
                kind: "Service",
                name: service.name,
                systemImage: ServicePresentation.systemImage,
                assetImage: ServicePresentation.assetImage,
                assetIsTemplate: false,
                iconTint: nil,
                status: status.title,
                statusColor: status.color,
                actionsDisabled: actionModel.isBusy
            ) {
                serviceActionButtons(
                    service,
                    snapshot: snapshot,
                    actionModel: actionModel
                )
            }

            if actionModel.state != .idle {
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

            ManagementDetailCard(
                "Service details",
                systemImage: "info.circle",
                tint: .blue
            ) {
                LabeledContent("Name", value: service.name)
                LabeledContent("Fleet state", value: status.title)
                LabeledContent("Executing members", value: ServiceSummaryStatus.executionSummary(service, prefix: ""))
            }

            ManagementDetailCard(
                "Controllers and executions",
                systemImage: "square.stack.3d.up",
                tint: .indigo
            ) {
                if service.placements.isEmpty {
                    Text("No fresh placement report")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(service.placements.enumerated()), id: \.offset) { index, placement in
                        if index > 0 {
                            Divider()
                        }
                        ServicePlacementRow(placement: placement)
                    }
                }
            }

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
        .workspaceNavigationTitle(service.name)
        .confirmationDialog(
            pendingAction(for: service.name)?.intent.confirmationTitle ?? "Confirm service action",
            isPresented: confirmationPresented(for: service.name),
            titleVisibility: .visible,
            presenting: pendingAction(for: service.name)
        ) { pending in
            Button(
                pending.intent.actionTitle,
                role: pending.intent.impact.confirmationRole
            ) {
                perform(
                    pending.action,
                    baseline: pending.baseline,
                    actionModel: actionModel
                )
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.intent.confirmationMessage)
        }
    }

    @ViewBuilder
    private func serviceActionButtons(
        _ service: ServiceObservation,
        snapshot: ServiceFleetSnapshot,
        actionModel: ServiceActionModel
    ) -> some View {
        actionButton(
            .start(name: service.name),
            service: service,
            snapshot: snapshot,
            actionModel: actionModel
        )
        actionButton(
            .reload(name: service.name),
            service: service,
            snapshot: snapshot,
            actionModel: actionModel
        )
        actionButton(
            .restart(name: service.name),
            service: service,
            snapshot: snapshot,
            actionModel: actionModel
        )

        Divider()

        actionButton(
            .stop(name: service.name),
            service: service,
            snapshot: snapshot,
            actionModel: actionModel
        )
    }

    private func actionButton(
        _ action: ServiceManagementAction,
        service: ServiceObservation,
        snapshot: ServiceFleetSnapshot,
        actionModel: ServiceActionModel
    ) -> some View {
        Button(action.title) {
            request(action, baseline: snapshot, actionModel: actionModel)
        }
        .disabled(!ServiceActionModel.canSubmit(
            action: action,
            service: service,
            snapshot: snapshot
        ))
    }

    private func request(
        _ action: ServiceManagementAction,
        baseline: ServiceFleetSnapshot,
        actionModel: ServiceActionModel
    ) {
        guard !actionModel.isBusy else {
            return
        }
        let intent = action.intent
        if intent.impact.requiresConfirmation {
            pendingAction = PendingServiceAction(
                action: action,
                baseline: baseline,
                intent: intent
            )
        } else {
            perform(action, baseline: baseline, actionModel: actionModel)
        }
    }

    private func perform(
        _ action: ServiceManagementAction,
        baseline: ServiceFleetSnapshot,
        actionModel: ServiceActionModel
    ) {
        pendingAction = nil
        Task {
            await actionModel.perform(action, baseline: baseline)
        }
    }

    private func pendingAction(for serviceName: String) -> PendingServiceAction? {
        guard pendingAction?.action.serviceName == serviceName else {
            return nil
        }
        return pendingAction
    }

    private func confirmationPresented(for serviceName: String) -> Binding<Bool> {
        Binding(
            get: { pendingAction(for: serviceName) != nil },
            set: { isPresented in
                if !isPresented {
                    pendingAction = nil
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
                Text("Connect to Claviron to load registered services.")
            } actions: {
                Button("Connect") {
                    Task {
                        await connectionModel.connect(to: serverID)
                    }
                }
            }
        case .loading:
            ProgressView("Loading services…")
        case let .failed(failure):
            ContentUnavailableView {
                Label("Services Unavailable", systemImage: "xmark.circle")
            } description: {
                Text(failure.localizedDescription)
            } actions: {
                Button("Reconnect") {
                    Task {
                        await connectionModel.reconnect(serverID)
                    }
                }
            }
        case .empty, .loaded, .stale:
            EmptyView()
        }
    }
}

nonisolated enum ServiceSummaryStatus: Equatable, Sendable {
    case running
    case waiting
    case starting
    case controllerRunning
    case stopping
    case stopped
    case failed
    case degraded
    case mixed
    case unknown

    init(lifecycle: ServiceLifecycleObservation) {
        switch lifecycle {
        case .running: self = .controllerRunning
        case .stopping: self = .stopping
        case .stopped: self = .stopped
        case .failed: self = .failed
        case .unspecified, .unrecognized: self = .unknown
        }
    }

    init(placement: ServicePlacementObservation) {
        guard let count = placement.activeExecutions else {
            self.init(lifecycle: placement.lifecycle)
            return
        }
        if count > 0 {
            self = placement.lifecycle == .stopping ? .stopping : .running
        } else if placement.lifecycle == .running {
            self = placement.dispatch == .one || placement.dispatch == .pool ? .waiting : .starting
        } else {
            self.init(lifecycle: placement.lifecycle)
        }
    }

    init(service: ServiceObservation) {
        let lifecycles = service.placements.map(\.lifecycle)
        guard !lifecycles.isEmpty else {
            self = .unknown
            return
        }

        if lifecycles.allSatisfy({ $0 == .running }) {
            if service.placements.contains(where: { ($0.activeExecutions ?? 0) > 0 }) {
                self = .running
            } else if service.placements.contains(where: { $0.activeExecutions == nil }) {
                self = .controllerRunning
            } else if service.placements.allSatisfy({ $0.dispatch == .one || $0.dispatch == .pool }) {
                self = .waiting
            } else {
                self = .starting
            }
        } else if lifecycles.allSatisfy({ $0 == .stopping }) {
            self = .stopping
        } else if lifecycles.allSatisfy({ $0 == .stopped }) {
            self = .stopped
        } else if lifecycles.allSatisfy({ $0 == .failed }) {
            self = .failed
        } else if lifecycles.contains(.failed) {
            self = .degraded
        } else if lifecycles.allSatisfy({ lifecycle in
            if case .unspecified = lifecycle { return true }
            if case .unrecognized = lifecycle { return true }
            return false
        }) {
            self = .unknown
        } else {
            self = .mixed
        }
    }

    static func instanceSummary(_ service: ServiceObservation) -> String {
        let count = service.placements.reduce(UInt64(0)) { $0 + ($1.activeExecutions ?? 0) }
        guard count > 0 else { return "" }
        return " · \(count.formatted()) \(count == 1 ? "instance" : "instances")"
    }

    static func executionSummary(_ service: ServiceObservation, prefix: String = " · ") -> String {
        let executing = service.placements.filter { ($0.activeExecutions ?? 0) > 0 }
        guard !executing.isEmpty else {
            return prefix.isEmpty ? (service.placements.contains { $0.activeExecutions == nil }
                ? "Not reported" : "None") : ""
        }
        let members = executing.map { placement in
            guard let member = placement.member else { return "Unknown member" }
            let role = switch member.role {
            case .master: "Master"
            case .worker: "Worker"
            case .standalone: "Standalone"
            case .unspecified, .unrecognized: "Member"
            }
            return "\(role) \(member.nodeID) (\(placement.activeExecutions ?? 0))"
        }
        return prefix + members.joined(separator: ", ")
    }

    var title: String {
        switch self {
        case .running: "Running"
        case .waiting: "Waiting"
        case .starting: "Starting"
        case .controllerRunning: "Controller running"
        case .stopping: "Stopping"
        case .stopped: "Stopped"
        case .failed: "Failed"
        case .degraded: "Degraded"
        case .mixed: "Mixed"
        case .unknown: "Unknown"
        }
    }

    fileprivate var color: Color {
        switch self {
        case .running: .green
        case .stopping, .degraded: .orange
        case .failed: .red
        case .stopped, .mixed, .unknown, .waiting, .starting, .controllerRunning: .secondary
        }
    }
}

private struct ServicePlacementRow: View {
    let placement: ServicePlacementObservation

    private var status: ServiceSummaryStatus {
        ServiceSummaryStatus(placement: placement)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(memberTitle)
                    .font(.body.weight(.medium))
                Spacer()
                HStack(spacing: 7) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 7, height: 7)
                    Text(status.title)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("Controller", value: ServiceSummaryStatus(lifecycle: placement.lifecycle).title)
            LabeledContent("Active executions", value: placement.activeExecutions?.formatted() ?? "Not reported")
            LabeledContent("Dispatch", value: dispatchTitle)
            if let observedAt = placement.observedAt {
                Text("Observed \(observedAt.clavironFormatted)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if let lastError = placement.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if let lastReloadError = placement.lastReloadError {
                Text(lastReloadError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 3)
    }

    private var memberTitle: String {
        guard let member = placement.member else {
            return "Unknown member"
        }

        let role = switch member.role {
        case .master: "Master"
        case .worker: "Worker"
        case .standalone: "Standalone"
        case .unspecified, .unrecognized: "Member"
        }
        return "\(role) \(member.nodeID)"
    }

    private var dispatchTitle: String {
        switch placement.dispatch {
        case .each: "Each"
        case .one: "One"
        case .pool: "Pool"
        case .unspecified: "Not reported"
        case let .unrecognized(raw): "Unknown (\(raw))"
        }
    }
}

nonisolated struct ServicePresentation {
    static let systemImage = "server.rack"
    static let assetImage = "TaskIconRust"
}

private struct PendingServiceAction: Identifiable {
    let id = UUID()
    let action: ServiceManagementAction
    let baseline: ServiceFleetSnapshot
    let intent: ManagementActionIntent
}

nonisolated extension ServiceManagementAction {
    var title: String {
        switch self {
        case let .start(name):
            "Start \(name)"
        case let .stop(name):
            "Stop \(name)"
        case let .reload(name):
            "Reload \(name)"
        case let .restart(name):
            "Restart \(name)"
        }
    }

    var intent: ManagementActionIntent {
        switch self {
        case .start:
            ManagementActionIntent(
                actionTitle: title,
                confirmationTitle: "Start this service?",
                confirmationMessage: "Claviron will start this Runnable on every registered fleet placement where it is not already running.",
                impact: .serviceWide
            )
        case .stop:
            ManagementActionIntent(
                actionTitle: title,
                confirmationTitle: "Stop this service?",
                confirmationMessage: "Claviron will drain and stop this Runnable on every registered fleet placement.",
                impact: .destructive
            )
        case .reload:
            ManagementActionIntent(
                actionTitle: title,
                confirmationTitle: "Reload this service?",
                confirmationMessage: "Claviron will reload this Runnable in place on every registered fleet placement.",
                impact: .serviceWide
            )
        case .restart:
            ManagementActionIntent(
                actionTitle: title,
                confirmationTitle: "Restart this service?",
                confirmationMessage: "Claviron will drain and replace this Runnable on every registered fleet placement.",
                impact: .serviceWide
            )
        }
    }
}
