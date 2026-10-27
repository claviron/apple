import SwiftUI

struct ConfigurationView: View {
    @Bindable var applicationModel: ApplicationModel
    @AppStorage(AppAppearance.storageKey) private var storedAppearance = AppAppearance.system.rawValue

    @State private var editor: ConfigurationEditor?
    @State private var isRunningWizard = false
    @State private var deletion: ConfigurationDeletion?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Appearance") {
                appearancePicker
            }

            Section("Servers") {
                ForEach(applicationModel.configuration.servers) { server in
                    serverRow(server)
                }

                Button {
                    editor = .addServer
                } label: {
                    Label("Add Server", systemImage: "plus.circle.fill")
                }
                .disabled(applicationModel.configuration.tlsProfiles.isEmpty)
            }

            Section("TLS Profiles") {
                ForEach(applicationModel.configuration.tlsProfiles) { profile in
                    tlsProfileRow(profile)
                }

                Button {
                    editor = .addTLSProfile
                } label: {
                    Label("Add TLS Profile", systemImage: "plus.circle.fill")
                }
            }

            Section {
                Button {
                    isRunningWizard = true
                } label: {
                    Label("Add with Wizard", systemImage: "wand.and.sparkles")
                }
            } footer: {
                Text("Walks through a server and the TLS profile it connects with, together.")
            }
        }
        .workspaceNavigationTitle("Settings")
        .sheet(item: $editor) { editor in
            editorView(editor)
        }
        .sheet(isPresented: $isRunningWizard) {
            InitialConfigurationView(applicationModel: applicationModel) {
                isRunningWizard = false
            }
        }
        .confirmationDialog(
            deletion?.title ?? "Remove Configuration",
            isPresented: Binding(
                get: { deletion != nil },
                set: { if !$0 { deletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                removePendingConfiguration()
            }
            Button("Cancel", role: .cancel) {
                deletion = nil
            }
        } message: {
            Text(deletion?.message ?? "")
        }
        .alert(
            "Configuration Not Changed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var appearancePicker: some View {
        HStack {
            Spacer(minLength: 0)

            HStack(spacing: 12) {
                appearanceOptions
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: 380, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var appearanceOptions: some View {
        ForEach(AppAppearance.allCases) { appearance in
            AppearanceOptionCard(
                appearance: appearance,
                isSelected: storedAppearance == appearance.rawValue
            ) {
                storedAppearance = appearance.rawValue
            }
        }
    }

    private func serverRow(_ server: ServerProfile) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(server.name)
                        .font(.headline)
                    if server.id == applicationModel.configuration.activeServerID {
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(server.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let tlsProfile = applicationModel.configuration.tlsProfiles.first(
                    where: { $0.id == server.tlsProfileID }
                ) {
                    Text("TLS: \(tlsProfile.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Menu {
                Button("Edit", systemImage: "pencil") {
                    editor = .editServer(server.id)
                }
                Button("Remove", systemImage: "trash", role: .destructive) {
                    deletion = .server(server.id, name: server.name)
                }
            } label: {
                Label("Server Actions", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuIndicator(.hidden)
            .help("Server actions")
#if os(macOS)
            .pointerStyle(.link)
#endif
        }
    }

    /// A profile a server still points at cannot be removed: the server
    /// would lose the credentials it connects with.
    private func isProfileInUse(_ profile: TLSProfile) -> Bool {
        applicationModel.configuration.servers.contains { $0.tlsProfileID == profile.id }
    }

    private func tlsProfileRow(_ profile: TLSProfile) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.headline)
                let useCount = applicationModel.configuration.servers.filter {
                    $0.tlsProfileID == profile.id
                }.count
                Text(useCount == 1 ? "Used by 1 server" : "Used by \(useCount) servers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button("Rename", systemImage: "pencil") {
                    editor = .editTLSProfile(profile.id)
                }
                Button("Remove", systemImage: "trash", role: .destructive) {
                    deletion = .tlsProfile(profile.id, name: profile.name)
                }
                .disabled(isProfileInUse(profile))

                if isProfileInUse(profile) {
                    Text("Remove the servers using this profile first")
                }
            } label: {
                Label("TLS Profile Actions", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuIndicator(.hidden)
            .help("TLS profile actions")
#if os(macOS)
            .pointerStyle(.link)
#endif
        }
    }

    @ViewBuilder
    private func editorView(_ editor: ConfigurationEditor) -> some View {
        switch editor {
        case .addServer:
            ServerEditorView(applicationModel: applicationModel)
        case let .editServer(serverID):
            if let server = applicationModel.configuration.servers.first(
                where: { $0.id == serverID }
            ) {
                ServerEditorView(
                    applicationModel: applicationModel,
                    existingServer: server
                )
            }
        case .addTLSProfile:
            TLSProfileEditorView(applicationModel: applicationModel)
        case let .editTLSProfile(profileID):
            if let profile = applicationModel.configuration.tlsProfiles.first(
                where: { $0.id == profileID }
            ) {
                TLSProfileEditorView(
                    applicationModel: applicationModel,
                    existingProfile: profile
                )
            }
        }
    }

    private func removePendingConfiguration() {
        guard let deletion else {
            return
        }
        self.deletion = nil

        Task {
            do {
                switch deletion {
                case let .server(serverID, _):
                    try await applicationModel.removeServer(serverID)
                case let .tlsProfile(profileID, _):
                    try await applicationModel.removeTLSProfile(profileID)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct AppearanceOptionCard: View {
    let appearance: AppAppearance
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            VStack(spacing: 9) {
                AppearancePreview(appearance: appearance)
                    .frame(height: 62)

                HStack(spacing: 5) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    Text(appearance.title)
                        .font(.callout.weight(.medium))
                }
            }
            .frame(width: 108)
            .padding(10)
            .contentShape(.rect(cornerRadius: 10))
            .background(background)
            .clipShape(.rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(border, lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
#if os(macOS)
        .pointerStyle(.link)
#endif
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .accessibilityLabel("\(appearance.title) appearance")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Hover walks toward the selected treatment rather than introducing a
    /// third look, so pointing at a card previews choosing it.
    private var background: Color {
        if isSelected {
            return Color.secondary.opacity(0.09)
        }
        return Color.secondary.opacity(isHovered ? 0.07 : 0.045)
    }

    private var border: Color {
        if isSelected {
            return Color.accentColor
        }
        return isHovered ? Color.accentColor.opacity(0.42) : Color.secondary.opacity(0.2)
    }
}

private struct AppearancePreview: View {
    let appearance: AppAppearance

    var body: some View {
        ZStack {
            previewBackground

            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.65))
                    .frame(height: 8)

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.38))
                        .frame(width: 24)
                    Rectangle()
                        .fill(Color.white.opacity(0.28))
                }
            }
            .padding(8)
        }
        .clipShape(.rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.black.opacity(0.18))
        }
    }

    @ViewBuilder
    private var previewBackground: some View {
        switch appearance {
        case .system:
            HStack(spacing: 0) {
                Color(white: 0.94)
                Color(white: 0.16)
            }
        case .light:
            Color(white: 0.94)
        case .dark:
            Color(white: 0.16)
        }
    }
}

private enum ConfigurationEditor: Identifiable {
    case addServer
    case editServer(ServerID)
    case addTLSProfile
    case editTLSProfile(TLSProfileID)

    var id: String {
        switch self {
        case .addServer:
            "add-server"
        case let .editServer(serverID):
            "edit-server-\(serverID.rawValue)"
        case .addTLSProfile:
            "add-tls-profile"
        case let .editTLSProfile(profileID):
            "edit-tls-profile-\(profileID.rawValue)"
        }
    }
}

private enum ConfigurationDeletion {
    case server(ServerID, name: String)
    case tlsProfile(TLSProfileID, name: String)

    var title: String {
        switch self {
        case .server:
            "Remove Server?"
        case .tlsProfile:
            "Remove TLS Profile?"
        }
    }

    var message: String {
        switch self {
        case let .server(_, name):
            "\(name) will be removed from this device."
        case let .tlsProfile(_, name):
            "\(name) and its copied credential files will be removed from this device."
        }
    }
}

#Preview {
    NavigationStack {
        ConfigurationView(
            applicationModel: .preview(configuration: .preview)
        )
    }
}
