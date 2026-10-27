import ClavironControlPlane
import SwiftUI

/// The add and edit forms for zones and records. `submit` returns the
/// failure to show, or `nil` once the store accepted the write and the sheet
/// may close.
struct DnsEditorSheet: View {
    let editor: DnsEditor
    let submit: (DnsManagementAction) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var zoneDraft = DnsZoneDraft()
    @State private var recordDraft = DnsRecordDraft()
    @State private var failure: String?
    @State private var isSubmitting = false
    @State private var isRemovalConfirmationPresented = false

    init(editor: DnsEditor, submit: @escaping (DnsManagementAction) async -> String?) {
        self.editor = editor
        self.submit = submit
        switch editor {
        case .newZone, .newRecord:
            break
        case let .zone(zone):
            if let configuration = zone.configuration {
                _zoneDraft = State(initialValue: DnsZoneDraft(configuration))
            }
        case let .record(record), let .duplicateRecord(record):
            if let configuration = record.configuration {
                _recordDraft = State(initialValue: DnsRecordDraft(configuration))
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch editor {
                case .newZone, .zone:
                    zoneFields
                case .newRecord, .record, .duplicateRecord:
                    recordFields
                }

                if let issue {
                    Section {
                        Label(issue, systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                if let failure {
                    Section {
                        Label(failure, systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                    }
                }

                if case let .record(record) = editor {
                    Section {
                        Button("Remove Record", systemImage: "trash", role: .destructive) {
                            isRemovalConfirmationPresented = true
                        }
                        .disabled(isSubmitting)
                        .confirmationDialog(
                            DnsRemoval.record(record).title,
                            isPresented: $isRemovalConfirmationPresented,
                            titleVisibility: .visible
                        ) {
                            Button(DnsRemoval.record(record).actionTitle, role: .destructive) {
                                Task { await send(DnsRemoval.record(record).action) }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text(DnsRemoval.record(record).message)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button(confirmTitle) {
                            if let action {
                                Task { await send(action) }
                            }
                        }
                        .disabled(action == nil)
                    }
                }
            }
            .interactiveDismissDisabled(isSubmitting)
        }
#if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
#endif
    }

    // MARK: Fields

    @ViewBuilder
    private var zoneFields: some View {
        Section("Zone") {
            TextField("Domain", text: $zoneDraft.domain, prompt: Text(verbatim: "example.com"))
                .dnsHostnameInput()
            Toggle("Enabled", isOn: $zoneDraft.enabled)
        }
        Section {
            TextField("Primary name server", text: $zoneDraft.mname, prompt: Text(verbatim: "ns1.example.com"))
                .dnsHostnameInput()
            TextField("Responsible mailbox", text: $zoneDraft.rname, prompt: Text(verbatim: "hostmaster.example.com"))
                .dnsHostnameInput()
        } header: {
            Text("Start of authority")
        }
        Section {
            secondsField("Refresh", text: $zoneDraft.refresh)
            secondsField("Retry", text: $zoneDraft.retry)
            secondsField("Expire", text: $zoneDraft.expire)
            secondsField("Minimum TTL", text: $zoneDraft.minimum)
        } header: {
            Text("Timers")
        } footer: {
            Text("Seconds. The zone serial is advanced by the store, not set here.")
        }
    }

    @ViewBuilder
    private var recordFields: some View {
        Section {
            if let zone = recordZone {
                LabeledContent("Zone", value: zone)
            }
            TextField("Name", text: $recordDraft.name, prompt: Text("@ or www"))
                .dnsHostnameInput()
            Picker("Type", selection: $recordDraft.type) {
                ForEach(recordDraft.typeChoices, id: \.self) { type in
                    Text(type).tag(type)
                }
            }
            TextField("Value", text: $recordDraft.value, axis: .vertical)
                .dnsHostnameInput()
                .lineLimit(1...4)
            secondsField("TTL", text: $recordDraft.ttl)
            Toggle("Enabled", isOn: $recordDraft.enabled)
        } header: {
            Text("Record")
        }

        if recordDraft.usesPriority || hasOptionalValues {
            Section {
                numberField("Priority", text: $recordDraft.priority)
                if recordDraft.usesWeightAndPort || !recordDraft.weight.isEmpty || !recordDraft.port.isEmpty {
                    numberField("Weight", text: $recordDraft.weight)
                    numberField("Port", text: $recordDraft.port)
                }
            } header: {
                Text(recordDraft.usesWeightAndPort ? "Service" : "Preference")
            } footer: {
                Text("Leave a field empty to omit it. Zero is a value, not an omission.")
            }
        }
    }

    private func secondsField(_ title: String, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField(title, text: text, prompt: Text("seconds"))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .dnsNumberInput()
        }
    }

    private func numberField(_ title: String, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField(title, text: text, prompt: Text("none"))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .dnsNumberInput()
        }
    }

    // MARK: Submission

    private var hasOptionalValues: Bool {
        !recordDraft.priority.isEmpty || !recordDraft.weight.isEmpty || !recordDraft.port.isEmpty
    }

    private var recordZone: String? {
        switch editor {
        case let .newRecord(zone): zone
        case let .record(record), let .duplicateRecord(record): record.zone
        case .newZone, .zone: nil
        }
    }

    private var issue: String? {
        switch editor {
        case .newZone, .zone: zoneDraft.issue
        case .newRecord, .record, .duplicateRecord: recordDraft.issue
        }
    }

    private var action: DnsManagementAction? {
        switch editor {
        case .newZone:
            zoneDraft.configuration.map { .addZone($0) }
        case let .zone(zone):
            zoneDraft.configuration.map { .updateZone(id: zone.id, $0) }
        case let .newRecord(zone):
            recordDraft.configuration.map { .addRecord(zone: zone, $0) }
        case let .record(record):
            recordDraft.configuration.map { .updateRecord(id: record.id, $0) }
        case let .duplicateRecord(record):
            recordDraft.configuration.map { .addRecord(zone: record.zone, $0) }
        }
    }

    private var title: String {
        switch editor {
        case .newZone: "New Zone"
        case let .zone(zone): zone.configuration?.domain ?? "Zone"
        case .newRecord, .duplicateRecord: "New Record"
        case let .record(record): record.configuration?.name ?? "Record"
        }
    }

    private var confirmTitle: String {
        switch editor {
        case .newZone, .newRecord, .duplicateRecord: "Add"
        case .zone, .record: "Save"
        }
    }

    private func send(_ action: DnsManagementAction) async {
        isSubmitting = true
        failure = nil
        let result = await submit(action)
        isSubmitting = false
        if let result {
            failure = result
        } else {
            dismiss()
        }
    }
}

private extension View {
    func dnsHostnameInput() -> some View {
#if os(iOS)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
#else
        self.autocorrectionDisabled()
#endif
    }

    func dnsNumberInput() -> some View {
#if os(iOS)
        self.keyboardType(.numberPad)
#else
        self
#endif
    }
}
