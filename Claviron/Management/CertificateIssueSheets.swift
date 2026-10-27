import ClavironControlPlane
import SwiftUI

/// The ways a certificate can be brought into the inventory from the
/// Certificates screen.
nonisolated enum CertificateIssuer: String, Identifiable, Sendable {
    case acme
    case localCA
    case rootCA

    var id: String { rawValue }
}

// MARK: - ACME

/// The hostnames a new ACME certificate covers: one common name and any
/// number of further names, each on its own row.
struct AddCertificateSheet: View {
    let submit: (CertificateManagementAction) async -> String?

    @State private var draft = CertificateDraft()

    var body: some View {
        IssueSheet(
            title: "New Certificate",
            confirmTitle: "Issue",
            systemImage: "checkmark.shield.fill",
            tint: .green,
            headline: "Certificate through ACME",
            message: "Every hostname must point at this server so its challenge can be answered.",
            progress: "Issuing through ACME. This waits for the order and its challenges.",
            action: draft.action,
            submit: submit
        ) {
            CertificateNameRows(
                draft: $draft,
                header: "Hostnames",
                commonNamePrompt: "example.com",
                alternatePrompt: "www.example.com",
                showsAlternates: true
            )
        }
        .onChange(of: draft) {
            draft.expandSeparatedNames()
        }
    }
}

// MARK: - Local CA

/// A certificate signed by this server's own authority. The certificate and
/// its key are generated and kept on the server.
struct LocalCertificateSheet: View {
    let submit: (CertificateManagementAction) async -> String?
    /// The local CAs the server holds, by common name: what "Signed by"
    /// offers. Empty, the configured authority is the only choice.
    var authorities: [String] = []
    var context: CertificateIssuanceContext? = nil

    @State private var draft = LocalCertificateDraft()
    @State private var choosingUser = false
    @State private var permissionCatalog: CertificatePermissions?
    @State private var permissionFailure: String?
    @State private var permissionSearch = ""
    @State private var loadingPermissions = false
    @State private var permissionSessionID: UUID?
    @State private var permissionLoadID = UUID()

    private var action: CertificateManagementAction? {
        if draft.kind == .client && draft.clientIdentity == .user && context?.isCurrent != true { return nil }
        if draft.kind == .client && draft.includesPermissions {
            guard context?.isCurrent == true, permissionSessionID == context?.sessionID, let permissionCatalog,
                  draft.selectedPermissions.isSubset(of: Set(permissionCatalog.names)) else { return nil }
        }
        return draft.action
    }

