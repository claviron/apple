import ClavironControlPlane
import SwiftUI

struct ManagementAssignmentsView: View {
    let key: ManagementAssignmentKey
    let session: ManagementSession
    let serverID: ServerID
    let connection: ConnectionModel
    @State private var candidates: ManagementModel
    @State private var schema: ManagementAssignmentSchema?
    @State private var original: ManagementAssignments?
    @State private var members: Set<String> = []
    @State private var failure: String?
    @State private var violations: [ManagementViolation] = []
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    init(key: ManagementAssignmentKey, session: ManagementSession, serverID: ServerID, connection: ConnectionModel) {
        self.key = key
        self.session = session
        self.serverID = serverID
        self.connection = connection
        _candidates = State(initialValue: ManagementModel(resource: key.relation.target, serverID: serverID, connection: connection))
    }

    private var isCurrent: Bool { session.id == connection.managementSessionID(for: serverID) }
    private var editable: Bool { schema?.operations.contains(.replaceAssignments) == true && isCurrent }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section("Direct \(key.relation.title)") {
                        if original == nil && failure == nil { ProgressView("Loading…") }
                        ForEach(members.sorted(), id: \.self) { reference in
                            HStack {
                                Text(candidates.page?.records.first { $0.key.reference == reference }?.title ?? reference)
                                    .textSelection(.enabled)
                                Spacer()
                                if editable {
                                    Button("Remove", systemImage: "minus.circle") { members.remove(reference) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        if original != nil && members.isEmpty { Text("No direct assignments").foregroundStyle(.secondary) }
                    }
                    if let failure { Text(failure).foregroundStyle(.red) }
                    if !isCurrent { Text("The connection changed. Close and reopen this view.").foregroundStyle(.red) }
                    ForEach(violations) { violation in Text(violation.message).foregroundStyle(.red) }
                }
                .frame(maxHeight: 230)
                if editable {
                    Divider()
                    ManagedRecordsList(model: candidates) { record in members.insert(record.key.reference) }
                }
            }
            .disabled(isSaving)
            .navigationTitle(key.relation.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if editable {
                        Button("Save") { Task { await save() } }
                            .disabled(isSaving || original == nil || Set(original?.members ?? []) == members)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
#if os(macOS)
        .frame(minWidth: 500, minHeight: 540)
#endif
        .task { await load() }
    }

    private func load() async {
        do {
            guard isCurrent else { return }
            let description = try await session.client.loadAssignmentSchema(key.relation)
            guard description.operations.contains(.readAssignments) else { throw ManagementClientError("Direct assignments are not readable by this identity.") }
            let assignments = try await session.client.loadAssignments(key)
            guard isCurrent, !Task.isCancelled else { return }
            schema = description
            original = assignments
            members = Set(assignments.members)
            if editable { await candidates.reload() }
        } catch { failure = error.localizedDescription }
    }

    private func save() async {
        guard editable, !isSaving, let original else { return }
        isSaving = true
        failure = nil
        violations = []
        defer { isSaving = false }
        do {
            let value = ManagementAssignments(key: key, revision: original.revision, members: members.sorted())
            let result = try await session.client.replaceAssignments(value)
            guard isCurrent else { return }
            switch result {
            case let .validation(errors): violations = errors
            case .assignments: dismiss()
            }
        } catch { failure = error.localizedDescription }
    }
}
