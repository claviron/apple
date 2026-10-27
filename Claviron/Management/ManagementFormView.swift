import ClavironControlPlane
import SwiftUI

struct ManagementFormView: View {
    let schema: ManagementSchema
    let record: ManagedRecord?
    let session: ManagementSession
    let serverID: ServerID
    let connection: ConnectionModel
    let committed: (ManagedRecord) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ManagementFormDraft?
    @State private var failure: String?
    @State private var violations: [ManagementViolation] = []
    @State private var isSaving = false

    private var isCurrent: Bool { connection.managementSessionID(for: serverID) == session.id }

    var body: some View {
        NavigationStack {
            Form {
                if let draft {
                    ForEach(draft.definition.fields) { field in
                        Section {
                            fieldControl(field)
                            if field.nullable && field.choices.isEmpty && field.kind != .boolean {
                                Toggle("No value (null)", isOn: Binding(
                                    get: { self.draft?.inputs[field.id] == .null },
                                    set: { self.draft?.inputs[field.id] = $0 ? .null : ManagementFieldInput(record?.values[field.id]) }
                                ))
                            }
                            ForEach(violations.filter { $0.path == ManagementFormDraft.pointer(field.id) }) { violation in
                                Text(violation.message).foregroundStyle(.red)
                            }
                        } header: {
                            Text(field.title + (record == nil && field.required ? " *" : ""))
                        } footer: {
                            if let description = field.description { Text(description) }
                        }
                    }
                }
                ForEach(violations.filter { violation in
                    !(draft?.definition.fields.contains { ManagementFormDraft.pointer($0.id) == violation.path } ?? false)
                }) { violation in
                    Text(violation.message).foregroundStyle(.red)
                }
                if !isCurrent { Text("The connection changed. Close this form and reload the record.").foregroundStyle(.red) }
                if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
                if isSaving { ProgressView("Saving…") }
            }
            .formStyle(.grouped)
            .disabled(isSaving || !isCurrent)
            .navigationTitle("\(record == nil ? "Create" : "Edit") \(schema.resource.singular)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(draft == nil || isSaving || !isCurrent)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
#if os(macOS)
        .frame(minWidth: 500, minHeight: 440)
#endif
        .onAppear(perform: prepare)
    }

    private func prepare() {
        guard draft == nil else { return }
        do {
            guard let form = record == nil ? schema.create : schema.update else { throw ManagementFormFields.unsupported }
            draft = try ManagementFormDraft(definition: ManagementFormFields(form), record: record?.values)
        } catch { failure = error.localizedDescription }
    }

    @ViewBuilder
    private func fieldControl(_ field: ManagementField) -> some View {
        let input = Binding<ManagementFieldInput>(
            get: { draft?.inputs[field.id] ?? .omitted },
            set: { draft?.inputs[field.id] = $0 }
        )
        if !field.choices.isEmpty || field.kind == .boolean {
            let choices = field.kind == .boolean && field.choices.isEmpty
                ? [ManagementValue.bool(true), .bool(false)] : field.choices.filter { $0 != .null }
            Picker(field.title, selection: input) {
                Text(record == nil ? "Not set" : "Leave unchanged").tag(ManagementFieldInput.omitted)
                if field.nullable { Text("No value (null)").tag(ManagementFieldInput.null) }
                if case .text = input.wrappedValue, !choices.contains(where: { $0.text == input.wrappedValue.text }) {
                    Text("Current: \(input.wrappedValue.text)").tag(input.wrappedValue)
                }
                ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                    Text(choice.text).tag(ManagementFieldInput.text(choice.text))
                }
            }
            .labelsHidden()
        } else {
            let text = Binding<String>(get: { input.wrappedValue.text }, set: { input.wrappedValue = .text($0) })
            if field.secret {
                SecureField(field.title, text: text).privacySensitive()
            } else if field.kind == .object || field.kind == .array {
                TextEditor(text: text).font(.body.monospaced()).frame(minHeight: 100)
            } else {
                TextField(field.title, text: text).autocorrectionDisabled()
            }
        }
    }

    private func save() async {
        guard !isSaving, isCurrent, let draft else { return }
        failure = nil
        violations = []
        do {
            let document = try draft.document()
            let action: ManagementAction
            if let record {
                action = .update(key: record.key, revision: record.revision, schemaRevision: schema.revision, changes: document)
            } else {
                action = .create(resource: schema.resource, schemaRevision: schema.revision, values: document)
            }
            isSaving = true
            defer { isSaving = false }
            let result = try await session.client.performManagementAction(action)
            guard isCurrent else { return }
            switch result {
            case let .validation(errors): violations = errors
            case let .record(updated):
                await committed(updated)
                dismiss()
            case .deleted: throw ManagementClientError("The server returned an unexpected mutation result.")
            }
        } catch let error as ManagementInputError {
            violations = [ManagementViolation(path: error.path, code: "input", message: error.message)]
        } catch { failure = error.localizedDescription }
    }
}
