import SwiftUI

struct DeviceKeyView: View {
    let applicationModel: ApplicationModel
    var allowsCreation = false
    var onLock: (() async -> Void)?

    @State private var protectWithPassword = true
    @State private var password = ""
    @State private var confirmation = ""
    @State private var confirmUnencrypted = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch applicationModel.deviceKeyStatus {
            case .none:
                if errorMessage == nil {
                    ProgressView("Checking for a device key")
                } else {
                    Label("Device key unavailable", systemImage: "exclamationmark.triangle")
                }
            case .missing:
                if allowsCreation {
                    creationControls
                } else {
                    Label("Create a device key in the registration wizard.", systemImage: "key")
                }
            case .unencrypted:
                Label("Device key ready (unencrypted)", systemImage: "key")
            case .locked:
                SetupField("Private key password", text: $password, isSecure: true)
                Button("Unlock Device Key", systemImage: "lock.open") {
                    perform { try await applicationModel.unlockDeviceKey(password: password) }
                }
                .disabled(password.isEmpty)
            case .unlocked:
                Label("Device key unlocked", systemImage: "lock.open")
                if let onLock {
                    Button("Lock Device Key", systemImage: "lock") {
                        perform {
                            applicationModel.lockDeviceKey()
                            await onLock()
                        }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .disabled(isWorking)
        .task {
            do {
                try await applicationModel.refreshDeviceKeyStatus()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Create a private key without a password?",
            isPresented: $confirmUnencrypted,
            titleVisibility: .visible
        ) {
            Button("Create Without Password") {
                perform { try await applicationModel.createDeviceKey(password: nil) }
            }
        } message: {
            Text("Claviron will store the key in its private application storage.")
        }
    }

    private var creationControls: some View {
        Group {
            Label("A device key is required for registration.", systemImage: "key")
            Toggle("Protect with a password", isOn: $protectWithPassword)
            if protectWithPassword {
                SetupField("Private key password", text: $password, isSecure: true)
                SetupField("Confirm private key password", text: $confirmation, isSecure: true)
            }
            Button("Generate Device Key", systemImage: "key") {
                if protectWithPassword {
                    perform { try await applicationModel.createDeviceKey(password: password) }
                } else {
                    confirmUnencrypted = true
                }
            }
            .disabled(protectWithPassword && (password.isEmpty || password != confirmation))
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        Task {
            defer {
                password = ""
                confirmation = ""
                isWorking = false
            }
            do {
                try await operation()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
