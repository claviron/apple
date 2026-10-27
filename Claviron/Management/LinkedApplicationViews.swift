import ClavironControlPlane
import Foundation
import SwiftUI

/// How a linked runner reads in the Applications list: what it is, which fleet
/// it is linked through, and whether the edge can reach it. The runner owns its
/// process; the edge observes only the Link, so no process state is claimed.
struct LinkedApplicationPresentation {
    let application: LinkedApplicationObservation

    var name: String {
        application.id.map {
            ManagementResourceName.title($0.name, fallback: "Unnamed Application")
        } ?? "Unidentified Application"
    }

    var runtime: ApplicationIconPresentation {
        ApplicationIconPresentation(application.description?.icon, runtime: application.description?.runtime ?? application.runtime)
    }

    /// `PHP · Linked · octane`, or `Linked · octane` for a runner that has
    /// never joined and so advertised no runtime.
    var detail: String {
        [application.description?.summary ?? runtime.title, transport, application.id?.fleetName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var transport: String? {
        switch application.transport.lowercased() {
        case "orbit": "Orbit"
        case "": nil
        default: application.transport
        }
    }

    var link: String {
        switch application.link {
        case .connected: "Connected"
        case .disconnected: "Disconnected"
        case .unspecified, .unrecognized: "Link unknown"
        }
    }

    /// `Connected · 4 lanes`, `Disconnected`.
    var status: ManagementResourceStatus {
        switch application.link {
        case .connected:
            let lanes = application.connectedLanes
            return ManagementResourceStatus(
                title: "Connected · \(lanes) \(lanes == 1 ? "lane" : "lanes")",
                color: .green
            )
        case .disconnected:
            return ManagementResourceStatus(title: link, color: .secondary)
        case .unspecified, .unrecognized:
            return ManagementResourceStatus(title: link, color: .secondary)
        }
    }

    /// A disconnected runner has no inbox to take a command.
    var canReceive: Bool {
        application.link == .connected && application.id != nil
    }
}

extension LinkedApplicationAction {
    var title: String {
        switch self {
        case let .start(_, application):
            "Start \(ManagementResourceName.title(application.name, fallback: "Application"))"
        case let .stop(_, application):
            "Stop \(ManagementResourceName.title(application.name, fallback: "Application"))"
        case let .restart(_, application):
            "Restart \(ManagementResourceName.title(application.name, fallback: "Application"))"
        case let .command(_, name, _):
            "Command \(name)"
        }
    }

    /// Stopping or restarting a hosted application ends the work it serves.
    var requiresConfirmation: Bool {
        switch self {
        case .stop, .restart: true
        case .start, .command: false
        }
    }

    /// The same action on a native application, for the native rules.
    var native: ApplicationManagementAction? {
        switch self {
        case let .start(_, application): .start(id: application)
        case let .stop(_, application): .stop(id: application)
        case let .restart(_, application): .restart(id: application)
        case .command: nil
        }
    }
}

struct LinkedApplicationDetailView: View {
    let serverID: ServerID
    @Bindable var connectionModel: ConnectionModel
    let id: LinkedApplicationIDObservation

    @State private var outcome: Outcome = .idle
    @State private var pendingAction: LinkedApplicationAction?
    @State private var composingCommand = false
    @State private var commandName = ""
    @State private var commandPayload = ""

    enum Outcome: Equatable {
        case idle
        case busy(LinkedApplicationAction)
        case accepted(LinkedApplicationAction)
        case rejected(LinkedApplicationAction)
        case failed(String)
    }

    private var application: LinkedApplicationObservation? {
        connectionModel.linkedApplicationSnapshot(for: serverID)?
            .applications.first { $0.id == id }
    }

    var body: some View {
        if let application {
            detail(LinkedApplicationPresentation(application: application))
        } else {
            ContentUnavailableView("Application Unavailable", systemImage: "questionmark.diamond")
        }
    }

    private func detail(_ presentation: LinkedApplicationPresentation) -> some View {
        let application = presentation.application
        return ManagementDetailLayout {
            ManagementResourceHeaderCard(
                kind: "Linked Application",
                name: presentation.name,
                systemImage: presentation.runtime.systemImage,
                assetImage: presentation.runtime.assetImage,
                assetIsTemplate: false,
                iconTint: nil,
                status: presentation.status.title,
                statusColor: presentation.status.color,
                actionsDisabled: isBusy || !presentation.canReceive
            ) {
                if let hosted = application.hosted {
                    ForEach(Array(hosted.applications.enumerated()), id: \.offset) { _, hostedApplication in
                        if let applicationID = hostedApplication.applicationID {
                            Section {
                                hostedButton(.start(link: id, application: applicationID), hostedApplication, hosted, presentation.canReceive)
                                hostedButton(.restart(link: id, application: applicationID), hostedApplication, hosted, presentation.canReceive)
                                hostedButton(.stop(link: id, application: applicationID), hostedApplication, hosted, presentation.canReceive)
                            }
                        }
                    }
                }
                Button("Send Command…") {
                    composingCommand = true
                }
            }

            if outcome != .idle {
                ManagementDetailCard("Command result", systemImage: "terminal", tint: .orange) {
                    outcomeView
                }
            }

            ManagementDetailCard("Link", systemImage: "point.3.connected.trianglepath.dotted", tint: .teal) {
                LabeledContent("Transport", value: presentation.transport ?? "Not reported")
                LabeledContent("Link fleet", value: id.fleetName)
                LabeledContent("Runtime", value: presentation.runtime.title ?? "Not advertised")
                LabeledContent("Connection", value: presentation.link)
                LabeledContent("Connected lanes", value: String(application.connectedLanes))
                ForEach(application.lanes, id: \.lane) { lane in
                    LabeledContent(
                        "Lane \(lane.lane)",
                        value: "pid \(lane.pid.map(String.init) ?? "not reported") · incarnation \(lane.incarnation)"
                    )
                }
            }

            hostedCard(application, canReceive: presentation.canReceive)
        }
        .workspaceNavigationTitle(presentation.name)
        .pageRefreshable(every: .seconds(2)) {
            await connectionModel.loadLinkedApplications(for: serverID)
        }
        .confirmationDialog(
            pendingAction.map { "\($0.title)?" } ?? "Confirm",
            isPresented: confirmationPresented,
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            Button(action.title, role: .destructive) {
                perform(action)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The runner carries this out; the edge only delivers it through the Link.")
        }
        .sheet(isPresented: $composingCommand) {
            commandSheet
        }
    }

    /// What the runner reported hosting. Absent is not stopped: the runner
    /// may simply not have reported yet.
    @ViewBuilder
    private func hostedCard(
        _ application: LinkedApplicationObservation,
        canReceive: Bool
    ) -> some View {
        ManagementDetailCard("Hosted applications", systemImage: "square.stack.3d.up", tint: .blue) {
            if let hosted = application.hosted {
                if hosted.applications.isEmpty {
                    Text("The runner reported no applications.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(hosted.applications.enumerated()), id: \.offset) { _, hostedApplication in
                    hostedRow(hostedApplication, snapshot: hosted, canReceive: canReceive)
                }
                LabeledContent(
                    "Reported",
                    value: hosted.capturedAt?.clavironFormatted ?? "Not reported"
                )
            } else {
                Text("The runner has not reported its applications yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func hostedRow(
        _ hostedApplication: ApplicationObservation,
        snapshot: ApplicationFleetSnapshot,
        canReceive: Bool
    ) -> some View {
        let status = ManagementResourceStatus.aggregate(
            hostedApplication.placements.map(\.lifecycle),
            display: { ManagementResourceStatus(title: $0.title, color: $0.color) },
            isFailure: { $0 == .failed }
        )
        let name = hostedApplication.applicationID.map {
            ManagementResourceName.title($0.name, fallback: "Unnamed Application")
        } ?? "Unidentified Application"
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name).font(.headline)
                if let detail = hostedApplication.description?.summary
                    ?? ApplicationRuntimePresentation(hostedApplication.applicationID?.runtime).title {
                    Text(detail).foregroundStyle(.secondary)
                }
                Spacer()
                Text(status.title).foregroundStyle(status.color)
            }
            if let applicationID = hostedApplication.applicationID {
                HStack {
                    hostedButton(.start(link: id, application: applicationID), hostedApplication, snapshot, canReceive)
                    hostedButton(.restart(link: id, application: applicationID), hostedApplication, snapshot, canReceive)
                    hostedButton(.stop(link: id, application: applicationID), hostedApplication, snapshot, canReceive)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            ForEach(Array(hostedApplication.placements.enumerated()), id: \.offset) { _, placement in
                ApplicationPlacementRow(placement: placement)
            }
        }
        .padding(.vertical, 4)
    }

    private func hostedButton(
        _ action: LinkedApplicationAction,
        _ hostedApplication: ApplicationObservation,
        _ snapshot: ApplicationFleetSnapshot,
        _ canReceive: Bool
    ) -> some View {
        let allowed = action.native.map {
            ApplicationActionModel.canSubmit(action: $0, application: hostedApplication, snapshot: snapshot)
        } ?? true
        return Button(action.title) {
            request(action)
        }
        .disabled(isBusy || !canReceive || !allowed)
    }

    private var commandSheet: some View {
        NavigationStack {
            Form {
                TextField("Command", text: $commandName)
                TextField("Payload", text: $commandPayload, axis: .vertical)
                Text("The runner defines what a command means; the edge only delivers it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Send Command")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { composingCommand = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        let name = commandName.trimmingCharacters(in: .whitespacesAndNewlines)
                        composingCommand = false
                        perform(.command(link: id, name: name, payload: Data(commandPayload.utf8)))
                    }
                    .disabled(commandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var outcomeView: some View {
        switch outcome {
        case .idle:
            EmptyView()
        case let .busy(action):
            Label("\(action.title) requested…", systemImage: "hourglass")
        case let .accepted(action):
            VStack(alignment: .leading, spacing: 6) {
                Label("\(action.title) delivered", systemImage: "checkmark.circle")
                Text("Delivered to the runner's Link inbox; the runner carries it out. Refresh to see the result.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Refresh") {
                    Task { await connectionModel.loadLinkedApplications(for: serverID) }
                }
            }
        case let .rejected(action):
            Label("\(action.title) was not accepted", systemImage: "xmark.octagon")
                .foregroundStyle(.red)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    private var isBusy: Bool {
        if case .busy = outcome { true } else { false }
    }

    private func request(_ action: LinkedApplicationAction) {
        if action.requiresConfirmation {
            pendingAction = action
        } else {
            perform(action)
        }
    }

    private func perform(_ action: LinkedApplicationAction) {
        pendingAction = nil
        outcome = .busy(action)
        Task {
            do {
                let receipt = try await connectionModel.performLinkedApplicationAction(
                    action,
                    for: serverID
                )
                outcome = receipt.accepted ? .accepted(action) : .rejected(action)
            } catch {
                outcome = .failed(error.localizedDescription)
            }
        }
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingAction != nil },
            set: { if !$0 { pendingAction = nil } }
        )
    }
}
