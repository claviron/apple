import ClavironControlPlane
import SwiftUI

/// Registrar-held domains: the store's rows, filtered by registrar, and per
/// domain the registrar's live record and delegation.
struct DomainsView: View {
    @Environment(\.isWorkspacePageActive) private var isWorkspacePageActive
    let serverID: ServerID
    @Bindable var connectionModel: ConnectionModel
    @State private var registrarFilter: String = DomainsView.everyRegistrar
    @State private var selectedDomain: String?
    @NavigationDetailPath(.domains) private var navigationPath: [String] = []
    @State private var isAddPresented = false
    @State private var isTemplatesPresented = false
    @State private var outcome: DomainActionOutcome?
    @State private var isPerforming = false

    static let everyRegistrar = ""

    private var state: DomainObservationState {
        connectionModel.domainObservationState(for: serverID)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if let snapshot = state.snapshot {
                    domainList(snapshot)
                } else {
                    unavailableContent
                }
            }
            .workspaceNavigationTitle("Domains")
            .toolbar {
                if isWorkspacePageActive {
                    ToolbarItemGroup {
                        if let snapshot = state.snapshot {
                            registrarPicker(snapshot.registrars)
                        }
                        Button {
                            Task { await perform(.sync(registrar: filterValue)) }
                        } label: {
                            Label("Sync from Registrar", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .help("Pull the registrar's domain list into the store.")
                        .disabled(isPerforming || state.snapshot == nil)
                        Button {
                            isAddPresented = true
                        } label: {
                            Label("Add Domain", systemImage: "plus")
                        }
                        .disabled(isPerforming || state.snapshot == nil)
                        Button {
                            isTemplatesPresented = true
                        } label: {
                            Label("Templates…", systemImage: "doc.text")
                        }
                        .help("Edit the contacts and nameservers a registration starts from.")
                        .disabled(state.snapshot == nil)
                    }
                }
            }
            .sheet(isPresented: $isTemplatesPresented) {
                DomainTemplateSheet(serverID: serverID, connectionModel: connectionModel) { action in
                    await submit(action)
                }
            }
            .sheet(isPresented: $isAddPresented) {
                DomainAddSheet(
                    registrars: state.snapshot?.registrars ?? [],
                    preferredRegistrar: filterValue
                ) { action in
                    await submit(action)
                }
            }
            .managementDestination(for: String.self) { name in
                if let domain = domain(named: name) {
                    DomainDetailView(
                        serverID: serverID,
                        connectionModel: connectionModel,
                        domain: domain,
                        outcome: outcome,
                        isPerforming: isPerforming,
                        perform: { action in await perform(action) }
                    )
                } else {
                    ContentUnavailableView("Domain Unavailable", systemImage: "questionmark.diamond")
                }
            }
        }
        .pageRefreshable(every: .seconds(2)) {
            await connectionModel.loadDomains(for: serverID)
        }
    }

    /// The registrar the filter names; nil stands for every registrar.
    private var filterValue: String? {
        registrarFilter == Self.everyRegistrar ? nil : registrarFilter
    }

    private func registrarPicker(_ registrars: [RegistrarObservation]) -> some View {
        Picker("Registrar", selection: $registrarFilter) {
            Text("All Registrars").tag(Self.everyRegistrar)
            ForEach(registrars) { registrar in
                Text(Self.registrarTitle(registrar)).tag(registrar.name)
            }
        }
        .pickerStyle(.menu)
        .help("Show only the domains held at one registrar.")
    }

    // MARK: Domain list

