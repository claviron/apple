import SwiftUI
import UniformTypeIdentifiers

struct CredentialImportFields: View {
    @Binding var credentials: TLSCredentialImport
    @Binding var errorMessage: String?

    @State private var importRole: TLSCredentialRole?
    @State private var isImporting = false

    var body: some View {
        ForEach(TLSCredentialRole.allCases, id: \.self) { role in
            LabeledContent(role.title) {
                Button(credentials[role]?.fileName ?? "Choose File…") {
                    importRole = role
                    isImporting = true
                }
                .lineLimit(1)
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.data]
        ) { result in
            importCredential(result)
        }
    }

    private func importCredential(_ result: Result<URL, any Error>) {
        guard let role = importRole else {
            return
        }

        do {
            credentials[role] = try ImportedCredential.read(from: result.get())
        } catch {
            errorMessage = error.localizedDescription
        }
        importRole = nil
    }
}
