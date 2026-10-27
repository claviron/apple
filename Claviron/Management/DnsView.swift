import ClavironControlPlane
import SwiftUI

/// Zones and their records in the authoritative DNS store.
///
/// Each presenting surface owns its own sheet and confirmation: a sheet
/// attached to the stack root is not presented while a pushed zone detail
/// covers it, so the zone list and the zone detail present independently.
struct DnsView: View {
    @Environment(\.isWorkspacePageActive) private var isWorkspacePageActive
    let serverID: ServerID
    @Bindable var connectionModel: ConnectionModel
    @State private var selectedDomain: String?
    @NavigationDetailPath(.dns) private var navigationPath: [String] = []
    @State private var editor: DnsEditor?
    @State private var pendingRemoval: DnsRemoval?
    @State private var outcome: DnsActionOutcome?
    @State private var isPerforming = false

    private var state: DnsZoneObservationState {
        connectionModel.dnsZoneObservationState(for: serverID)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if let snapshot = state.snapshot {
                    zoneList(snapshot)
                } else {
                    unavailableContent
                }
            }
            .workspaceNavigationTitle("DNS")
            .toolbar {
                if isWorkspacePageActive {
                    ToolbarItemGroup {
                        reloadButton
                        Button {
                            editor = .newZone
                        } label: {
                            Label("Add Zone", systemImage: "plus")
                        }
                        .disabled(isPerforming || state.snapshot == nil)
                    }
                }
            }
            .sheet(item: $editor) { editor in
                DnsEditorSheet(editor: editor) { action in
                    await submit(action)
                }
            }
            .dnsRemovalConfirmation($pendingRemoval) { action in
                Task { await perform(action) }
            }
            .managementDestination(for: String.self) { domain in
                if let zone = zone(named: domain) {
                    DnsZoneDetailView(
                        serverID: serverID,
                        connectionModel: connectionModel,
                        zone: zone,
                        outcome: outcome,
                        isPerforming: isPerforming,
                        submit: { action in await submit(action) },
                        perform: { action in await perform(action) }
                    )
                } else {
                    ContentUnavailableView("Zone Unavailable", systemImage: "questionmark.diamond")
                }
            }
        }
        .pageRefreshable(every: .seconds(2)) {
            await connectionModel.loadDnsZones(for: serverID)
        }
    }

    private var reloadButton: some View {
        Button {
            Task { await perform(.reload) }
        } label: {
            Label("Reload DNS", systemImage: "arrow.triangle.2.circlepath")
        }
        .help("Force every DNS server to reload from the store. Writes already reload on their own.")
        .disabled(isPerforming || state.snapshot == nil)
    }

    // MARK: Zone list

    private func zoneList(_ snapshot: DnsInventorySnapshot) -> some View {
        List {
            if let outcome {
                Section {
                    DnsOutcomeRow(outcome: outcome)
                }
            }
            if snapshot.zones.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Zones", systemImage: DnsPresentation.systemImage)
                    } description: {
                        Text("The DNS store holds no authoritative zones.")
                    } actions: {
                        Button("Add Zone") { editor = .newZone }
                    }
                }
            } else {
                Section {
                    ForEach(snapshot.zones) { zone in
                        let domain = zone.configuration?.domain ?? ""
                        let status = Self.status(enabled: zone.configuration?.enabled)
                        ManagementResourceRow(
                            name: domain.isEmpty ? "Unidentified zone" : domain,
                            systemImage: DnsPresentation.systemImage,
                            detail: "serial \(zone.serial)",
                            status: status.title,
                            statusColor: status.color,
                            isSelected: selectedDomain == domain,
                            select: { selectedDomain = domain },
                            open: { open(domain) }
                        )
                        .contextMenu {
                            Button("Open", systemImage: "arrow.right.circle") { open(domain) }
                            Button("Edit Zone…", systemImage: "pencil") { editor = .zone(zone) }
                                .disabled(zone.configuration == nil)
                            Button("Add Record…", systemImage: "plus") {
                                editor = .newRecord(zone: domain)
                            }
                            .disabled(domain.isEmpty)
                            Button("Copy Domain", systemImage: "doc.on.doc") { Clipboard.copy(domain) }
                                .disabled(domain.isEmpty)
                            Divider()
                            Button("Remove Zone…", systemImage: "trash", role: .destructive) {
                                pendingRemoval = .zone(zone)
                            }
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

    // MARK: Actions

    private func open(_ domain: String) {
        guard !domain.isEmpty, navigationPath.last != domain else {
            return
        }
        navigationPath.append(domain)
    }

    private func zone(named domain: String) -> DnsZoneObservation? {
        state.snapshot?.zones.first { $0.configuration?.domain == domain }
    }

    /// Editor submissions: a failure stays in the sheet, success closes it.
    private func submit(_ action: DnsManagementAction) async -> String? {
        await perform(action)
        if case let .failed(_, failure) = outcome {
            return failure.localizedDescription
        }
        return nil
    }

    private func perform(_ action: DnsManagementAction) async {
        isPerforming = true
        defer { isPerforming = false }
        do {
            let receipt = try await connectionModel.performDnsAction(action, for: serverID)
            outcome = .succeeded(action, receipt)
            if case .removeZone = action, case let .removed(zone, _) = receipt {
                navigationPath.removeAll { $0 == zone }
            }
            if case let .updateZone(_, configuration) = action,
               let index = navigationPath.lastIndex(where: { zone(named: $0) == nil }) {
                navigationPath[index] = configuration.domain
            }
        } catch {
            let failure = error as? ClavironClientFailure ?? ClavironClientFailure(
                kind: .unknown,
                diagnosticDetail: String(describing: error)
            )
            outcome = .failed(action, failure)
        }
    }

    // MARK: Unavailable

    @ViewBuilder
    private var unavailableContent: some View {
        switch state {
        case .disconnected:
            ContentUnavailableView {
                Label("Disconnected", systemImage: "network.slash")
            } description: {
                Text("Connect to Claviron to load the DNS zones.")
            } actions: {
                Button("Connect") {
                    Task { await connectionModel.loadDnsZones(for: serverID) }
                }
            }
        case .loading(previous: nil):
            ProgressView("Loading DNS…")
        case let .failed(failure):
            ContentUnavailableView {
                Label("DNS Unavailable", systemImage: "xmark.circle")
            } description: {
                Text(failure.localizedDescription)
            } actions: {
                Button("Try Again") {
                    Task { await connectionModel.loadDnsZones(for: serverID) }
                }
            }
        case .loading(previous: .some), .empty, .loaded, .stale:
            EmptyView()
        }
    }

    // MARK: Presentation

    static func status(enabled: Bool?) -> ManagementResourceStatus {
        switch enabled {
        case true: ManagementResourceStatus(title: "Enabled", color: .green)
        case false: ManagementResourceStatus(title: "Disabled", color: .secondary)
        case nil: .unknown
        }
    }

    static func seconds(_ value: UInt32) -> String {
        let duration = Duration.seconds(Int64(value))
        let units = duration.formatted(.units(allowed: [.days, .hours, .minutes, .seconds], width: .abbreviated))
        return "\(value) s (\(units))"
    }
}

// MARK: - Zone detail

/// One zone: its SOA and its records. It presents its own editor sheet and
/// removal confirmation, because it is the visible surface while pushed.
private struct DnsZoneDetailView: View {
    let serverID: ServerID
    @Bindable var connectionModel: ConnectionModel
    let zone: DnsZoneObservation
    let outcome: DnsActionOutcome?
    let isPerforming: Bool
    let submit: (DnsManagementAction) async -> String?
    let perform: (DnsManagementAction) async -> Void

    @State private var editor: DnsEditor?
    @State private var pendingRemoval: DnsRemoval?

    private var domain: String { zone.configuration?.domain ?? "" }

    private var recordState: DnsRecordObservationState {
        connectionModel.dnsRecordObservationState(for: serverID, zone: domain)
    }

    var body: some View {
        let status = DnsView.status(enabled: zone.configuration?.enabled)
        ManagementDetailLayout {
            ManagementResourceHeaderCard(
                kind: "Zone",
                name: domain.isEmpty ? "Unidentified zone" : domain,
                systemImage: DnsPresentation.systemImage,
                status: status.title,
                statusColor: status.color,
                actionsDisabled: isPerforming || zone.configuration == nil
            ) {
                Button("Edit Zone…", systemImage: "pencil") { editor = .zone(zone) }
                Button("Add Record…", systemImage: "plus") { editor = .newRecord(zone: domain) }
                Button("Copy Domain", systemImage: "doc.on.doc") { Clipboard.copy(domain) }
                Button("Copy Records as Zone File", systemImage: "text.alignleft") {
                    if let records = recordState.snapshot?.records {
                        Clipboard.copy(DnsRecordPresentation.zoneFile(records))
                    }
                }
                .disabled(recordState.snapshot?.records.isEmpty ?? true)
                Divider()
                Button("Remove Zone…", systemImage: "trash", role: .destructive) {
                    pendingRemoval = .zone(zone)
                }
            }

            if let outcome {
                ManagementDetailCard("Command result", systemImage: "terminal", tint: .orange) {
                    DnsOutcomeRow(outcome: outcome)
                }
            }

            ManagementDetailCard("Zone details", systemImage: "info.circle", tint: .blue) {
                HStack {
                    Spacer()
                    Button {
                        editor = .zone(zone)
                    } label: {
                        Label("Edit Zone", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isPerforming || zone.configuration == nil)
                }
                LabeledContent("Domain", value: domain)
                LabeledContent("ID", value: zone.id.formatted())
                LabeledContent("Serial", value: String(zone.serial))
                LabeledContent(
                    "Enabled",
                    value: zone.configuration.map { $0.enabled ? "Yes" : "No" } ?? "Not reported"
                )
            }

            ManagementDetailCard("Start of authority", systemImage: "seal", tint: .indigo) {
                if let soa = zone.configuration?.soa {
                    LabeledContent("Primary name server", value: soa.mname)
                    LabeledContent("Responsible mailbox", value: soa.rname)
                    LabeledContent("Refresh", value: DnsView.seconds(soa.refresh))
                    LabeledContent("Retry", value: DnsView.seconds(soa.retry))
                    LabeledContent("Expire", value: DnsView.seconds(soa.expire))
                    LabeledContent("Minimum TTL", value: DnsView.seconds(soa.minimum))
                } else {
                    Text("SOA not reported")
                        .foregroundStyle(.secondary)
                }
            }

            ManagementDetailCard("Records", systemImage: "list.bullet.rectangle", tint: .teal) {
                recordsContent
            }
        }
        .workspaceNavigationTitle(domain.isEmpty ? "Zone" : domain)
        .pageRefreshable(every: .seconds(2)) {
            await connectionModel.loadDnsZones(for: serverID)
            await connectionModel.loadDnsRecords(for: serverID, zone: domain)
        }
        .sheet(item: $editor) { editor in
            DnsEditorSheet(editor: editor) { action in
                await submit(action)
            }
        }
        .dnsRemovalConfirmation($pendingRemoval) { action in
            Task { await perform(action) }
        }
    }

    @ViewBuilder
    private var recordsContent: some View {
        HStack {
            if case .loading = recordState {
                ProgressView()
                    .controlSize(.small)
            }
            Spacer()
            Button {
                editor = .newRecord(zone: domain)
            } label: {
                Label("Add Record", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isPerforming || domain.isEmpty)
        }

        if let snapshot = recordState.snapshot {
            if snapshot.records.isEmpty {
                Text("No records")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(snapshot.records.enumerated()), id: \.element.id) { index, record in
                    if index > 0 {
                        Divider()
                    }
                    DnsRecordRow(
                        record: record,
                        isPerforming: isPerforming,
                        edit: { editor = .record(record) },
                        duplicate: { editor = .duplicateRecord(record) },
                        remove: { pendingRemoval = .record(record) }
                    )
                }
            }
            if case let .stale(_, failure) = recordState {
                Label(failure.localizedDescription, systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
            }
        } else if case let .failed(failure) = recordState {
            Label(failure.localizedDescription, systemImage: "xmark.circle")
                .foregroundStyle(.red)
            Button("Try Again") {
                Task { await connectionModel.loadDnsRecords(for: serverID, zone: domain) }
            }
        }
    }
}

// MARK: - Rows

/// A record as selectable text: copying is the system's own selection,
/// ⌘C and the text context menu. Nothing in the row is a click target; the
/// record's commands live in the trailing ⋯ menu.
private struct DnsRecordRow: View {
    let record: DnsRecordObservation
    let isPerforming: Bool
    let edit: () -> Void
    let duplicate: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let configuration = record.configuration {
                Text(configuration.type)
                    .font(.caption.weight(.semibold).monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 4))
                    .frame(minWidth: 52, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(configuration.name)
                        .font(.body.weight(.medium))
                    Text(configuration.value)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                    if let extras = Self.extras(configuration) {
                        Text(extras)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 8)
                Text("TTL \(configuration.ttl)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Circle()
                    .fill(configuration.enabled ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel(configuration.enabled ? "Enabled" : "Disabled")
            } else {
                Label("Record \(record.id) has no reported configuration", systemImage: "questionmark.diamond")
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Menu {
                commands
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(isPerforming)
            .accessibilityLabel("Record actions")
            .help("Record actions")
        }
        .padding(.vertical, 4)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private var commands: some View {
        if record.configuration != nil {
            Button("Edit…", systemImage: "pencil", action: edit)
            Button("Duplicate…", systemImage: "plus.square.on.square", action: duplicate)
            Divider()
        }
        Button("Remove Record…", systemImage: "trash", role: .destructive, action: remove)
    }

    private static func extras(_ configuration: DnsRecordConfiguration) -> String? {
        var parts: [String] = []
        if let priority = configuration.priority { parts.append("priority \(priority)") }
        if let weight = configuration.weight { parts.append("weight \(weight)") }
        if let port = configuration.port { parts.append("port \(port)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct DnsOutcomeRow: View {
    let outcome: DnsActionOutcome

    var body: some View {
        row.copyableMessage(clipboardText)
    }

    private var clipboardText: String {
        switch outcome {
        case let .succeeded(action, receipt):
            "\(action.title): \(DnsActionOutcome.summary(receipt))"
        case let .failed(action, failure):
            "\(action.title): \(failure.localizedDescription)"
        }
    }

    @ViewBuilder
    private var row: some View {
        switch outcome {
        case let .succeeded(action, receipt):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.headline)
                    Text(DnsActionOutcome.summary(receipt))
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: DnsActionOutcome.isAccepted(receipt) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(DnsActionOutcome.isAccepted(receipt) ? Color.green : Color.orange)
            }
        case let .failed(action, failure):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.headline)
                    Text(failure.localizedDescription)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }
}

private extension View {
    /// The destructive confirmation for a pending removal, on the surface
    /// that asked for it.
    func dnsRemovalConfirmation(
        _ pending: Binding<DnsRemoval?>,
        confirm: @escaping (DnsManagementAction) -> Void
    ) -> some View {
        confirmationDialog(
            pending.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { pending.wrappedValue != nil },
                set: { if !$0 { pending.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: pending.wrappedValue
        ) { removal in
            Button(removal.actionTitle, role: .destructive) {
                confirm(removal.action)
            }
            Button("Cancel", role: .cancel) {}
        } message: { removal in
            Text(removal.message)
        }
    }
}

// MARK: - State

/// Text forms of records for the pasteboard, in master-file order:
/// `name TTL IN type [priority] [weight] [port] value`.
nonisolated enum DnsPresentation {
    static let systemImage = "point.3.connected.trianglepath.dotted"
}

nonisolated enum DnsRecordPresentation {
    static func zoneFileLine(_ configuration: DnsRecordConfiguration) -> String {
        var fields = [configuration.name, String(configuration.ttl), "IN", configuration.type]
        fields += [configuration.priority, configuration.weight, configuration.port]
            .compactMap { $0.map(String.init) }
        fields.append(configuration.value)
        let line = fields.joined(separator: " ")
        return configuration.enabled ? line : "; disabled: " + line
    }

    static func zoneFile(_ records: [DnsRecordObservation]) -> String {
        records.compactMap { $0.configuration.map(zoneFileLine) }.joined(separator: "\n") + "\n"
    }
}

nonisolated enum DnsActionOutcome: Equatable, Sendable {
    case succeeded(DnsManagementAction, DnsManagementReceipt)
    case failed(DnsManagementAction, ClavironClientFailure)

    static func isAccepted(_ receipt: DnsManagementReceipt) -> Bool {
        if case let .reload(accepted) = receipt {
            return accepted
        }
        return true
    }

    /// What the receipt proves, worded no stronger than the protocol allows.
    /// A committed write is announced by the database's `dns_zone_changed`
    /// trigger; every DNS process reloads its own snapshot from that notice,
    /// so no manual reload follows a write. The receipt still proves only
    /// the commit, not that every process has already reloaded.
    static func summary(_ receipt: DnsManagementReceipt) -> String {
        switch receipt {
        case let .zone(zone):
            "Stored \(zone.configuration?.domain ?? "zone") at serial \(zone.serial). DNS servers reload on the change notice."
        case let .record(record, zoneSerial):
            "Stored in \(record.zone) at serial \(zoneSerial). DNS servers reload on the change notice."
        case let .removed(zone, zoneSerial?):
            "Removed from \(zone); serial is now \(zoneSerial). DNS servers reload on the change notice."
        case let .removed(zone, nil):
            "Removed zone \(zone). DNS servers reload on the change notice."
        case .reload(accepted: true):
            "Reload accepted. Fleet members publish the new snapshot on their own."
        case .reload(accepted: false):
            "The server did not accept the reload."
        }
    }
}

nonisolated enum DnsEditor: Identifiable, Sendable {
    case newZone
    case zone(DnsZoneObservation)
    case newRecord(zone: String)
    case record(DnsRecordObservation)
    /// A new record in the same zone, prefilled from an existing one.
    case duplicateRecord(DnsRecordObservation)

    var id: String {
        switch self {
        case .newZone: "zone.new"
        case let .zone(zone): "zone.\(zone.id)"
        case let .newRecord(zone): "record.new.\(zone)"
        case let .record(record): "record.\(record.id)"
        case let .duplicateRecord(record): "record.copy.\(record.id)"
        }
    }
}

nonisolated enum DnsRemoval: Equatable, Sendable {
    /// Removing a zone always takes its records with it; the store's
    /// foreign keys cascade, so there is no record-preserving variant.
    case zone(DnsZoneObservation)
    case record(DnsRecordObservation)

    var action: DnsManagementAction {
        switch self {
        case let .zone(zone): .removeZone(id: zone.id, cascade: true)
        case let .record(record): .removeRecord(id: record.id)
        }
    }

    var title: String {
        switch self {
        case let .zone(zone): "Remove \(zone.configuration?.domain ?? "zone")?"
        case let .record(record): "Remove \(record.configuration?.name ?? "record")?"
        }
    }

    var actionTitle: String {
        switch self {
        case .zone: "Remove Zone"
        case .record: "Remove Record"
        }
    }

    var message: String {
        switch self {
        case .zone:
            "The zone and every record in it are deleted from the store."
        case .record:
            "The record is deleted from the store and the zone serial advances."
        }
    }
}

#Preview {
    let applicationModel = ApplicationModel.preview(configuration: .preview)
    let connectionModel = ConnectionModel(applicationModel: applicationModel) { _ in
        MockClavironClient(
            results: [.success(.preview)],
            dnsZoneResults: [.success(.preview)],
            dnsRecordResults: [.success(.preview)]
        )
    }
    DnsView(
        serverID: applicationModel.configuration.activeServerID!,
        connectionModel: connectionModel
    )
}
