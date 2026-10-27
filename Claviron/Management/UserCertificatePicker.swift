import ClavironControlPlane
import SwiftUI

struct CertificateIssuanceContext {
    let serverID: ServerID
    let connection: ConnectionModel
    let sessionID: UUID
    var initialUser: ManagedRecord? = nil
    var isCurrent: Bool { connection.managementSessionID(for: serverID) == sessionID }
    var supportsUsers: Bool { connection.serverInfo(for: serverID)?.capabilities.contains("users") == true }

    func loadPermissions() async throws -> CertificatePermissions {
        guard isCurrent else { throw ManagementClientError("The connection changed. Reopen certificate creation.") }
        guard connection.serverInfo(for: serverID)?.capabilities.contains("authorization") == true else {
            throw ManagementClientError("This server does not provide permission management.")
        }
        let session = try connection.managementSession(for: serverID)
        let permissions = try await session.client.loadCertificatePermissions()
        guard isCurrent else { throw ManagementClientError("The connection changed. Reopen certificate creation.") }
        return permissions
    }
}

struct UserCertificatePicker: View {
    let context: CertificateIssuanceContext
    let selected: (ManagedRecord) -> Void
    let cancel: () -> Void
    @State private var model: ManagementModel
    @State private var failure: String?

    init(context: CertificateIssuanceContext, selected: @escaping (ManagedRecord) -> Void, cancel: @escaping () -> Void) {
        self.context = context
        self.selected = selected
        self.cancel = cancel
        _model = State(initialValue: ManagementModel(resource: .user, serverID: context.serverID, connection: context.connection))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !context.isCurrent { Text("The connection changed. Reopen certificate creation.").foregroundStyle(.red) }
                if let failure { Text(failure).foregroundStyle(.red).padding() }
                TextField("Search users", text: $model.search)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .padding()
                    .disabled(!context.isCurrent)
                ManagedRecordsList(model: model, allowsSelection: context.isCurrent, showsSearch: false) { record in
                    guard context.isCurrent, model.isCurrent else { return }
                    guard ClientCertificateIdentity.userSubject(record.key) != nil else {
                        failure = "This user's public reference is not a UUID. Use an explicit client identifier instead."
                        return
                    }
                    selected(record)
                }
            }
            .navigationTitle("Select User")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
            }
        }
#if os(macOS)
        .frame(minWidth: 500, minHeight: 440)
#endif
        .task(id: model.search) {
            failure = nil
            if context.isCurrent { await model.reload() }
        }
    }
}
