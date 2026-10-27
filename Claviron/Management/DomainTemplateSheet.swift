import ClavironControlPlane
import SwiftUI

/// The registration template editor: pick a stored template or start a new
/// one, edit its contacts and nameservers, save or remove it. One form, no
/// separate list; the picker is the inventory.
struct DomainTemplateSheet: View {
    let serverID: ServerID
    @Bindable var connectionModel: ConnectionModel
    /// Returns the failure to show, or nil once the store accepted the write.
    let submit: (DomainManagementAction) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var templates: [DomainTemplateObservation] = []
    @State private var loadFailure: String?
    @State private var isLoading = true
    @State private var selection: String = DomainTemplateSheet.newTemplate
    @State private var draft = DomainTemplateDraft()
    @State private var failure: String?
    @State private var isSubmitting = false
    @State private var isRemovalConfirmationPresented = false

    static let newTemplate = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Template", selection: $selection) {
                        Text("New template…").tag(Self.newTemplate)
                        ForEach(templates) { template in
                            Text(template.name).tag(template.name)
                        }
                    }
                    .onChange(of: selection) { _, name in
                        load(name)
                    }
                    TextField("Name", text: $draft.name, prompt: Text("default"))
                        .autocorrectionDisabled()
                        .disabled(selection != Self.newTemplate)
                } header: {
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading templates…")
                        }
                    }
                } footer: {
                    if let loadFailure {
                        Label(loadFailure, systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                            .copyableMessage(loadFailure)
                    } else if let updatedAt = selectedTemplate?.updatedAt {
                        Text("Last saved \(updatedAt.formatted())")
                    }
                }

                contactSection("Registrant", contact: $draft.registrant)
                optionalContactSection("Admin", enabled: $draft.hasAdmin, contact: $draft.admin)
                optionalContactSection("Tech", enabled: $draft.hasTech, contact: $draft.tech)
                optionalContactSection("Billing", enabled: $draft.hasBilling, contact: $draft.billing)

                Section {
                    TextEditor(text: $draft.nameservers)
                        .font(.body.monospaced())
                        .frame(minHeight: 72)
                } header: {
                    Text("Nameservers")
                } footer: {
                    Text("One hostname per line; leave empty to let the registrar assign its defaults.")
                }

                if let failure {
                    Section {
                        Label(failure, systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                            .copyableMessage(failure)
                    }
                }

                if selection != Self.newTemplate {
                    Section {
                        Button("Remove Template", systemImage: "trash", role: .destructive) {
                            isRemovalConfirmationPresented = true
                        }
                        .disabled(isSubmitting)
                        .confirmationDialog(
                            "Remove template \(selection)?",
                            isPresented: $isRemovalConfirmationPresented,
                            titleVisibility: .visible
                        ) {
                            Button("Remove", role: .destructive) {
                                Task { await remove() }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("A template still assigned to a registrar or domain is refused by the store.")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Registration Templates")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selection == Self.newTemplate ? "Create" : "Save") {
                        Task { await save() }
                    }
                    .disabled(!draft.canSubmit || isSubmitting)
                }
            }
            .task { await reload() }
        }
        .frame(minWidth: 560, minHeight: 620)
    }

    private var selectedTemplate: DomainTemplateObservation? {
        templates.first { $0.name == selection }
    }

    private func contactSection(_ title: String, contact: Binding<DomainContact>) -> some View {
        Section(title) {
            contactFields(contact)
        }
    }

    private func optionalContactSection(
        _ title: String,
        enabled: Binding<Bool>,
        contact: Binding<DomainContact>
    ) -> some View {
        Section {
            Toggle("Separate \(title.lowercased()) contact", isOn: enabled)
            if enabled.wrappedValue {
                contactFields(contact)
            }
        } header: {
            Text(title)
        } footer: {
            if !enabled.wrappedValue {
                Text("Off: the registrar reuses the registrant for this role.")
            }
        }
    }

    @ViewBuilder
    private func contactFields(_ contact: Binding<DomainContact>) -> some View {
        TextField("First name", text: contact.firstName)
        TextField("Last name", text: contact.lastName)
        TextField("Address", text: contact.address1)
        TextField("Address line 2", text: contact.address2)
        TextField("City", text: contact.city)
        TextField("State / province", text: contact.stateProvince)
        TextField("Postal code", text: contact.postalCode)
        TextField("Country (ISO 2)", text: contact.country)
            .autocorrectionDisabled()
        TextField("Phone (+NNN.NNNNNNNNNN)", text: contact.phone)
            .autocorrectionDisabled()
        TextField("Email", text: contact.email)
            .textContentType(.emailAddress)
            .autocorrectionDisabled()
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            templates = try await connectionModel.loadDomainTemplates(for: serverID)
            loadFailure = nil
            if selection != Self.newTemplate, !templates.contains(where: { $0.name == selection }) {
                selection = Self.newTemplate
            }
            load(selection)
        } catch {
            loadFailure = (error as? ClavironClientFailure)?.localizedDescription ?? String(describing: error)
        }
    }

    private func load(_ name: String) {
        failure = nil
        guard let template = templates.first(where: { $0.name == name }) else {
            draft = DomainTemplateDraft()
            return
        }
        draft = DomainTemplateDraft(template)
    }

    private func save() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let name = draft.trimmedName
        failure = await submit(.putTemplate(
            name: name,
            contacts: draft.contacts,
            nameservers: draft.nameserverList
        ))
        if failure == nil {
            await reload()
            selection = name
            load(name)
        }
    }

    private func remove() async {
        isSubmitting = true
        defer { isSubmitting = false }
        failure = await submit(.removeTemplate(name: selection))
        if failure == nil {
            selection = Self.newTemplate
            await reload()
        }
    }
}

/// The editable form state; `contacts` is what the store receives.
private struct DomainTemplateDraft {
    var name = ""
    var registrant = DomainContact()
    var hasAdmin = false
    var admin = DomainContact()
    var hasTech = false
    var tech = DomainContact()
    var hasBilling = false
    var billing = DomainContact()
    var nameservers = ""

    init() {}

    init(_ template: DomainTemplateObservation) {
        name = template.name
        if let contacts = template.contacts {
            registrant = contacts.registrant
            if let contact = contacts.admin {
                hasAdmin = true
                admin = contact
            }
            if let contact = contacts.tech {
                hasTech = true
                tech = contact
            }
            if let contact = contacts.billing {
                hasBilling = true
                billing = contact
            }
        }
        nameservers = template.nameservers.joined(separator: "\n")
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var contacts: DomainContacts {
        DomainContacts(
            registrant: registrant,
            admin: hasAdmin ? admin : nil,
            tech: hasTech ? tech : nil,
            billing: hasBilling ? billing : nil
        )
    }

    var nameserverList: [String] {
        nameservers.split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    /// The server validates every field; the form only refuses an empty name
    /// and an empty registrant, so its message is the store's own.
    var canSubmit: Bool {
        !trimmedName.isEmpty && !registrant.email.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
