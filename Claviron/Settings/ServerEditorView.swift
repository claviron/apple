import SwiftUI

struct ServerEditorView: View {
    @Bindable var applicationModel: ApplicationModel
    let existingServer: ServerProfile?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var address: String
    @State private var tlsProfileID: TLSProfileID?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        applicationModel: ApplicationModel,
        existingServer: ServerProfile? = nil
    ) {
        self.applicationModel = applicationModel
        self.existingServer = existingServer
        _name = State(initialValue: existingServer?.name ?? "")
        _address = State(initialValue: existingServer?.address ?? "")
        _tlsProfileID = State(
            initialValue: existingServer?.tlsProfileID
                ?? applicationModel.activeServer?.tlsProfileID
                ?? applicationModel.configuration.tlsProfiles.first?.id
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("HTTPS address", text: $address)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                Picker("TLS Profile", selection: $tlsProfileID) {
                    ForEach(applicationModel.configuration.tlsProfiles) { profile in
                        Text(profile.name)
                            .tag(Optional(profile.id))
                    }
                }

                if let tlsProfileID,
                   let profile = applicationModel.configuration.tlsProfiles.first(
                       where: { $0.id == tlsProfileID }
                   ) {
                    Text("Reuses the \(profile.name) client certificate and private key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existingServer == nil ? "Add Server" : "Edit Server")
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
                    .disabled(isSaving || tlsProfileID == nil)
                }
            }
        }
        .frame(idealWidth: 420, idealHeight: 300)
        .interactiveDismissDisabled(isSaving)
        .alert(
            "Server Not Saved",
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
        guard let tlsProfileID else {
            return
        }
        isSaving = true

        Task {
            defer {
                isSaving = false
            }

            do {
                if let existingServer {
                    try await applicationModel.updateServer(
                        existingServer.id,
                        name: name,
                        address: address,
                        tlsProfileID: tlsProfileID
                    )
                } else {
                    try await applicationModel.addServer(
                        name: name,
                        address: address,
                        tlsProfileID: tlsProfileID
                    )
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
