import ClavironControlPlane
import SwiftUI

struct RuntimeOverviewView: View {
    let server: ServerProfile
    @Bindable var connectionModel: ConnectionModel

    private var connectionState: ServerConnectionState {
        connectionModel.state(for: server.id)
    }

    private var serviceState: ServiceObservationState {
        connectionModel.serviceObservationState(for: server.id)
    }

    private var overviewSummary: RuntimeOverviewSummary {
        RuntimeOverviewSummary(
            services: serviceState.snapshot,
            workers: connectionModel.workerObservationState(for: server.id).snapshot,
            applications: connectionModel.applicationObservationState(for: server.id).snapshot,
            linkedApplications: connectionModel.linkedApplicationSnapshot(for: server.id),
            tasks: connectionModel.taskObservationState(for: server.id).snapshot
        )
    }

    var body: some View {
        ManagementDetailLayout {
            resourceSummary
            serverInfoCard
            RuntimeMemoryCard(
                state: connectionModel.runtimeMemoryState(for: server.id),
                supported: connectionModel.serverInfo(for: server.id)?.capabilities.contains("metrics") == true
            )

            if let snapshot = serviceState.snapshot {
                fleetCard(snapshot)
            }
        }
        .workspaceNavigationTitle("Runtime Overview")
        .pageRefreshable(every: .seconds(2)) {
            await connectionModel.refresh(server.id)
            async let resources: Void = connectionModel.loadRuntimeResources(for: server.id)
            async let memory: Void = connectionModel.loadRuntimeMemory(for: server.id)
            _ = await (resources, memory)
        }
    }

