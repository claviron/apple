import SwiftUI

struct InitialConfigurationView: View {
    @Bindable var applicationModel: ApplicationModel

    @State private var step: InitialConfigurationStep
    @State private var input: InitialConfigurationInput
    @State private var credentials: TLSCredentialImport
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Set when the wizard is presented over an app that already works, so
    /// backing out is possible. On first run there is nothing to go back to
    /// and no Cancel is offered.
    private let cancel: (() -> Void)?

    init(
        applicationModel: ApplicationModel,
        initialStep: InitialConfigurationStep = .welcome,
        input: InitialConfigurationInput = InitialConfigurationInput(),
        credentials: TLSCredentialImport = TLSCredentialImport(),
        cancel: (() -> Void)? = nil
    ) {
        self.applicationModel = applicationModel
        self.cancel = cancel
        _step = State(initialValue: initialStep)
        _input = State(initialValue: input)
        _credentials = State(initialValue: credentials)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressHeader
                Divider()
                stepContent
                Divider()
                navigationControls
            }
            .navigationTitle(step.title)
        }
        .alert(
            "Configuration Not Saved",
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

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Set Up Claviron")
                    .font(.headline)
                Spacer()
                Text("Step \(step.rawValue + 1) of \(InitialConfigurationStep.allCases.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(
                value: Double(step.rawValue + 1),
                total: Double(InitialConfigurationStep.allCases.count)
            )
            .accessibilityLabel("Setup progress")
            .accessibilityValue("Step \(step.rawValue + 1) of \(InitialConfigurationStep.allCases.count)")
        }
        .padding()
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .server:
            serverStep
        case .identity:
            identityStep
        case .review:
            reviewStep
        }
    }

    private var welcomeStep: some View {
        Form {
            Section {
                Label("Connect directly to your Claviron management server.", systemImage: "server.rack")
                Label("Authenticate with your existing mutual TLS files.", systemImage: "lock.shield")
                Label("Keep server configuration and credentials in this app's private storage.", systemImage: "externaldrive.badge.checkmark")
            } header: {
                Text("Native Claviron Management")
            } footer: {
                Text("The app uses gRPC directly. It does not run the Claviron command-line client.")
            }

            Section {
                Link("Learn more at claviron.app", destination: URL(string: "https://claviron.app")!)
            }
        }
        .formStyle(.grouped)
    }

    private var serverStep: some View {
        Form {
            Section("Claviron Server") {
                TextField("Name", text: $input.serverName)
                    .textContentType(.organizationName)
                TextField("HTTPS address", text: $input.serverAddress)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
            }

            Section {
                Text("Use the HTTPS origin of the management server, including its port when it is not 443.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var identityStep: some View {
        Form {
            Section {
                TextField("TLS profile name", text: $input.tlsProfileName)
                CredentialImportFields(
                    credentials: $credentials,
                    errorMessage: $errorMessage
                )
            } header: {
                Text("Mutual TLS Identity")
            } footer: {
                Text("Choose the CA certificate, client certificate, and matching private key. The files are copied into Claviron's private application storage.")
            }
        }
        .formStyle(.grouped)
    }

    private var reviewStep: some View {
        Form {
            Section("Server") {
                LabeledContent("Name", value: input.serverName)
                LabeledContent("Address", value: input.serverAddress)
            }

            Section("Mutual TLS") {
                LabeledContent("Profile", value: input.tlsProfileName)
                ForEach(TLSCredentialRole.allCases, id: \.self) { role in
                    LabeledContent(
                        role.title,
                        value: credentials[role]?.fileName ?? "Missing"
                    )
                }
            }

            Section {
                Text("Saving creates the first server, makes it active, and stores private copies of the selected TLS files. You can add more servers and shared TLS profiles later in Settings.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var navigationControls: some View {
        HStack {
            if let cancel {
                Button("Cancel", role: .cancel) {
                    cancel()
                }
                .disabled(isSaving)
                .keyboardShortcut(.cancelAction)
            }

            if step.previous != nil {
                Button("Back") {
                    goBack()
                }
                .disabled(isSaving)
            }

            Spacer()

            Button {
                advanceOrSave()
            } label: {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(step == .review ? "Save and Continue" : "Continue")
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(
                isSaving
                    || !step.canContinue(input: input, credentials: credentials)
            )
        }
        .padding()
    }

    private func goBack() {
        guard let previous = step.previous else {
            return
        }
        step = previous
    }

    private func advanceOrSave() {
        do {
            try step.validate(input: input, credentials: credentials)
            if step == .review {
                save()
            } else if let next = step.next {
                step = next
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        isSaving = true
        Task {
            defer {
                isSaving = false
            }

            do {
                try await applicationModel.saveInitialConfiguration(
                    input,
                    credentials: credentials
                )
                cancel?()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