    private func domainList(_ snapshot: DomainInventorySnapshot) -> some View {
        let domains = snapshot.domains.filter { domain in
            filterValue.map { $0 == domain.registrar } ?? true
        }
        return List {
            if let outcome {
                Section {
                    DomainOutcomeRow(outcome: outcome)
                }
            }
            if !snapshot.registrars.contains(where: \.configured) {
                Section {
                    Label(
                        "No registrar is configured on this server; registrar calls will be refused until domains.yaml names one.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
            }
            if domains.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Domains", systemImage: DomainPresentation.systemImage)
                    } description: {
                        Text(filterValue.map { "The store holds no domain at \($0)." }
                            ?? "The store holds no domains.")
                    } actions: {
                        Button("Add Domain") { isAddPresented = true }
                    }
                }
            } else {
                Section {
                    ForEach(domains) { domain in
                        let status = Self.status(domain.status)
                        ManagementResourceRow(
                            name: domain.name,
                            systemImage: DomainPresentation.systemImage,
                            detail: Self.rowDetail(domain),
                            status: status.title,
                            statusColor: status.color,
                            isSelected: selectedDomain == domain.name,
                            select: { selectedDomain = domain.name },
                            open: { open(domain.name) }
                        )
                        .contextMenu {
                            Button("Open", systemImage: "arrow.right.circle") { open(domain.name) }
                            Button("Use Claviron DNS", systemImage: "point.3.connected.trianglepath.dotted") {
                                Task {
                                    await perform(.useClavironNameservers(registrar: domain.registrar, name: domain.name))
                                }
                            }
                            .disabled(isPerforming || domain.registrar.isEmpty)
                        }
                    }
                } header: {
                    Text(filterValue.map { "Domains at \($0)" } ?? "Domains")
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

    private func open(_ name: String) {
        guard navigationPath.last != name else {
            return
        }
        navigationPath.append(name)
    }

    private func domain(named name: String) -> DomainObservation? {
        state.snapshot?.domains.first { $0.name == name }
    }

    /// Sheet submissions: a failure stays in the sheet, success closes it.
    private func submit(_ action: DomainManagementAction) async -> String? {
        await perform(action)
        if case let .failed(_, failure) = outcome {
            return failure.localizedDescription
        }
        return nil
    }

    private func perform(_ action: DomainManagementAction) async {
        isPerforming = true
        defer { isPerforming = false }
        do {
            let receipt = try await connectionModel.performDomainAction(action, for: serverID)
            outcome = .succeeded(action, receipt)
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
                Text("Connect to Claviron to load the domains.")
            } actions: {
                Button("Connect") {
                    Task { await connectionModel.loadDomains(for: serverID) }
                }
            }
        case .loading(previous: nil):
            ProgressView("Loading domains…")
        case let .failed(failure):
            ContentUnavailableView {
                Label("Domains Unavailable", systemImage: "xmark.circle")
            } description: {
                Text(failure.localizedDescription)
            } actions: {
                Button("Try Again") {
                    Task { await connectionModel.loadDomains(for: serverID) }
                }
            }
        case .loading(previous: .some), .empty, .loaded, .stale:
            EmptyView()
        }
    }

    // MARK: Presentation

    static func registrarTitle(_ registrar: RegistrarObservation) -> String {
        registrar.configured ? registrar.name : "\(registrar.name) (not configured)"
    }

    static func status(_ status: DomainStatusObservation) -> ManagementResourceStatus {
        switch status {
        case .active: ManagementResourceStatus(title: "Active", color: .green)
        case .pending, .transferring: ManagementResourceStatus(title: status.title, color: .orange)
        case .expired, .suspended, .failed: ManagementResourceStatus(title: status.title, color: .red)
        case .unspecified, .unrecognized: ManagementResourceStatus(title: status.title, color: .secondary)
        }
    }

    static func rowDetail(_ domain: DomainObservation) -> String {
        var parts = [domain.registrar]
        if !domain.dnsProvider.isEmpty {
            parts.append("dns \(domain.dnsProvider)")
        }
        if let expiresAt = domain.expiresAt {
            parts.append("expires \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }
}

enum DomainPresentation {
    static let systemImage = "globe"
}

// MARK: - Detail

private struct DomainDetailView: View {
    let serverID: ServerID
    @Bindable var connectionModel: ConnectionModel
    let domain: DomainObservation
    let outcome: DomainActionOutcome?
    let isPerforming: Bool
    let perform: (DomainManagementAction) async -> Void

    @State private var nameservers: LiveLoad<DomainNameserversSnapshot> = .idle
    @State private var registrarInfo: LiveLoad<DomainRegistrarInfo> = .idle
    @State private var isNameserverSheetPresented = false
    @State private var isClavironConfirmationPresented = false
    @State private var isRenewPresented = false
    @State private var renewYears = 1

    var body: some View {
        let status = DomainsView.status(domain.status)
        ManagementDetailLayout {
            ManagementResourceHeaderCard(
                kind: "Domain",
                name: domain.name,
                systemImage: DomainPresentation.systemImage,
                assetImage: nil,
                assetIsTemplate: false,
                iconTint: nil,
                status: status.title,
                statusColor: status.color,
                actionsDisabled: isPerforming
            ) {
                Button("Use Claviron DNS", systemImage: "point.3.connected.trianglepath.dotted") {
                    isClavironConfirmationPresented = true
                }
                Button("Set Nameservers…", systemImage: "pencil") {
                    isNameserverSheetPresented = true
                }
                Button("Renew…", systemImage: "calendar.badge.plus") {
                    isRenewPresented = true
                }
                Divider()
                Button("Refresh from Registrar", systemImage: "arrow.clockwise") {
                    Task {
                        await perform(.refresh(name: domain.name))
                        await loadLive()
                    }
                }
                Button("Sync DNS Records", systemImage: "list.bullet.rectangle") {
                    Task { await perform(.syncRecords(name: domain.name)) }
                }
            }

            if let outcome {
                ManagementDetailCard("Command result", systemImage: "terminal", tint: .orange) {
                    DomainOutcomeRow(outcome: outcome)
                }
            }

            ManagementDetailCard("Store record", systemImage: "internaldrive", tint: .blue) {
                LabeledContent("Registrar", value: domain.registrar)
                LabeledContent("Reference", value: domain.registrarRef)
                LabeledContent("DNS provider", value: domain.dnsProvider.isEmpty ? "Not recorded" : domain.dnsProvider)
                LabeledContent("Status", value: domain.status.title)
                LabeledContent("Registered", value: domain.registeredAt?.formatted() ?? "Not recorded")
                LabeledContent("Expires", value: domain.expiresAt?.formatted() ?? "Not recorded")
                LabeledContent("Auto-renew", value: domain.autoRenew ? "Yes" : "No")
                LabeledContent("Renew before", value: "\(domain.renewBeforeDays) day(s)")
                LabeledContent("WHOIS privacy", value: domain.whoisPrivacy ? "Yes" : "No")
                LabeledContent("Updated", value: domain.updatedAt?.formatted() ?? "Not recorded")
            }

            ManagementDetailCard("Nameservers", systemImage: "point.3.connected.trianglepath.dotted", tint: .indigo) {
                switch nameservers {
                case .idle, .loading:
                    ProgressView("Asking \(domain.registrar)…")
                case let .failed(message):
                    Label(message, systemImage: "xmark.circle")
                        .foregroundStyle(.red)
                        .copyableMessage(message)
                case let .loaded(snapshot):
                    if snapshot.nameservers.isEmpty {
                        Text("The registrar reports no nameservers.").foregroundStyle(.secondary)
                    } else {
                        ForEach(snapshot.nameservers, id: \.self) { server in
                            Text(server).font(.body.monospaced())
                        }
                    }
                }
            }

            ManagementDetailCard("Registrar record", systemImage: "building.2", tint: .teal) {
                switch registrarInfo {
                case .idle, .loading:
                    ProgressView("Asking \(domain.registrar)…")
                case let .failed(message):
                    Label(message, systemImage: "xmark.circle")
                        .foregroundStyle(.red)
                        .copyableMessage(message)
                case let .loaded(info):
                    LabeledContent("Status", value: info.registrarStatus)
                    LabeledContent("Reference", value: info.registrarRef)
                    LabeledContent("Registered", value: info.registeredAt?.formatted() ?? "Not reported")
                    LabeledContent("Expires", value: info.expiresAt?.formatted() ?? "Not reported")
                    LabeledContent("Auto-renew", value: Self.flag(info.autoRenew))
                    LabeledContent("WHOIS privacy", value: Self.flag(info.whoisPrivacy))
                }
            }
        }
        .workspaceNavigationTitle(domain.name)
        .pageRefreshable(every: .seconds(2)) {
            await connectionModel.loadDomains(for: serverID)
            await loadLive()
        }
        .onChange(of: outcome) { _, outcome in
            if case .succeeded(.setNameservers, _) = outcome {
                Task { await loadNameservers() }
            } else if case .succeeded(.useClavironNameservers, _) = outcome {
                Task { await loadNameservers() }
            }
        }
        .sheet(isPresented: $isNameserverSheetPresented) {
            DomainNameserverSheet(
                domain: domain,
                current: nameservers.value?.nameservers ?? []
            ) { action in
                await perform(action)
                if case let .failed(_, failure) = outcome {
                    return failure.localizedDescription
                }
                return nil
            }
        }
        .sheet(isPresented: $isRenewPresented) {
            NavigationStack {
                Form {
                    Section {
                        Stepper("\(renewYears) year\(renewYears == 1 ? "" : "s")", value: $renewYears, in: 1...10)
                    } footer: {
                        Text("The registrar charges the renewal to the account domains.yaml names. The store row is replaced with the registrar's new expiry.")
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Renew \(domain.name)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isRenewPresented = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Renew") {
                            isRenewPresented = false
                            Task {
                                await perform(.renew(name: domain.name, years: UInt32(renewYears)))
                                await loadLive()
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 380, minHeight: 180)
        }
        .confirmationDialog(
            "Delegate \(domain.name) to Claviron DNS?",
            isPresented: $isClavironConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Use Claviron DNS") {
                Task { await perform(.useClavironNameservers(registrar: domain.registrar, name: domain.name)) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The registrar's delegation is replaced with the nameservers the store lists for Claviron. Records the registrar hosts stop answering once the change propagates.")
        }
    }

    private func loadLive() async {
        async let servers: Void = loadNameservers()
        async let info: Void = loadRegistrarInfo()
        _ = await (servers, info)
    }

    private func loadNameservers() async {
        nameservers = .loading
        do {
            nameservers = .loaded(try await connectionModel.loadDomainNameservers(
                for: serverID,
                registrar: domain.registrar,
                name: domain.name
            ))
        } catch {
            nameservers = .failed((error as? ClavironClientFailure)?.localizedDescription ?? String(describing: error))
        }
    }

    private func loadRegistrarInfo() async {
        registrarInfo = .loading
        do {
            registrarInfo = .loaded(try await connectionModel.loadDomainRegistrarInfo(
                for: serverID,
                registrar: domain.registrar,
                name: domain.name
            ))
        } catch {
            registrarInfo = .failed((error as? ClavironClientFailure)?.localizedDescription ?? String(describing: error))
        }
    }

    static func flag(_ value: Bool?) -> String {
        switch value {
        case true: "Yes"
        case false: "No"
        case nil: "Not reported"
        }
    }
}

/// One live registrar read owned by the view that asked for it.
private enum LiveLoad<Value: Equatable>: Equatable {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case let .loaded(value) = self {
            return value
        }
        return nil
    }
}

// MARK: - Sheets

/// Record a domain the registrar already holds. The registrar is a choice
/// from the list the server reported, never typed.
private struct DomainAddSheet: View {
    let registrars: [RegistrarObservation]
    let submit: (DomainManagementAction) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var registrar: String
    @State private var name = ""
    @State private var failure: String?
    @State private var isSubmitting = false

    init(
        registrars: [RegistrarObservation],
        preferredRegistrar: String?,
        submit: @escaping (DomainManagementAction) async -> String?
    ) {
        self.registrars = registrars
        self.submit = submit
        let configured = registrars.filter(\.configured)
        let initial = preferredRegistrar.flatMap { preferred in
            configured.first { $0.name == preferred }?.name
        } ?? configured.first?.name ?? ""
        _registrar = State(initialValue: initial)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canSubmit: Bool {
        !registrar.isEmpty && trimmedName.contains(".") && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Registrar", selection: $registrar) {
                        ForEach(registrars) { entry in
                            Text(DomainsView.registrarTitle(entry))
                                .tag(entry.name)
                                .selectionDisabled(!entry.configured)
                        }
                    }
                    TextField("Domain", text: $name, prompt: Text("example.com"))
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                } footer: {
                    Text("The registrar's own dates, reference and status are recorded; nothing is invented. The domain must already be held at the chosen registrar.")
                }
                if registrars.filter(\.configured).isEmpty {
                    Section {
                        Label("No registrar is configured on this server.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                if let failure {
                    Section {
                        Label(failure, systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                            .copyableMessage(failure)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Domain")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            isSubmitting = true
                            defer { isSubmitting = false }
                            failure = await submit(.add(registrar: registrar, name: trimmedName))
                            if failure == nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 260)
    }
}

/// Replace the delegation set, one hostname per line.
private struct DomainNameserverSheet: View {
    let domain: DomainObservation
    let submit: (DomainManagementAction) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var failure: String?
    @State private var isSubmitting = false

    init(
        domain: DomainObservation,
        current: [String],
        submit: @escaping (DomainManagementAction) async -> String?
    ) {
        self.domain = domain
        self.submit = submit
        _text = State(initialValue: current.joined(separator: "\n"))
    }

    private var hostnames: [String] {
        text.split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.body.monospaced())
                        .frame(minHeight: 120)
                } header: {
                    Text("Nameservers for \(domain.name)")
                } footer: {
                    Text("One hostname per line. The registrar replaces the whole set; a nameserver left out stops being authoritative.")
                }
                if let failure {
                    Section {
                        Label(failure, systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                            .copyableMessage(failure)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Set Nameservers")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Replace") {
                        Task {
                            isSubmitting = true
                            defer { isSubmitting = false }
                            failure = await submit(.setNameservers(
                                registrar: domain.registrar,
                                name: domain.name,
                                nameservers: hostnames
                            ))
                            if failure == nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(hostnames.isEmpty || isSubmitting)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 280)
    }
}

// MARK: - Outcome

nonisolated enum DomainActionOutcome: Equatable, Sendable {
    case succeeded(DomainManagementAction, DomainManagementReceipt)
    case failed(DomainManagementAction, ClavironClientFailure)

    /// The whole message as shown, one line per failed domain on a sync.
    static func clipboardText(_ outcome: DomainActionOutcome) -> String {
        switch outcome {
        case let .succeeded(action, receipt):
            var lines = ["\(action.title): \(summary(receipt))"]
            if case let .sync(sync) = receipt {
                lines.append(contentsOf: sync.failed.map { "\($0.domain): \($0.message)" })
            }
            return lines.joined(separator: "\n")
        case let .failed(action, failure):
            return "\(action.title): \(failure.localizedDescription)"
        }
    }

    static func summary(_ receipt: DomainManagementReceipt) -> String {
        switch receipt {
        case let .template(template):
            "Template \(template.name) stored."
        case let .templateRemoved(name, removed):
            removed ? "Template \(name) removed." : "No template named \(name)."
        case let .domain(domain):
            "\(domain.name) now reads \(domain.status.title.lowercased()) at \(domain.registrar)"
                + (domain.expiresAt.map { ", expires \($0.formatted(date: .abbreviated, time: .omitted))." } ?? ".")
        case let .nameservers(snapshot):
            snapshot.nameservers.isEmpty
                ? "\(snapshot.name): registrar reports no nameservers."
                : "\(snapshot.name) now delegates to \(snapshot.nameservers.joined(separator: ", "))."
        case let .sync(sync):
            "found \(sync.found), created \(sync.created.count), updated \(sync.updated.count), skipped \(sync.skipped), failed \(sync.failed.count)."
        }
    }
}

private struct DomainOutcomeRow: View {
    let outcome: DomainActionOutcome

    var body: some View {
        row.copyableMessage(DomainActionOutcome.clipboardText(outcome))
    }

    @ViewBuilder
    private var row: some View {
        switch outcome {
        case let .succeeded(action, receipt):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title).font(.headline)
                    Text(DomainActionOutcome.summary(receipt)).foregroundStyle(.secondary)
                    if case let .sync(sync) = receipt {
                        ForEach(Array(sync.failed.enumerated()), id: \.offset) { _, failure in
                            Text("\(failure.domain): \(failure.message)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
            }
        case let .failed(action, failure):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title).font(.headline)
                    Text(failure.localizedDescription).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Color.red)
            }
        }
    }
}
