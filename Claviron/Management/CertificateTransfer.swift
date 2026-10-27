import ClavironControlPlane
import SwiftUI
import UniformTypeIdentifiers

/// Every stored certificate carries its kind; a certificate without one
/// (an older row, or a build this client does not know) is listed under All.
nonisolated enum CertificateGroup: String, CaseIterable {
    case all = "All"
    case ca = "CA"
    case server = "Server"
    case client = "Client"

    func contains(_ certificate: CertificateObservation?) -> Bool {
        if self == .all { return true }
        switch certificate?.kind {
        case .kind(.ca): return self == .ca
        case .kind(.server): return self == .server
        case .kind(.client): return self == .client
        default: return false
        }
    }
}

/// In-memory export only; key material is never put in preferences or logs.
nonisolated struct CertificatePEMDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    var privateKey = false

    init(pem: String, privateKey: Bool = false) {
        data = Data(pem.utf8)
        self.privateKey = privateKey
    }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let wrapper = FileWrapper(regularFileWithContents: data)
        if privateKey { wrapper.fileAttributes[FileAttributeKey.posixPermissions.rawValue] = 0o600 }
        return wrapper
    }
}

struct ImportCertificateSheet: View {
    let submit: (CertificateManagementAction) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var chain: ImportedCredential?
    @State private var key: ImportedCredential?
    @State private var choosingKey = false
    @State private var choosingFile = false
    @State private var issuer = ""
    @State private var errorMessage: String?
    @State private var importing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("PEM files") {
                    Button("Certificate: \(chain?.fileName ?? "Choose File…")") {
                        choosingKey = false
                        choosingFile = true
                    }
                    Button("Private key: \(key?.fileName ?? "Choose File…")") {
                        choosingKey = true
                        choosingFile = true
                    }
                    TextField("Issuer (optional; detected when empty)", text: $issuer)
                    Text("The server validates the pair and derives CA, server or client usage. Existing certificates are never overwritten. Root import does not change active trust.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                if importing { ProgressView("Importing…") }
            }
            .navigationTitle("Import Certificate")
            .disabled(importing)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(importing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { Task { await send() } }
                        .disabled(chain == nil || key == nil || importing)
                }
            }
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.data, .item]) { result in
                do {
                    let file = try ImportedCredential.read(from: result.get())
                    guard String(data: file.data, encoding: .utf8) != nil else {
                        throw CocoaError(.fileReadInapplicableStringEncoding)
                    }
                    if choosingKey { key = file } else { chain = file }
                    errorMessage = nil
                } catch { errorMessage = error.localizedDescription }
            }
        }
        .interactiveDismissDisabled(importing)
        .onDisappear { chain = nil; key = nil }
    }

    private func send() async {
        guard let chain, let key,
              let chainPEM = String(data: chain.data, encoding: .utf8),
              let keyPEM = String(data: key.data, encoding: .utf8) else { return }
        importing = true
        defer { importing = false }
        let name = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = await submit(.importPEM(chain: chainPEM, privateKey: keyPEM,
                                              issuer: name.isEmpty ? nil : name))
        if errorMessage == nil { dismiss() }
    }
}
