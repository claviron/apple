import SwiftUI

/// Device-local presentation data, independent of a server's user identity.
nonisolated enum LocalProfile {
    static let displayNameKey = "profile.displayName"
    static let emailKey = "profile.email"

    static func initials(for name: String) -> String? {
        let words = name.split(whereSeparator: \.isWhitespace)
        guard let first = words.first?.first else { return nil }
        let last = words.count > 1 ? words.last?.first : nil
        return (String(first) + (last.map(String.init) ?? "")).uppercased()
    }
}

struct ProfileView: View {
    @AppStorage(LocalProfile.displayNameKey) private var displayName = ""
    @AppStorage(LocalProfile.emailKey) private var email = ""

    var body: some View {
        Form {
            Section {
                TextField("Display Name", text: $displayName)
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
            } header: {
                Text("Personal Information")
            } footer: {
                Text("Changes are saved on this device.")
            }
        }
        .formStyle(.grouped)
        .workspaceNavigationTitle("Profile")
    }
}
