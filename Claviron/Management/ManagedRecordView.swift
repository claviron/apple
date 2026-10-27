import ClavironControlPlane
import SwiftUI

struct ManagedRecordView: View {
    let key: ManagedRecordKey
    let serverID: ServerID
    let connection: ConnectionModel
    let changed: () async -> Void
    @State private var record: ManagedRecord?
    @State private var schema: ManagementSchema?
    @State private var session: ManagementSession?
    @State private var failure: String?
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var creatingCertificate = false
    @State private var certificateResult: String?
    @State private var selectedRelation: ManagementRelation?
    @State private var showingAssignments = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isWorkspacePageActive) private var isActive

    private var isCurrent: Bool { session?.id != nil && session?.id == connection.managementSessionID(for: serverID) }
    private var capabilities: [String] { connection.serverInfo(for: serverID)?.capabilities ?? [] }

    var body: some View {
        ManagementDetailLayout {
            if isCurrent, let record {
                ManagementDetailCard(record.title, systemImage: key.resource.systemImage, tint: .indigo) {
                    LabeledContent("Reference", value: record.key.reference).textSelection(.enabled)
                    ForEach(record.values.keys.sorted(), id: \.self) { name in
                        let field = schema?.recordSchema["properties"]?.object?[name]?.object
                        if field?["writeOnly"]?.bool != true, let value = record.values[name] {
                            LabeledContent(field?["title"]?.string ?? ManagementResourceName.title(name, fallback: name)) {
                                Text(value == .null ? "—" : value.text).textSelection(.enabled)
                            }
                        }
                    }
                }
                if capabilities.contains("authorization"), key.resource != .permission {
                    ManagementDetailCard("Direct Assignments", systemImage: "person.badge.key") {
                        if key.resource == .user {
                            Button("Roles…") { open(.userRoles) }
                            Button("Permissions…") { open(.userPermissions) }
                        } else {
                            Button("Permissions…") { open(.rolePermissions) }
                        }
                    }
                    .disabled(!isCurrent)
                }
            } else if failure == nil { ProgressView("Loading…") }
            if let failure { ManagementDetailCard { Text(failure).foregroundStyle(.red).textSelection(.enabled) } }
            if let certificateResult { ManagementDetailCard { Text(certificateResult).textSelection(.enabled) } }
        }
        .workspaceNavigationTitle(record?.title ?? key.resource.singular)
        .toolbar {
            if isActive {
                if schema?.operations.contains(.update) == true, schema?.update != nil {
                    Button("Edit", systemImage: "pencil") { editing = true }.disabled(!isCurrent || record == nil)
                }
                if key.resource == .user, capabilities.contains("mtls"), ClientCertificateIdentity.userSubject(key) != nil {
                    Button("Create Client Certificate…", systemImage: "person.crop.circle.badge.checkmark") { creatingCertificate = true }
                        .disabled(!isCurrent || record == nil)
                }
                if schema?.operations.contains(.delete) == true {
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                        .disabled(!isCurrent || record == nil || isDeleting)
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let schema, let record, let session {
                ManagementFormView(schema: schema, record: record, session: session, serverID: serverID, connection: connection) { updated in
                    self.record = updated
                    await changed()
                }
            }
        }
        .sheet(isPresented: $showingAssignments) {
            if let selectedRelation, let session {
                ManagementAssignmentsView(key: ManagementAssignmentKey(relation: selectedRelation, reference: key.reference), session: session,
                                          serverID: serverID, connection: connection)
            }
        }
        .sheet(isPresented: $creatingCertificate) {
            if let record, let session {
                LocalCertificateSheet(
                    submit: { action in
                        do {
                            guard isCurrent else { throw ManagementClientError("The connection changed. Reload this user before issuing a certificate.") }
                            let result = try await connection.performCertificateAction(action, for: serverID)
                            if case let .local(info) = result {
                                certificateResult = "Created \(info.commonName) · \(info.subjectURIs.joined(separator: ", "))"
                            }
                            return nil
                        } catch { return error.localizedDescription }
                    },
                    context: CertificateIssuanceContext(serverID: serverID, connection: connection, sessionID: session.id, initialUser: record)
                )
            }
        }
        .confirmationDialog("Delete this \(key.resource.singular.lowercased())?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await remove() } }
        }
        .pageRefreshable(every: .seconds(2), enabled: capabilities.contains(key.resource.capability)) {
            await reload()
        }
    }

    private func open(_ relation: ManagementRelation) {
        selectedRelation = relation
        showingAssignments = true
    }

    private func reload() async {
        failure = nil
        if !isCurrent { record = nil; schema = nil; session = nil }
        do {
            let captured = try connection.managementSession(for: serverID)
            let description = try await captured.client.loadManagementSchema(key.resource)
            guard description.operations.contains(.read) else { throw ManagementClientError("Reading this record is not available for this identity.") }
            let loaded = try await captured.client.loadManagedRecord(key)
            guard !Task.isCancelled, connection.managementSessionID(for: serverID) == captured.id else { return }
            session = captured
            schema = description
            record = loaded
        } catch {
            guard !Task.isCancelled else { return }
            failure = error.localizedDescription
        }
    }

    private func remove() async {
        guard isCurrent, !isDeleting, let record, let session, schema?.operations.contains(.delete) == true else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            let result = try await session.client.performManagementAction(.delete(key: record.key, revision: record.revision))
            guard isCurrent else { return }
            guard result == .deleted else { throw ManagementClientError("The server did not confirm deletion.") }
            await changed()
            dismiss()
        } catch { failure = error.localizedDescription }
    }
}
