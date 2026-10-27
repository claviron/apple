import SwiftUI

struct TLSProfileEditorView: View {
    @Bindable var applicationModel: ApplicationModel
    let existingProfile: TLSProfile?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var credentials = TLSCredentialImport()
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        applicationModel: ApplicationModel,
        existingProfile: TLSProfile? = nil
    ) {
        self.applicationModel = applicationModel
        self.existingProfile = existingProfile
        _name = State(initialValue: existingProfile?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $name)
                }

                if existingProfile == nil {
                    Section {
                        CredentialImportFields(
                            credentials: $credentials,
                            errorMessage: $errorMessage
                        )
                    } header: {
                        Text("Mutual TLS")
                    } footer: {
                        Text("Credential files are copied into protected application storage.")
                    }
                } else {
                    Section {
                        Label("Managed as an immutable TLS identity", systemImage: "lock.shield")
                    } header: {
                        Text("Credentials")
                    } footer: {
                        Text("To change certificate material, add a new TLS profile and move servers to it. Provisioning and rotation will belong to the SSL service.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(
                existingProfile == nil ? "Add TLS Profile" : "Rename TLS Profile"
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(isSaving)
                }
            }
        }
        .frame(idealWidth: 460, idealHeight: 420)
        .interactiveDismissDisabled(isSaving)
        .alert(
            "TLS Profile Not Saved",
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

    private func save() {
        isSaving = true
        Task {
            defer {
                isSaving = false
            }

            do {
                if let existingProfile {
                    try await applicationModel.updateTLSProfileName(
                        existingProfile.id,
                        name: name
                    )
                } else {
                    try await applicationModel.addTLSProfile(
                        name: name,
                        credentials: credentials
                    )
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
