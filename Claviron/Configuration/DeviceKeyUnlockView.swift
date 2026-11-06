import SwiftUI

struct DeviceKeyUnlockView: View {
    let applicationModel: ApplicationModel
    @State private var password = ""
    @State private var isUnlocking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            SetupField(
                "Private key password", text: $password, prompt: "Password",
                isSecure: true, contentType: .password, showsTitle: false, alignment: .center
            )
            Button("Unlock", action: unlock)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty || isUnlocking)
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 340)
        .padding(32)
        .disabled(isUnlocking)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .navigationTitle("Claviron")
    }

    private func unlock() {
        guard !password.isEmpty, !isUnlocking else { return }
        isUnlocking = true
        errorMessage = nil
        Task {
            defer {
                password = ""
                isUnlocking = false
            }
            do {
                try await applicationModel.unlockDeviceKey(password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