    private var serverInfoCard: some View {
        ManagementDetailCard("Server Info", systemImage: "info.circle", tint: .blue) {
            VStack(alignment: .leading, spacing: 14) {
                if let info = connectionModel.serverInfo(for: server.id) {
                    infoGrid(serverFacts(info))
                    if let process = info.respondingProcess {
                        Divider()
                        infoGrid(processFacts(process))
                    }
                    if !info.capabilities.isEmpty {
                        Divider()
                        capabilityChips(info.capabilities)
                    }
                    if let captured = info.capturedAt {
                        Text("Observed \(captured.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text("Server information not reported.")
                        .foregroundStyle(.secondary)
                }
                if let failure = connectionModel.serverInfoFailure(for: server.id) {
                    Text(failure.localizedDescription).foregroundStyle(.red)
                }
            }
            .textSelection(.enabled)
        }
    }

    private struct InfoFact: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    private func serverFacts(_ info: ServerInfoSnapshot) -> [InfoFact] {
        [
            InfoFact(label: "Name", value: info.name),
            InfoFact(label: "Environment", value: info.environment),
            InfoFact(label: "Host", value: info.hostname),
            InfoFact(label: "Fleet", value: info.fleetName ?? "Not reported"),
            InfoFact(label: "Controller PID", value: overviewSummary.controllerPID.map(String.init) ?? "Not reported"),
            InfoFact(label: "Claviron", value: info.clavironVersion),
            InfoFact(label: "Application", value: info.applicationVersion ?? "Not reported"),
            InfoFact(
                label: "Workers",
                value: overviewSummary.workerStatus(fallback: info)
            ),
            InfoFact(label: "Reload revision", value: info.reloadRevision.map(String.init) ?? "Not reported"),
            InfoFact(label: "Started", value: info.startedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not reported"),
            InfoFact(label: "Uptime", value: uptimeLabel(info.uptime)),
            InfoFact(label: "Instance", value: info.instanceID ?? "Not reported"),
        ]
    }

    private func processFacts(_ process: ServerProcessInfo) -> [InfoFact] {
        var facts = [
            InfoFact(label: "Responding process", value: "\(process.runMode.title) · PID \(process.pid)")
        ]
        if let worker = process.workerID {
            facts.append(InfoFact(label: "Worker ID", value: String(worker)))
        }
        facts.append(contentsOf: [
            InfoFact(label: "Process started", value: process.startedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not reported"),
            InfoFact(label: "Process uptime", value: uptimeLabel(process.uptime)),
            InfoFact(label: "Process reload revision", value: String(process.reloadRevision)),
        ])
        return facts
    }

    private func infoGrid(_ facts: [InfoFact]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180), alignment: .topLeading)],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(facts) { fact in
                VStack(alignment: .leading, spacing: 2) {
                    Text(fact.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(fact.value)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func capabilityChips(_ capabilities: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Capabilities")
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(capabilities, id: \.self) { capability in
                    Text(capability)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.blue.opacity(0.15), in: Capsule())
                }
            }
        }
    }

    private func uptimeLabel(_ uptime: ProtobufDurationObservation?) -> String {
        guard let uptime else { return "Not reported" }
        return Duration.seconds(uptime.seconds).formatted(.units(allowed: [.days, .hours, .minutes, .seconds]))
    }

    private var resourceSummary: some View {
        ViewThatFits(in: .horizontal) {
            VStack(spacing: 12) {
                metricRow(RuntimeOverviewMetric.primaryRow)
            }

            VStack(spacing: 12) {
                ForEach(RuntimeOverviewMetric.primaryRow) { metric in
                    metricCard(metric)
                }
            }
        }
    }

    private func metricRow(_ metrics: [RuntimeOverviewMetric]) -> some View {
        HStack(spacing: 12) {
            ForEach(metrics) { metric in
                metricCard(metric)
                    .frame(minWidth: 145, maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func metricCard(_ metric: RuntimeOverviewMetric) -> some View {
        switch metric {
        case .workers:
            metricCard(
                "Workers", value: overviewSummary.workerCount, systemImage: "cpu", tint: .blue,
                displayValue: connectionModel.serverInfo(for: server.id)?.respondingProcess?.runMode == .standalone
                    ? "Standalone" : nil
            )
        case .services:
            metricCard("Services", value: overviewSummary.serviceCount, systemImage: "server.rack", tint: .green)
        case .applications:
            metricCard("Applications", value: overviewSummary.applicationCount, systemImage: "app.fill", tint: .indigo)
        case .tasks:
            metricCard("Tasks", value: overviewSummary.taskCount, systemImage: "checklist", tint: .orange)
        }
    }

    private func metricCard(
        _ title: String,
        value: Int?,
        systemImage: String,
        tint: Color,
        displayValue: String? = nil
    ) -> some View {
        ManagementDetailCard(title, systemImage: systemImage, tint: tint) {
            Text(displayValue ?? value?.formatted() ?? "—")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(displayValue == nil ? Color.primary : tint)
                .contentTransition(.numericText())
                .accessibilityLabel(displayValue ?? value.map(String.init) ?? "Not reported")
        }
    }

    private func fleetCard(_ snapshot: ServiceFleetSnapshot) -> some View {
        ManagementDetailCard(
            "Latest Service Fleet Observation",
            systemImage: snapshot.coverage.systemImage,
            tint: snapshot.coverage.tint
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(snapshot.coverage.title)
                    Spacer()
                    observationBadge
                }
                LabeledContent(
                    "Members reporting",
                    value: "\(snapshot.membersReporting) / \(snapshot.membersExpected)"
                )
                LabeledContent(
                    "Registered services",
                    value: snapshot.services.count.formatted()
                )
                LabeledContent(
                    "Captured",
                    value: snapshot.capturedAt?.clavironFormatted ?? "Not reported"
                )
            }
        }
    }

    @ViewBuilder
    private var observationBadge: some View {
        switch serviceState {
        case .loading(previous: .some):
            Label("Refreshing", systemImage: "arrow.clockwise")
                .foregroundStyle(.secondary)
        case .stale:
            Label("Stale", systemImage: "clock.badge.exclamationmark")
                .foregroundStyle(.orange)
        case .disconnected, .loading(previous: nil), .empty, .loaded, .failed:
            EmptyView()
        }
    }
}

struct RuntimeOverviewSummary: Equatable {
    let workerCount: Int?
    let workersRunning: Int?
    let workersExpected: UInt32?
    let controllerPID: UInt32?
    let serviceCount: Int?
    let applicationCount: Int?
    let taskCount: Int?

    init(
        services: ServiceFleetSnapshot?,
        workers: WorkerFleetSnapshot?,
        applications: ApplicationFleetSnapshot?,
        linkedApplications: LinkedApplicationSnapshot? = nil,
        tasks: TaskFleetSnapshot?
    ) {
        workerCount = workers?.workers.count
        workersRunning = workers?.workers.filter { $0.lifecycle == .running }.count
        workersExpected = workers?.workersExpected
        controllerPID = workers?.master?.process?.pid
        serviceCount = services?.services.count
        // Count reachable runners once, not once per worker lane. Configured
        // but disconnected destinations remain in the list, not the live total.
        applicationCount = applications == nil && linkedApplications == nil ? nil
            : (applications?.applications.count ?? 0)
                + (linkedApplications?.applications.filter { $0.link == .connected }.count ?? 0)
        taskCount = tasks?.tasks.count
    }

    /// Prefer the same fleet observation as the Workers card, not the older
    /// GetInfo captured at connection time. Preserve missing values before it arrives.
    func workerStatus(fallback info: ServerInfoSnapshot) -> String {
        if info.respondingProcess?.runMode == .standalone {
            return "Standalone"
        }
        let running = workersRunning.map(String.init) ?? info.workersRunning.map(String.init) ?? "—"
        let expected = workersExpected.map(String.init) ?? info.workersDesired.map(String.init) ?? "—"
        return "\(running) / \(expected)"
    }
}

nonisolated enum RuntimeOverviewMetric: String, CaseIterable, Identifiable {
    case workers
    case services
    case applications
    case tasks

    static let primaryRow: [Self] = [.workers, .services, .applications, .tasks]

    var id: Self { self }
}



private extension FleetCoverage {
    var title: String {
        switch self {
        case .complete:
            "Complete fleet report"
        case .partial:
            "Partial fleet report"
        case .noReports:
            "No fleet members reporting"
        }
    }

    var systemImage: String {
        switch self {
        case .complete:
            "checkmark.circle"
        case .partial, .noReports:
            "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .complete:
            .green
        case .partial, .noReports:
            .orange
        }
    }
}

extension Date {
    var clavironFormatted: String {
        formatted(date: .abbreviated, time: .standard)
    }
}
