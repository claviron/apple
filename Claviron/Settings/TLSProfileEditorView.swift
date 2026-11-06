import SwiftUI

struct TLSProfileEditorView: View {
    @Bindable var applicationModel: ApplicationModel
    let existingProfile: TLSProfile

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        applicationModel: ApplicationModel,
        existingProfile: TLSProfile
    ) {
        self.applicationModel = applicationModel
        self.existingProfile = existingProfile
        _name = State(initialValue: existingProfile.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $name)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Rename TLS Profile")
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
                try await applicationModel.updateTLSProfileName(
                    existingProfile.id,
                    name: name
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
