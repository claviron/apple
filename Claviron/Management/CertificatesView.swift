import ClavironControlPlane
#if os(macOS)
import AppKit
#endif
import SwiftUI
import UniformTypeIdentifiers

struct CertificatesView: View {
    @Environment(\.isWorkspacePageActive) private var isWorkspacePageActive
    let serverID: ServerID
    @Bindable var connectionModel: ConnectionModel
    @State private var selectedCertificateIndex: Int?
    @NavigationDetailPath(.certificates) private var navigationPath: [Int] = []
    @State private var issuing: CertificateIssuer?
    @State private var pendingRemoval: String?
    @State private var pendingRevocation: String?
    @State private var renewing = false
    @State private var outcome: CertificateActionOutcome?
    @State private var isPerforming = false
    @State private var group: CertificateGroup = .all
    @State private var importing = false
    @State private var pendingKeyExport: String?
    @State private var exportDocument: CertificatePEMDocument?
    @State private var exporting = false
    @State private var exportingKey = false
    @State private var transferError: String?

    private var state: CertificateObservationState {
        connectionModel.certificateObservationState(for: serverID)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if let snapshot = state.snapshot {
                    certificateList(snapshot)
                } else {
                    unavailableContent
                }
            }
            .workspaceNavigationTitle("Certificates")
            .toolbar {
                if isWorkspacePageActive {
                    ToolbarItem {
                        Menu {
                            Button("Import Certificate…", systemImage: "square.and.arrow.down") {
                                importing = true
                            }
                            Divider()
                            Button("Issue with ACME…", systemImage: "globe") {
                                issuing = .acme
                            }
                            Button("Issue from Local CA…", systemImage: "seal") {
                                issuing = .localCA
                            }
                            Divider()
                            Button("Create Root CA…", systemImage: "seal.fill") {
                                issuing = .rootCA
                            }
                        } label: {
                            Label("Add Certificate", systemImage: "plus")
                        }
                        .help("Issue a certificate through ACME or from the local CA")
                        .disabled(isPerforming || state.snapshot == nil)
                    }
                }
            }
            .sheet(item: $issuing) { issuer in
                switch issuer {
                case .acme:
                    AddCertificateSheet { action in await perform(action) }
                case .localCA:
                    LocalCertificateSheet(
                        submit: { action in await perform(action) },
                        authorities: localAuthorities,
                        context: certificateIssuanceContext
                    )
                case .rootCA:
                    RootCASheet { action in await perform(action) }
                }
            }
            .sheet(isPresented: $importing) {
                ImportCertificateSheet { action in await perform(action) }
            }
            .certificateRemovalConfirmation($pendingRemoval) { commonName in
                Task { await perform(.remove(commonName: commonName)) }
            }
            .certificateRevocationConfirmation($pendingRevocation) { commonName in
                Task { await perform(.revoke(commonName: commonName)) }
            }
            .managementDestination(for: Int.self) { index in
                if let snapshot = state.snapshot,
                   snapshot.certificates.indices.contains(index) {
                    CertificateDetailView(
                        hosted: snapshot.certificates[index],
                        outcome: outcome,
                        isPerforming: isPerforming,
                        perform: { action in await perform(action) },
                        export: { key in
                            let name = snapshot.certificates[index].certificate?.commonName ?? ""
                            if key { pendingKeyExport = name }
                            else { Task { await export(commonName: name, key: false) } }
                        },
                        chain: {
                            let name = snapshot.certificates[index].certificate?.commonName ?? ""
                            return await chainPEM(commonName: name)
                        }
                    )
                    .pageRefreshable(every: .seconds(2)) {
                        await connectionModel.loadCertificates(for: serverID)
                    }
                } else {
                    ContentUnavailableView("Certificate Unavailable", systemImage: "questionmark.diamond")
                }
            }
        }
        // Presented from the stack, not from its root: the export and its
        // confirmation are asked for from a pushed detail view, and a panel
        // attached to a view the stack has covered does not appear.
        .confirmationDialog("Export unencrypted private key?", isPresented: Binding(
            get: { pendingKeyExport != nil },
            set: { if !$0 { pendingKeyExport = nil } }
        ), titleVisibility: .visible) {
            if let name = pendingKeyExport {
                Button("Export Private Key") {
                    pendingKeyExport = nil
                    Task { await export(commonName: name, key: true) }
                }
            }
        } message: {
            Text("Anyone with this key can use the certificate's identity. Save it only to a trusted location.")
        }
        .fileExporter(isPresented: $exporting, document: exportDocument,
                      contentType: .data, defaultFilename: exportingKey ? "private-key.key" : "certificate.crt") { result in
            defer { exportDocument = nil }
            do {
                let url = try result.get()
                if exportingKey {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                }
            } catch { transferError = error.localizedDescription }
        }
        .alert("Certificate Transfer Failed", isPresented: Binding(
            get: { transferError != nil }, set: { if !$0 { transferError = nil } }
        )) {
            Button("OK") { transferError = nil }
        } message: { Text(transferError ?? "") }
        .pageRefreshable(every: .seconds(2)) {
            await connectionModel.loadCertificates(for: serverID)
        }
    }

    private var certificateIssuanceContext: CertificateIssuanceContext? {
        guard let sessionID = connectionModel.managementSessionID(for: serverID) else { return nil }
        return CertificateIssuanceContext(serverID: serverID, connection: connectionModel, sessionID: sessionID)
    }

    /// The CA certificates the server holds, for "Signed by".
    private var localAuthorities: [String] {
        (state.snapshot?.certificates ?? [])
            .filter { CertificateGroup.ca.contains($0.certificate) && $0.certificate?.enabled == true }
            .compactMap { $0.certificate?.commonName.nonEmpty }
            .sorted()
    }

    private func certificateList(_ snapshot: CertificateInventorySnapshot) -> some View {
        List {
            Section {
                Picker("Certificate type", selection: $group) {
                    ForEach(CertificateGroup.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if let outcome {
                Section {
                    CertificateOutcomeRow(outcome: outcome)
                }
            }
            if snapshot.certificates.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Persisted Certificates", systemImage: "checkmark.shield")
                    } description: {
                        Text("The complete certificate inventory contains no certificates.")
                    } actions: {
                        Button("Issue with ACME") { issuing = .acme }
                        Button("Issue from Local CA") { issuing = .localCA }
                    }
                }
            } else {
                if !snapshot.certificates.contains(where: { group.contains($0.certificate) }) {
                    Text("No \(group.rawValue.lowercased()) certificates")
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(Array(snapshot.certificates.enumerated()).filter { group.contains($0.element.certificate) }, id: \.offset) { index, hosted in
                        let status = Self.status(hosted)
                        let commonName = hosted.certificate?.commonName ?? ""
                        ManagementResourceRow(
                            name: commonName.nonEmpty ?? "Unidentified certificate",
                            systemImage: "checkmark.shield",
                            detail: hosted.certificate?.expiresAt.map { "expires \($0.reportedDate)" },
                            warningBadge: hosted.certificate?.revokedAt != nil ? "Revoked" : nil,
                            status: status.title,
                            statusColor: status.color,
                            isSelected: selectedCertificateIndex == index,
                            select: { selectedCertificateIndex = index },
                            open: { navigationPath.append(index) }
                        )
                        .contextMenu {
                            Button("Open", systemImage: "arrow.right.circle") {
                                navigationPath.append(index)
                            }
                            Divider()
                            Button("Export Certificate…", systemImage: "square.and.arrow.up") {
                                Task { await export(commonName: commonName, key: false) }
                            }
                            .disabled(commonName.isEmpty || isPerforming)
                            Button("Export Private Key…", systemImage: "key") {
                                pendingKeyExport = commonName
                            }
                            .disabled(commonName.isEmpty || isPerforming)
                            Divider()
                            Button("Renew with ACME", systemImage: "globe") {
                                Task { await perform(.renewACME(commonName: commonName)) }
                            }
                            .disabled(commonName.isEmpty || isPerforming || hosted.certificate?.enabled != true || hosted.certificate?.revokedAt != nil)
                            Button("Renew Local Certificate…", systemImage: "arrow.clockwise") {
                                selectedCertificateIndex = index
                                renewing = true
                            }
                            .disabled(commonName.isEmpty || isPerforming || hosted.certificate?.enabled != true || hosted.certificate?.revokedAt != nil)
                            Button("Remove Certificate…", systemImage: "trash", role: .destructive) {
                                pendingRemoval = commonName
                            }
                            .disabled(commonName.isEmpty || isPerforming)
                            Button("Revoke Certificate…", systemImage: "xmark.shield", role: .destructive) {
                                pendingRevocation = commonName
                            }
                            .disabled(commonName.isEmpty || isPerforming || hosted.certificate?.revokedAt != nil)
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
        .sheet(isPresented: $renewing) {
            if let index = selectedCertificateIndex,
               let snapshot = state.snapshot,
               snapshot.certificates.indices.contains(index),
               let certificate = snapshot.certificates[index].certificate {
                RenewCertificateSheet(commonName: certificate.commonName) { action in
                    await perform(action)
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

    /// Sends one certificate write. A refusal the server reports as
    /// `success: false` is a failure, not a quiet success.
    @discardableResult
    private func perform(_ action: CertificateManagementAction) async -> String? {
        isPerforming = true
        defer { isPerforming = false }
        do {
            let receipt = try await connectionModel.performCertificateAction(action, for: serverID)
            // Never retain uploaded private keys in the command-result view.
            if case .importPEM = action {
                outcome = nil
            } else {
                outcome = .succeeded(action, receipt)
            }
            // Details are addressed by inventory index, which a removal
            // shifts; return to the inventory rather than show a neighbour.
            if case .remove = action, CertificateActionOutcome.refusal(receipt) == nil {
                navigationPath.removeAll()
            }
            return CertificateActionOutcome.refusal(receipt)
        } catch {
            let failure = error as? ClavironClientFailure ?? ClavironClientFailure(
                kind: .unknown,
                diagnosticDetail: String(describing: error)
            )
            if case .importPEM = action { outcome = nil }
            else { outcome = .failed(action, failure) }
            return failure.localizedDescription
        }
    }

    /// The stored chain for the detail's decoded view: read-only, no outcome row.
    private func chainPEM(commonName: String) async -> String? {
        guard !commonName.isEmpty else { return nil }
        let receipt = try? await connectionModel.performCertificateAction(
            .exportPEM(commonName: commonName, includePrivateKey: false), for: serverID
        )
        guard case let .exported(chain, _)? = receipt, !chain.isEmpty else { return nil }
        return chain
    }

    private func export(commonName: String, key: Bool) async {
        guard !isPerforming else { return }
        isPerforming = true
        defer { isPerforming = false }
        do {
            let receipt = try await connectionModel.performCertificateAction(
                .exportPEM(commonName: commonName, includePrivateKey: key), for: serverID
            )
            guard case let .exported(chain, privateKey) = receipt else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let pem: String
            if key {
                guard let privateKey, !privateKey.isEmpty else {
                    throw CocoaError(.fileReadNoPermission)
                }
                pem = privateKey
            } else { pem = chain }
            guard !pem.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            #if os(macOS)
            // AppKit's own panel: a SwiftUI file exporter raised from a pushed
            // detail view has no reliable anchor on macOS.
            try await Self.savePEM(pem, filename: key ? "\(commonName).key" : "\(commonName).crt", privateKey: key)
            #else
            exportingKey = key
            exportDocument = CertificatePEMDocument(pem: pem, privateKey: key)
            exporting = true
            #endif
        } catch { transferError = error.localizedDescription }
    }

    #if os(macOS)
    /// Ask where to save the PEM and write it; a private key is written 0600.
    /// The panel is AppKit's and runs on the main thread, whatever executor
    /// the export's task is on.
    private static func savePEM(_ pem: String, filename: String, privateKey: Bool) async throws {
        let destination: URL? = await MainActor.run {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = filename
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.title = privateKey ? "Save Private Key" : "Save Certificate"
            panel.message = privateKey
                ? "Anyone with this key can use the certificate's identity."
                : "The certificate chain, PEM encoded."
            return panel.runModal() == .OK ? panel.url : nil
        }
        guard let url = destination else { return }
        try Data(pem.utf8).write(to: url, options: .atomic)
        if privateKey {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
    #endif

    static func status(_ hosted: HostedCertificateObservation) -> ManagementResourceStatus {
        guard let certificate = hosted.certificate else {
            return .unknown
        }
        return ManagementResourceStatus(
            title: certificate.enabled ? "Enabled" : "Disabled",
            color: certificate.enabled ? .green : .secondary
        )
    }

    @ViewBuilder
    private var unavailableContent: some View {
        switch state {
        case .disconnected:
            ContentUnavailableView {
                Label("Disconnected", systemImage: "network.slash")
            } description: {
                Text("Connect to Claviron to load the certificate inventory.")
            } actions: {
                Button("Connect") {
                    Task {
                        await connectionModel.loadCertificates(for: serverID)
                    }
                }
            }
        case .loading(previous: nil):
            ProgressView("Loading certificates…")
        case let .failed(failure):
            ContentUnavailableView {
                Label("Certificates Unavailable", systemImage: "xmark.circle")
            } description: {
                Text(failure.localizedDescription)
            } actions: {
                Button("Try Again") {
                    Task {
                        await connectionModel.loadCertificates(for: serverID)
                    }
                }
            }
        case .loading(previous: .some), .empty, .loaded, .stale:
            EmptyView()
        }
    }
}

// MARK: - Detail

/// One certificate. It presents its own removal confirmation, because it is
/// the visible surface while pushed.
private struct CertificateDetailView: View {
    let hosted: HostedCertificateObservation
    let outcome: CertificateActionOutcome?
    let isPerforming: Bool
    let perform: (CertificateManagementAction) async -> String?
    let export: (Bool) -> Void
    /// The stored chain, PEM, for the decoded view; nil when it cannot be read.
    let chain: () async -> String?

    @State private var pendingRemoval: String?
    @State private var pendingRevocation: String?
    @State private var renewing = false
    @State private var decoded: [DecodedCertificate]?
    @State private var permissions: CertificatePermissions?
    @State private var permissionsFailure: String?

    private var commonName: String { hosted.certificate?.commonName ?? "" }

    var body: some View {
        let status = CertificatesView.status(hosted)
        ManagementDetailLayout {
            ManagementResourceHeaderCard(
                kind: "Certificate",
                name: commonName.nonEmpty ?? "Unidentified certificate",
                systemImage: "checkmark.shield",
                warningBadge: hosted.certificate?.revokedAt != nil ? "Revoked" : nil,
                status: status.title,
                statusColor: status.color,
                actionsDisabled: isPerforming || commonName.isEmpty
            ) {
                Button("Export Certificate…", systemImage: "square.and.arrow.up") { export(false) }
                Button("Export Private Key…", systemImage: "key") { export(true) }
                Button("Renew with ACME", systemImage: "globe") {
                    Task { await perform(.renewACME(commonName: commonName)) }
                }
                .disabled(isPerforming || hosted.certificate?.revokedAt != nil)
                Button("Renew Local Certificate…", systemImage: "arrow.clockwise") {
                    renewing = true
                }
                .disabled(hosted.certificate?.enabled != true || hosted.certificate?.revokedAt != nil)
                Button("Remove Certificate…", systemImage: "trash", role: .destructive) {
                    pendingRemoval = commonName
                }
                Button("Revoke Certificate…", systemImage: "xmark.shield", role: .destructive) {
                    pendingRevocation = commonName
                }
                .disabled(hosted.certificate?.revokedAt != nil)
            }

            if let outcome {
                ManagementDetailCard("Command result", systemImage: "terminal", tint: .orange) {
                    CertificateOutcomeRow(outcome: outcome)
                }
            }

            ManagementDetailCard("Certificate details", systemImage: "info.circle", tint: .blue) {
                if let certificate = hosted.certificate {
                    LabeledContent(
                        "Common name",
                        value: certificate.commonName.isEmpty ? "Empty string" : certificate.commonName
                    )
                    LabeledContent("ID", value: certificate.id.formatted())
                    LabeledContent("Issuer", value: decoded?.first.map { $0.selfSigned ? "\($0.issuer) (self-signed)" : $0.issuer } ?? "Reading…")
                    LabeledContent("Enabled", value: certificate.enabled ? "Yes" : "No")
                    LabeledContent("Issued", value: certificate.issuedAt.reportedDate)
                    LabeledContent("Expires", value: certificate.expiresAt.reportedDate)
                    LabeledContent("Updated", value: certificate.updatedAt.reportedDate)
                    if let revokedAt = certificate.revokedAt {
                        LabeledContent("Revoked", value: revokedAt.reportedDate)
                    }
                } else {
                    Label("Certificate identity and state not reported", systemImage: "questionmark.diamond")
                        .foregroundStyle(.secondary)
                }
            }

            ManagementDetailCard("Certificate permissions", systemImage: "key", tint: .indigo) {
                if decoded == nil {
                    Text("Reading the stored certificate…").foregroundStyle(.secondary)
                } else if let permissionsFailure {
                    Text(permissionsFailure).foregroundStyle(.orange)
                } else if let permissions {
                    if permissions.names.isEmpty {
                        Text("Explicitly empty permission scope").foregroundStyle(.secondary)
                    } else {
                        ForEach(permissions.names, id: \.self) { name in
                            Text(name).font(.body.monospaced()).textSelection(.enabled)
                        }
                    }
                } else {
                    Text("No permission declaration").foregroundStyle(.secondary)
                }
            }

            ManagementDetailCard("Chain", systemImage: "link.badge.plus", tint: .green) {
                switch decoded {
                case nil:
                    Text("Reading the stored chain…").foregroundStyle(.secondary)
                case let .some(chain) where chain.isEmpty:
                    Text("The stored chain could not be read.").foregroundStyle(.secondary)
                case let .some(chain):
                    ForEach(Array(chain.enumerated()), id: \.offset) { index, link in
                        if index > 0 { Divider() }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.subject).font(.body.weight(.medium))
                            Text(link.selfSigned ? "Self-signed" : "Signed by \(link.issuer)")
                                .font(.callout).foregroundStyle(.secondary)
                            if let notAfter = link.notAfter {
                                Text("Expires \(notAfter.clavironFormatted)")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }

            ManagementDetailCard("Hostnames", systemImage: "link", tint: .teal) {
                let aliases = hosted.certificate?.aliases ?? []
                if aliases.isEmpty {
                    Text("No hostnames")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(aliases.enumerated()), id: \.offset) { index, alias in
                        if index > 0 {
                            Divider()
                        }
                        Text(alias.isEmpty ? "Empty hostname" : alias)
                            .font(.body.monospaced())
                    }
                }
            }

            ManagementDetailCard("Server attachments", systemImage: "server.rack", tint: .indigo) {
                if hosted.servers.isEmpty {
                    Text("No server attachments")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(hosted.servers.enumerated()), id: \.offset) { index, server in
                        if index > 0 {
                            Divider()
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text(server.name.isEmpty ? "Empty server name" : server.name)
                                .font(.body.weight(.medium))
                            Text("id \(server.id)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text(server.enabled ? "Enabled" : "Disabled")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .workspaceNavigationTitle(commonName.nonEmpty ?? "Certificate")
        .task(id: "\(commonName)#\(hosted.certificate?.updatedAt?.seconds ?? 0)") {
            decoded = nil
            permissions = nil
            permissionsFailure = nil
            let pem = await chain()
            guard !Task.isCancelled else { return }
            decoded = pem.map(CertificateChainDecoder.decode(pem:)) ?? []
            if let pem {
                do { permissions = try CertificatePermissions.read(pem: pem) }
                catch { permissionsFailure = error.localizedDescription }
            } else {
                permissionsFailure = "The stored certificate could not be read."
            }
        }
        .sheet(isPresented: $renewing) {
            RenewCertificateSheet(commonName: commonName, submit: perform)
        }
        .certificateRemovalConfirmation($pendingRemoval) { commonName in
            Task { await perform(.remove(commonName: commonName)) }
        }
        .certificateRevocationConfirmation($pendingRevocation) { commonName in
            Task { await perform(.revoke(commonName: commonName)) }
        }
    }
}

// MARK: - Outcome

private struct CertificateOutcomeRow: View {
    let outcome: CertificateActionOutcome

    var body: some View {
        let failed = outcome.isFailure
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(outcome.action.title)
                    .font(.headline)
                Text(outcome.summary)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(failed ? Color.red : Color.green)
        }
    }
}

nonisolated enum CertificateActionOutcome: Equatable, Sendable {
    case succeeded(CertificateManagementAction, CertificateManagementReceipt)
    case failed(CertificateManagementAction, ClavironClientFailure)

    var action: CertificateManagementAction {
        switch self {
        case let .succeeded(action, _), let .failed(action, _): action
        }
    }

    var isFailure: Bool {
        switch self {
        case .failed: true
        case let .succeeded(_, receipt): Self.refusal(receipt) != nil
        }
    }

    var summary: String {
        switch self {
        case let .failed(_, failure):
            failure.localizedDescription
        case let .succeeded(_, .added(id, attachedExisting: true)):
            "An existing certificate (ID \(id)) already covers these hostnames and was attached."
        case let .succeeded(_, .added(id, attachedExisting: false)):
            "Issued through ACME and stored as certificate \(id)."
        case let .succeeded(_, .operation(_, message?)):
            message
        case let .succeeded(_, .operation(success, nil)):
            success ? "Accepted." : "The server did not accept the change."
        case let .succeeded(_, .imported(commonName)):
            "Imported \(commonName)."
        case .succeeded(_, .exported):
            "Certificate material received for export."
        case let .succeeded(_, .renewed(expiresAt)):
            expiresAt.map { "Renewed through ACME; now expires \($0.clavironFormatted)." }
                ?? "Renewed through ACME."
        case let .succeeded(.renewLocal, .local(certificate)):
            "Renewed \(certificate.commonName) (certificate \(certificate.id)). Key, subject and extensions preserved."
        case let .succeeded(.revoke, .local(certificate)):
            "Revocation committed for \(certificate.commonName). Existing connections remain open."
        case let .succeeded(_, .local(certificate)):
            Self.summary(local: certificate)
        }
    }

    /// What the local CA issued, and that its material stayed on the server.
    static func summary(local certificate: LocalCertificateObservation) -> String {
        let what: String = switch certificate.kind {
        case .kind(.server): "a server certificate"
        case .kind(.client): "a client certificate"
        case .kind(.ca): certificate.issuerID == nil ? "the root CA" : "an intermediate CA"
        case .unspecified, .unrecognized: "a certificate"
        }
        let signer = certificate.issuerID.map { ", signed by certificate \($0)" } ?? ""
        let expiry = certificate.expiresAt?.date.map {
            "; valid until \($0.formatted(date: .abbreviated, time: .omitted))"
        } ?? ""
        return "Created \(what) for \(certificate.commonName) (certificate \(certificate.id))"
            + signer + expiry + ". Certificate and key stay on the server."
    }

    static func refusal(_ receipt: CertificateManagementReceipt) -> String? {
        if case let .operation(false, message) = receipt {
            return message ?? "The server did not accept the change."
        }
        return nil
    }
}

private extension View {
    func certificateRevocationConfirmation(
        _ pending: Binding<String?>,
        confirm: @escaping (String) -> Void
    ) -> some View {
        confirmationDialog(
            "Revoke \(pending.wrappedValue ?? "certificate")?",
            isPresented: Binding(get: { pending.wrappedValue != nil }, set: { if !$0 { pending.wrappedValue = nil } }),
            titleVisibility: .visible
        ) {
            Button("Revoke Certificate", role: .destructive) {
                if let name = pending.wrappedValue { confirm(name) }
                pending.wrappedValue = nil
            }
        } message: {
            Text("Revocation is permanent. TLS snapshots update after the database commit; existing connections remain open. Enabling the certificate will not restore access.")
        }
    }

    func certificateRemovalConfirmation(
        _ pending: Binding<String?>,
        confirm: @escaping (String) -> Void
    ) -> some View {
        confirmationDialog(
            "Remove \(pending.wrappedValue ?? "certificate")?",
            isPresented: Binding(
                get: { pending.wrappedValue != nil },
                set: { if !$0 { pending.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: pending.wrappedValue
        ) { commonName in
            Button("Remove Certificate", role: .destructive) {
                confirm(commonName)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The certificate is permanently deleted and stops being served.")
        }
    }
}

private extension Optional where Wrapped == ProtobufTimestampObservation {
    var reportedDate: String {
        guard let timestamp = self else {
            return "Not reported"
        }
        return timestamp.reportedDate
    }
}

private extension ProtobufTimestampObservation {
    var reportedDate: String {
        guard let date else {
            return "Invalid (\(seconds)s, \(nanoseconds)ns)"
        }
        return date.clavironFormatted
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