    var body: some View {
        IssueSheet(
            title: "Local Certificate",
            confirmTitle: "Create",
            systemImage: draft.kind.systemImage,
            tint: .indigo,
            headline: "Certificate from the local CA",
            message: "Signed by this server's own authority, for internal hosts and mutual TLS clients. Browsers do not trust it unless its root is installed.",
            progress: "Creating the certificate on the server.",
            action: action,
            submit: submit
        ) {
            Section {
                Picker("Kind", selection: $draft.kind) {
                    ForEach(LocalCertificateKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Kind")
            } footer: {
                Text(draft.kind.explanation)
                    .foregroundStyle(.secondary)
            }

            if draft.kind == .client {
                Section("Client Identity") {
                    if context?.supportsUsers == true {
                        Picker("Identity", selection: $draft.clientIdentity) {
                            Text("Common name").tag(ClientIdentityMode.commonName)
                            Text("User").tag(ClientIdentityMode.user)
                        }
                        .pickerStyle(.segmented)
                    }
                    if draft.clientIdentity == .user {
                        Button(draft.user?.title ?? "Select user…") { choosingUser = true }
                        if let user = draft.user, let subject = ClientCertificateIdentity.userSubject(user.key) {
                            LabeledContent("Identifier", value: subject).textSelection(.enabled)
                        }
                        if context?.isCurrent != true {
                            Text("The connection changed. Reopen certificate creation.").foregroundStyle(.red)
                        }
                    } else {
                        TextField("Identifier", text: $draft.identifier, prompt: Text("Optional UUID or URI"))
                            .autocorrectionDisabled()
                    }
                }
                Section {
                    Toggle("Declare certificate permissions", isOn: $draft.includesPermissions)
                        .disabled(permissionCatalog == nil || context?.isCurrent != true || permissionSessionID != context?.sessionID || loadingPermissions)
                    if loadingPermissions {
                        ProgressView("Loading permissions…")
                    }
                    if let permissionFailure {
                        Text(permissionFailure).foregroundStyle(.orange)
                        Button("Reload Permissions") { Task { await loadPermissions() } }
                            .disabled(loadingPermissions || context?.isCurrent != true)
                    }
                    if draft.includesPermissions {
                        TextField("Filter permissions", text: $permissionSearch)
                            .autocorrectionDisabled()
                        if let permissionCatalog {
                            let names = permissionCatalog.names.filter {
                                permissionSearch.isEmpty || $0.localizedCaseInsensitiveContains(permissionSearch)
                            }
                            if names.isEmpty {
                                Text(permissionCatalog.names.isEmpty ? "No permissions registered" : "No matching permissions")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(names, id: \.self) { name in
                                Toggle(name, isOn: Binding(
                                    get: { draft.selectedPermissions.contains(name) },
                                    set: { selected in
                                        if selected { draft.selectedPermissions.insert(name) }
                                        else { draft.selectedPermissions.remove(name) }
                                    }
                                ))
                                .font(.body.monospaced())
                            }
                        }
                    }
                } header: {
                    Text("Certificate Permissions")
                } footer: {
                    Text("Select existing permissions. User and role assignments stay unchanged. An enabled, empty selection declares no permissions.")
                        .foregroundStyle(.secondary)
                }
            }

            CertificateNameRows(
                draft: $draft.names,
                header: draft.kind.nameHeader,
                commonNamePrompt: draft.kind.commonNamePrompt,
                alternatePrompt: "api.internal.example",
                showsAlternates: draft.kind == .server
            )

            ValidityRows(days: $draft.validityDays)

            if draft.kind == .ca {
                Section {
                    LabeledContent("Path length") {
                        TextField("Path length", text: $draft.caPathLength, prompt: Text(verbatim: "0"))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .font(.body.monospacedDigit())
                            .numberInput()
                    }
                } header: {
                    Text("Authority")
                } footer: {
                    Text("How many further CAs may sit below this one. 0 lets it sign only end-entity certificates.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Issuer", selection: $draft.issuer) {
                    Text("Configured authority").tag("")
                    ForEach(authorities, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            } header: {
                Text("Signed by")
            } footer: {
                Text("The configured authority, or one of the server's local CAs. Certificate and key stay on the server; nothing is downloaded here.")
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: draft.names) {
            // Client and CA names may contain spaces; only hostnames split.
            if draft.kind == .server {
                draft.names.expandSeparatedNames()
            }
        }
        .onAppear {
            if let user = context?.initialUser, draft.user == nil {
                draft.kind = .client
                draft.clientIdentity = .user
                selectUser(user)
            }
        }
        .task(id: draft.kind == .client ? context?.sessionID : nil) {
            if draft.kind == .client { await loadPermissions() }
        }
        .sheet(isPresented: $choosingUser) {
            if let context {
                UserCertificatePicker(context: context, selected: { user in
                    selectUser(user)
                    choosingUser = false
                }, cancel: { choosingUser = false })
            }
        }
    }

    private func selectUser(_ user: ManagedRecord) {
        draft.user = user
        draft.names.commonName = user.values["username"]?.string ?? user.key.reference
    }

    private func loadPermissions() async {
        let loadID = UUID()
        permissionLoadID = loadID
        permissionCatalog = nil
        permissionSessionID = nil
        permissionFailure = nil
        draft.includesPermissions = false
        draft.selectedPermissions = []
        guard let context else {
            permissionFailure = "Connect to the server to load certificate permissions."
            return
        }
        loadingPermissions = true
        defer { if permissionLoadID == loadID { loadingPermissions = false } }
        do {
            let catalog = try await context.loadPermissions()
            guard !Task.isCancelled, permissionLoadID == loadID else { return }
            permissionCatalog = catalog
            permissionSessionID = context.sessionID
        } catch {
            guard !Task.isCancelled, permissionLoadID == loadID else { return }
            permissionFailure = error.localizedDescription
        }
    }
}

/// The root every local certificate chains to.
struct RootCASheet: View {
    let submit: (CertificateManagementAction) async -> String?

    @State private var draft = RootCADraft()

    var body: some View {
        IssueSheet(
            title: "Root CA",
            confirmTitle: "Create",
            systemImage: "seal.fill",
            tint: .orange,
            headline: "Root of the local CA",
            message: "Create it once. Every local certificate chains to this root; replacing it later means reissuing them and redistributing the root.",
            progress: "Creating the root on the server.",
            action: draft.action,
            submit: submit
        ) {
            Section {
                TextField("Common name", text: $draft.commonName, prompt: Text(verbatim: "Example Internal Root"))
                TextField("Organization", text: $draft.organization, prompt: Text("Optional"))
                TextField("Country", text: $draft.country, prompt: Text(verbatim: "TR"))
                    .font(.body.monospaced())
                    .hostnameInput()
            } header: {
                Text("Subject")
            } footer: {
                Text("Country is an optional two-letter code.")
                    .foregroundStyle(.secondary)
            }

            ValidityRows(days: $draft.validityDays)
        }
        .onChange(of: draft.country) {
            let normalized = String(draft.country.uppercased().filter(\.isLetter).prefix(2))
            if normalized != draft.country { draft.country = normalized }
        }
    }
}

// MARK: - Shared form pieces

/// The frame every issue sheet shares: a header naming what is created,
/// its fields, progress while the server works, and the server's refusal.
struct RenewCertificateSheet: View {
    let commonName: String
    let submit: (CertificateManagementAction) async -> String?
    @State private var validityDays = ""

    private var action: CertificateManagementAction? {
        guard let days = UInt32(validityDays), days > 0 else { return nil }
        return .renewLocal(commonName: commonName, validityDays: days)
    }

    var body: some View {
        IssueSheet(
            title: "Renew Local Certificate",
            confirmTitle: "Renew",
            systemImage: "arrow.clockwise",
            tint: .indigo,
            headline: "\(commonName)",
            message: "Uses the original private key and issuer. Subject, organization and all extensions are preserved. ACME certificates must use ACME renewal.",
            progress: "Renewing the certificate on the server.",
            action: action,
            submit: submit
        ) {
            ValidityRows(days: $validityDays)
        }
    }
}

private struct IssueSheet<Fields: View>: View {
    let title: LocalizedStringKey
    let confirmTitle: LocalizedStringKey
    let systemImage: String
    let tint: Color
    let headline: LocalizedStringKey
    let message: LocalizedStringKey
    let progress: LocalizedStringKey
    let action: CertificateManagementAction?
    let submit: (CertificateManagementAction) async -> String?
    @ViewBuilder let fields: () -> Fields

    @Environment(\.dismiss) private var dismiss
    @State private var failure: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: systemImage)
                            .font(.title)
                            .foregroundStyle(tint)
                            .frame(width: 36)
                            .contentTransition(.symbolEffect(.replace))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(headline)
                                .font(.headline)
                            Text(message)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }

                fields()

                if isSubmitting {
                    Section {
                        Label {
                            Text(progress)
                        } icon: {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }

                if let failure {
                    Section {
                        Label(failure, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(isSubmitting)
            .navigationTitle(title)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) {
                        if let action {
                            Task { await send(action) }
                        }
                    }
                    .disabled(action == nil || isSubmitting)
                }
            }
            .interactiveDismissDisabled(isSubmitting)
        }
#if os(macOS)
        .frame(minWidth: 520, minHeight: 440)
#endif
    }

    private func send(_ action: CertificateManagementAction) async {
        isSubmitting = true
        failure = nil
        let result = await submit(action)
        isSubmitting = false
        if let result {
            failure = result
        } else {
            dismiss()
        }
    }
}

/// A common name and, where the certificate allows it, further names on
/// their own rows.
private struct CertificateNameRows: View {
    @Binding var draft: CertificateDraft
    let header: LocalizedStringKey
    let commonNamePrompt: String
    let alternatePrompt: String
    let showsAlternates: Bool

    var body: some View {
        Section {
            row(text: $draft.commonName, prompt: commonNamePrompt, badge: showsAlternates ? "Common name" : nil)
            if showsAlternates {
                ForEach(draft.alternates.indices, id: \.self) { index in
                    row(
                        text: $draft.alternates[index],
                        prompt: alternatePrompt,
                        remove: { draft.alternates.remove(at: index) }
                    )
                }
                Button {
                    draft.alternates.append("")
                } label: {
                    Label("Add Hostname", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text(header)
        } footer: {
            if showsAlternates {
                HStack(spacing: 6) {
                    Text(Self.coverage(draft.hostnames.count))
                    Text(verbatim: "·")
                    Text("Paste several names at once to split them into rows.")
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func row(
        text: Binding<String>,
        prompt: String,
        badge: LocalizedStringKey? = nil,
        remove: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            TextField("Hostname", text: text, prompt: Text(verbatim: prompt))
                .labelsHidden()
                .font(.body.monospaced())
                .hostnameInput()
            if let badge {
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15), in: .capsule)
                    .foregroundStyle(Color.accentColor)
                    .fixedSize()
            }
            if let remove {
                Button(action: remove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove hostname")
                .help("Remove hostname")
            }
        }
    }

    private static func coverage(_ count: Int) -> String {
        switch count {
        case 0: "No hostnames yet"
        case 1: "1 hostname"
        default: "\(count) hostnames"
        }
    }
}

/// A validity the operator must state; nothing is filled in for them.
private struct ValidityRows: View {
    @Binding var days: String

    var body: some View {
        Section {
            LabeledContent("Valid for") {
                HStack(spacing: 6) {
                    TextField("Days", text: $days, prompt: Text("Required"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .font(.body.monospacedDigit())
                        .numberInput()
                    Text("days")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Validity")
        } footer: {
            Group {
                if let expiry = ValidityPreview.expiry(days: days, from: .now) {
                    Text("Expires around \(expiry, format: .dateTime.year().month().day()).")
                } else {
                    Text("A whole number of days, at least 1.")
                }
            }
            .foregroundStyle(.secondary)
        }
    }
}

private extension LocalCertificateKind {
    var title: LocalizedStringKey {
        switch self {
        case .server: "Server"
        case .client: "Client"
        case .ca: "Intermediate CA"
        }
    }

    var systemImage: String {
        switch self {
        case .server: "server.rack"
        case .client: "person.badge.key.fill"
        case .ca: "seal"
        }
    }

    var explanation: LocalizedStringKey {
        switch self {
        case .server: "Identifies an internal host to the clients that trust the local root."
        case .client: "Identifies a client to services that require mutual TLS."
        case .ca: "A subordinate authority that can sign further certificates under the local root."
        }
    }

    var nameHeader: LocalizedStringKey {
        switch self {
        case .server: "Hostnames"
        case .client: "Identity"
        case .ca: "CA name"
        }
    }

    var commonNamePrompt: String {
        switch self {
        case .server: "service.internal.example"
        case .client: "worker-01"
        case .ca: "Example Issuing CA"
        }
    }
}

private extension View {
    func hostnameInput() -> some View {
#if os(iOS)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
#else
        self.autocorrectionDisabled()
#endif
    }

    func numberInput() -> some View {
#if os(iOS)
        self.keyboardType(.numberPad)
#else
        self
#endif
    }
}

// MARK: - Drafts

/// Editable hostnames for a certificate: the common name first, then the
/// further names in the order they were added.
nonisolated struct CertificateDraft: Equatable, Sendable {
    var commonName = ""
    var alternates: [String] = []

    /// Every hostname, common name first, without blanks or repeats.
    var hostnames: [String] {
        var seen = Set<String>()
        return ([commonName] + alternates)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// A field holding several names (typed or pasted with commas, spaces or
    /// new lines) becomes one row per name: the field keeps the first, the
    /// rest follow it as new rows. A single name is left exactly as typed.
    mutating func expandSeparatedNames() {
        let commonNameParts = Self.names(in: commonName)
        if commonNameParts.count > 1 {
            commonName = commonNameParts[0]
            alternates.insert(contentsOf: commonNameParts.dropFirst(), at: 0)
        }
        var index = 0
        while index < alternates.count {
            let parts = Self.names(in: alternates[index])
            if parts.count > 1 {
                alternates[index] = parts[0]
                alternates.insert(contentsOf: parts.dropFirst(), at: index + 1)
            }
            index += 1
        }
    }

    private static func names(in text: String) -> [String] {
        text.split { $0 == "," || $0 == ";" || $0.isWhitespace }.map(String.init)
    }

    /// No common name, no certificate: further names never stand in for it.
    var action: CertificateManagementAction? {
        guard !commonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return .add(hostnames: hostnames)
    }
}

/// A local CA certificate as the operator is filling it in.
nonisolated struct LocalCertificateDraft: Equatable, Sendable {
    var kind: LocalCertificateKind = .server
    var names = CertificateDraft()
    var validityDays = ""
    var caPathLength = ""
    var issuer = ""
    var clientIdentity = ClientIdentityMode.commonName
    var user: ManagedRecord?
    var identifier = ""
    var includesPermissions = false
    var selectedPermissions: Set<String> = []

    private var permissions: CertificatePermissions? {
        guard kind == .client, includesPermissions else { return nil }
        return try? CertificatePermissions(names: Array(selectedPermissions))
    }

    /// Nil until every required field holds a usable value: a common name,
    /// a validity of at least one day, and a path length for a CA. Further
    /// names belong to server certificates only.
    var request: LocalCertificateRequest? {
        let hostnames = names.hostnames
        guard let commonName = hostnames.first,
              !names.commonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let days = ValidityPreview.days(validityDays),
              !(kind == .client && includesPermissions && permissions == nil)
        else { return nil }

        var pathLength: UInt32?
        if kind == .ca {
            guard let parsed = UInt32(caPathLength.trimmingCharacters(in: .whitespaces)) else {
                return nil
            }
            pathLength = parsed
        }

        let trimmedIssuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        var subject: String?
        if kind == .client {
            if clientIdentity == .user {
                guard let user, let selected = ClientCertificateIdentity.userSubject(user.key) else { return nil }
                subject = selected
            } else if !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let parsed = ClientCertificateIdentity.subject(identifier) else { return nil }
                subject = parsed
            }
        }
        return LocalCertificateRequest(
            commonName: commonName,
            aliases: kind == .server ? Array(hostnames.dropFirst()) : [],
            validityDays: days,
            kind: kind,
            caPathLength: pathLength,
            issuer: trimmedIssuer.isEmpty ? nil : trimmedIssuer,
            subjectURI: subject,
            permissions: permissions
        )
    }

    var action: CertificateManagementAction? {
        request.map { .createLocal($0) }
    }
}

nonisolated enum ClientIdentityMode: Hashable, Sendable { case commonName, user }

/// The local root as the operator is filling it in.
nonisolated struct RootCADraft: Equatable, Sendable {
    var commonName = ""
    var validityDays = ""
    var organization = ""
    var country = ""

    var request: LocalRootCARequest? {
        let name = commonName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let days = ValidityPreview.days(validityDays) else { return nil }
        let organization = organization.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = country.trimmingCharacters(in: .whitespacesAndNewlines)
        guard country.isEmpty || country.count == 2 else { return nil }
        return LocalRootCARequest(
            commonName: name,
            validityDays: days,
            organization: organization.isEmpty ? nil : organization,
            country: country.isEmpty ? nil : country.uppercased()
        )
    }

    var action: CertificateManagementAction? {
        request.map { .createRootCA($0) }
    }
}

/// Reads the validity field the operator typed; there is no default.
nonisolated enum ValidityPreview {
    static func days(_ text: String) -> UInt32? {
        guard let days = UInt32(text.trimmingCharacters(in: .whitespaces)), days > 0 else {
            return nil
        }
        return days
    }

    static func expiry(days text: String, from start: Date, calendar: Calendar = .current) -> Date? {
        guard let days = days(text) else { return nil }
        return calendar.date(byAdding: .day, value: Int(days), to: start)
    }
}
