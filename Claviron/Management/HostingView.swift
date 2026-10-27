import ClavironControlPlane
import SwiftUI

/// Sites and aliases reported by the server's runtime resolver.
struct HostingView: View {
    let serverID: ServerID
    @Bindable var connectionModel: ConnectionModel
    @State private var selectedVhostIndex: Int?
    @NavigationDetailPath(.hosting) private var navigationPath: [Int] = []
    @State private var outcome: HostingActionOutcome?
    @State private var isPerforming = false

    private var state: HostingObservationState {
        connectionModel.hostingObservationState(for: serverID)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if let snapshot = state.snapshot {
                    hostingList(snapshot)
                } else {
                    unavailableContent
                }
            }
            .workspaceNavigationTitle("Sites")
            .managementDestination(for: Int.self) { index in
                if let snapshot = state.snapshot,
                   snapshot.vhosts.indices.contains(index) {
                    HostingSiteDetailView(
                        hosted: snapshot.vhosts[index],
                        siteNames: snapshot.vhosts.compactMap { $0.vhost?.name.nonEmpty },
                        outcome: outcome,
                        isPerforming: isPerforming,
                        perform: { action in await perform(action) }
                    )
                    .pageRefreshable(every: .seconds(2)) {
                        await connectionModel.loadHosting(for: serverID)
                    }
                } else {
                    ContentUnavailableView("Site Unavailable", systemImage: "questionmark.diamond")
                }
            }
        }
        .pageRefreshable(every: .seconds(2)) {
            await connectionModel.loadHosting(for: serverID)
        }
    }

    private func hostingList(_ snapshot: HostingInventorySnapshot) -> some View {
        List {
            if let outcome {
                Section {
                    HostingOutcomeRow(outcome: outcome)
                }
            }
            if snapshot.vhosts.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Persisted Sites",
                        systemImage: "network",
                        description: Text("The complete hosting inventory contains no vhosts.")
                    )
                }
            } else {
                Section {
                    ForEach(Array(snapshot.vhosts.enumerated()), id: \.offset) { index, hosted in
                        let status = Self.status(hosted)
                        ManagementResourceRow(
                            name: hosted.vhost?.name.nonEmpty ?? "Unidentified site",
                            systemImage: "network",
                            detail: Self.aliasCount(hosted.aliases.count),
                            status: status.title,
                            statusColor: status.color,
                            isSelected: selectedVhostIndex == index,
                            select: { selectedVhostIndex = index },
                            open: { navigationPath.append(index) }
                        )
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

    /// Sends one alias write. A refusal the server reports as
    /// `success: false` is a failure, not a quiet success.
    @discardableResult
    private func perform(_ action: HostingManagementAction) async -> String? {
        isPerforming = true
        defer { isPerforming = false }
        do {
            let receipt = try await connectionModel.performHostingAction(action, for: serverID)
            outcome = .succeeded(action, receipt)
            return HostingActionOutcome.refusal(receipt)
        } catch {
            let failure = error as? ClavironClientFailure ?? ClavironClientFailure(
                kind: .unknown,
                diagnosticDetail: String(describing: error)
            )
            outcome = .failed(action, failure)
            return failure.localizedDescription
        }
    }

    static func status(_ hosted: HostedVhostObservation) -> ManagementResourceStatus {
        guard let vhost = hosted.vhost else {
            return .unknown
        }
        return ManagementResourceStatus(
            title: vhost.enabled ? "Enabled" : "Disabled",
            color: vhost.enabled ? .green : .secondary
        )
    }

    private static func aliasCount(_ count: Int) -> String? {
        switch count {
        case 0: nil
        case 1: "1 alias"
        default: "\(count) aliases"
        }
    }

    @ViewBuilder
    private var unavailableContent: some View {
        switch state {
        case .disconnected:
            ContentUnavailableView {
                Label("Disconnected", systemImage: "network.slash")
            } description: {
                Text("Connect to Claviron to load the sites inventory.")
            } actions: {
                Button("Connect") {
                    Task {
                        await connectionModel.loadHosting(for: serverID)
                    }
                }
            }
        case .loading(previous: nil):
            ProgressView("Loading sites…")
        case let .failed(failure):
            ContentUnavailableView {
                Label("Sites Unavailable", systemImage: "xmark.circle")
            } description: {
                Text(failure.localizedDescription)
            } actions: {
                Button("Try Again") {
                    Task {
                        await connectionModel.loadHosting(for: serverID)
                    }
                }
            }
        case .loading(previous: .some), .empty, .loaded, .stale:
            EmptyView()
        }
    }
}

// MARK: - Site detail

/// One site. It presents its own alias sheet and removal confirmation,
/// because it is the visible surface while pushed.
private struct HostingSiteDetailView: View {
    let hosted: HostedVhostObservation
    let siteNames: [String]
    let outcome: HostingActionOutcome?
    let isPerforming: Bool
    let perform: (HostingManagementAction) async -> String?

    @State private var editor: HostingAliasEditor?
    @State private var pendingRemoval: String?

    private var siteName: String { hosted.vhost?.name ?? "" }

    var body: some View {
        let status = HostingView.status(hosted)
        ManagementDetailLayout {
            ManagementResourceHeaderCard(
                kind: "Site",
                name: siteName.nonEmpty ?? "Unidentified site",
                systemImage: "network",
                status: status.title,
                statusColor: status.color,
                actionsDisabled: isPerforming || siteName.isEmpty
            ) {
                Button("Add Alias…", systemImage: "plus") {
                    editor = .add(siteName: siteName)
                }
            }

            if let outcome {
                ManagementDetailCard("Command result", systemImage: "terminal", tint: .orange) {
                    HostingOutcomeRow(outcome: outcome)
                }
            }

            ManagementDetailCard("Site details", systemImage: "info.circle", tint: .blue) {
                if let vhost = hosted.vhost {
                    LabeledContent("Name", value: vhost.name.isEmpty ? "Empty string" : vhost.name)
                    if vhost.id != 0 {
                        LabeledContent("ID", value: vhost.id.formatted())
                    }
                    if vhost.readOnly {
                        Label("Read-only definition", systemImage: "lock")
                        if let reason = vhost.readOnlyReason {
                            Text(reason).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Enabled", value: vhost.enabled ? "Yes" : "No")
                } else {
                    Label("Site identity not reported", systemImage: "questionmark.diamond")
                        .foregroundStyle(.secondary)
                }
            }

            ManagementDetailCard("Aliases", systemImage: "link", tint: .teal) {
                HStack {
                    Text(hosted.aliases.count == 1 ? "1 alias" : "\(hosted.aliases.count) aliases")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        editor = .add(siteName: siteName)
                    } label: {
                        Label("Add Alias", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isPerforming || siteName.isEmpty)
                }

                ForEach(Array(hosted.aliases.enumerated()), id: \.offset) { index, alias in
                    if index > 0 {
                        Divider()
                    }
                    HostingAliasRow(
                        alias: alias,
                        canMove: siteNames.contains { $0 != siteName },
                        isPerforming: isPerforming,
                        move: { editor = .move(hostname: alias.hostname, from: siteName) },
                        remove: { pendingRemoval = alias.hostname }
                    )
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
        .workspaceNavigationTitle(siteName.nonEmpty ?? "Site")
        .sheet(item: $editor) { editor in
            HostingAliasEditorSheet(editor: editor, siteNames: siteNames) { action in
                await perform(action)
            }
        }
        .confirmationDialog(
            "Remove \(pendingRemoval ?? "alias")?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { hostname in
            Button("Remove Alias", role: .destructive) {
                Task { await perform(.removeAlias(hostname: hostname)) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The alias stops routing to \(siteName.nonEmpty ?? "this site").")
        }
    }
}

/// An alias as selectable text; its commands live in the trailing ⋯ menu.
private struct HostingAliasRow: View {
    let alias: VhostAliasObservation
    let canMove: Bool
    let isPerforming: Bool
    let move: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(alias.hostname.isEmpty ? "Empty hostname" : alias.hostname)
                .font(.body.monospaced())
            if alias.id != 0 {
                Text("id \(alias.id)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if let enabled = alias.enabled {
                Text(enabled ? "Enabled" : "Disabled")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if alias.readOnly {
                Label("Read-only", systemImage: "lock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help(alias.readOnlyReason ?? "Read-only alias")
                    .accessibilityHint(alias.readOnlyReason ?? "Read-only alias")
            } else {
                Menu {
                    Button("Move to Site…", systemImage: "arrow.right.square", action: move)
                        .disabled(!canMove)
                    Divider()
                    Button("Remove Alias…", systemImage: "trash", role: .destructive, action: remove)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(isPerforming || alias.hostname.isEmpty)
                .accessibilityLabel("Alias actions")
                .help("Alias actions")
            }
        }
        .padding(.vertical, 2)
        .textSelection(.enabled)
    }
}

private struct HostingOutcomeRow: View {
    let outcome: HostingActionOutcome

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

// MARK: - Editor

nonisolated enum HostingAliasEditor: Identifiable, Sendable {
    case add(siteName: String)
    case move(hostname: String, from: String)

    var id: String {
        switch self {
        case let .add(siteName): "alias.add.\(siteName)"
        case let .move(hostname, _): "alias.move.\(hostname)"
        }
    }
}

/// Editable text for an alias write.
nonisolated struct HostingAliasDraft: Equatable, Sendable {
    var hostname = ""
    var targetSite = ""

    func action(for editor: HostingAliasEditor) -> HostingManagementAction? {
        switch editor {
        case let .add(siteName):
            let hostname = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hostname.isEmpty, !siteName.isEmpty else { return nil }
            return .addAlias(vhostName: siteName, hostname: hostname)
        case let .move(hostname, from):
            guard !targetSite.isEmpty, targetSite != from else { return nil }
            return .replaceAlias(hostname: hostname, vhostName: targetSite)
        }
    }
}

private struct HostingAliasEditorSheet: View {
    let editor: HostingAliasEditor
    let siteNames: [String]
    let submit: (HostingManagementAction) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var draft = HostingAliasDraft()
    @State private var failure: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                switch editor {
                case let .add(siteName):
                    Section {
                        LabeledContent("Site", value: siteName)
                        TextField("Hostname", text: $draft.hostname, prompt: Text(verbatim: "www.example.com"))
#if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
#endif
                            .autocorrectionDisabled()
                    } header: {
                        Text("Alias")
                    }
                case let .move(hostname, from):
                    Section {
                        LabeledContent("Alias", value: hostname)
                        LabeledContent("Current site", value: from)
                        Picker("Move to", selection: $draft.targetSite) {
                            Text("Choose a site").tag("")
                            ForEach(siteNames.filter { $0 != from }, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    } header: {
                        Text("Move")
                    }
                }

                if let failure {
                    Section {
                        Label(failure, systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
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
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button(confirmTitle) {
                            if let action = draft.action(for: editor) {
                                Task { await send(action) }
                            }
                        }
                        .disabled(draft.action(for: editor) == nil)
                    }
                }
            }
            .interactiveDismissDisabled(isSubmitting)
        }
#if os(macOS)
        .frame(minWidth: 420, minHeight: 240)
#endif
    }

    private var title: String {
        switch editor {
        case .add: "New Alias"
        case .move: "Move Alias"
        }
    }

    private var confirmTitle: String {
        switch editor {
        case .add: "Add"
        case .move: "Move"
        }
    }

    private func send(_ action: HostingManagementAction) async {
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

// MARK: - State

nonisolated enum HostingActionOutcome: Equatable, Sendable {
    case succeeded(HostingManagementAction, HostingManagementReceipt)
    case failed(HostingManagementAction, ClavironClientFailure)

    var action: HostingManagementAction {
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
        case let .succeeded(_, .alias(alias, vhostName)):
            "Added \(alias.hostname) to \(vhostName)."
        case let .succeeded(_, .operation(_, message?)):
            message
        case let .succeeded(_, .operation(success, nil)):
            success ? "Accepted." : "The server did not accept the change."
        }
    }

    /// The sentence to show when the server answered but refused.
    static func refusal(_ receipt: HostingManagementReceipt) -> String? {
        if case let .operation(false, message) = receipt {
            return message ?? "The server did not accept the change."
        }
        return nil
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
