import SwiftUI

/// The rail footer opens an identity card rather than a compact system menu.
struct ProfileMenu: View {
    @Binding var selection: AppDestination?
    var userManagementAvailable = false
    @AppStorage(LocalProfile.displayNameKey) private var displayName = ""
    @AppStorage(LocalProfile.emailKey) private var email = ""
    @State private var isPresented = false
    @State private var isHovered = false

    private var isSelected: Bool {
        let group = (selection ?? .overview).group
        return group == .settings
    }

    private var profileName: String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Profile" : name
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            ProfileAvatar(name: displayName, size: 30)
                .frame(width: 36, height: 36)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(background, in: .rect(cornerRadius: 8))
        .onHover { isHovered = $0 }
        .help("Profile and Settings")
        .accessibilityLabel("\(profileName), Profile and Settings")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("profile-menu")
        .popover(isPresented: $isPresented, arrowEdge: popoverEdge) {
            profilePanel
                .presentationCompactAdaptation(.popover)
        }
    }

    private var profilePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfilePanelEntry(identifier: "profile-menu.profile", action: { select(.profile) }) {
                HStack(spacing: 12) {
                    ProfileAvatar(name: displayName, size: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profileName)
                            .font(.headline)
                            .lineLimit(1)
                        if !email.isEmpty {
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else if profileName != "Profile" {
                            Text("Profile")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
            .disabled(!userManagementAvailable)
            Divider()
                .padding(.horizontal, 8)
            ProfilePanelEntry(identifier: "profile-menu.settings", action: { select(.settings) }) {
                Label("Settings", systemImage: "gearshape")
                    .font(.body)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(10)
        .frame(width: 270)
    }

    private var background: Color {
        if isSelected || isPresented { Color.primary.opacity(0.14) }
        else if isHovered { Color.primary.opacity(0.06) }
        else { .clear }
    }

    private var popoverEdge: Edge {
#if os(macOS)
        .trailing
#else
        .top
#endif
    }

    private func select(_ destination: AppDestination) {
        isPresented = false
        selection = destination
    }
}

private struct ProfileAvatar: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            if let initials = LocalProfile.initials(for: name) {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .medium))
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.48))
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(.tint, in: Circle())
        .accessibilityHidden(true)
    }
}

private struct ProfilePanelEntry<Content: View>: View {
    let identifier: String
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color.primary.opacity(0.06) : .clear, in: .rect(cornerRadius: 8))
        .onHover { isHovered = $0 }
        .accessibilityIdentifier(identifier)
    }
}
