import SwiftUI

struct InitialConfigurationView: View {
    @Bindable var applicationModel: ApplicationModel

    @State private var step: InitialConfigurationStep
    @State private var input: InitialConfigurationInput
    @State private var enrollment = EnrollmentInput()
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Set when the wizard is presented over an app that already works, so
    /// backing out is possible. On first run there is nothing to go back to
    /// and no Cancel is offered.
    private let cancel: (() -> Void)?

    init(
        applicationModel: ApplicationModel,
        initialStep: InitialConfigurationStep = .key,
        input: InitialConfigurationInput = InitialConfigurationInput(),
        cancel: (() -> Void)? = nil
    ) {
        self.applicationModel = applicationModel
        self.cancel = cancel
        _step = State(initialValue: initialStep)
        _input = State(initialValue: input)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressHeader
                Divider()
                stepContent
                    .disabled(isSaving)
                Divider()
                navigationControls
            }
            .navigationTitle(step.title)
        }
        .alert(
            "Setup Could Not Continue",
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
        case .key:
            keyStep
        case .server:
            serverStep
        case .identity:
            identityStep
        case .review:
            reviewStep
        }
    }

    private var keyStep: some View {
        Form {
            Section {
                DeviceKeyView(applicationModel: applicationModel, allowsCreation: true)
            } footer: {
                Text("This device uses the same key to register with different servers.")
            }
        }
        .formStyle(.grouped)
    }

    private var serverStep: some View {
        Form {
            Section {
                SetupField(
                    "Server name", text: $input.serverName,
                    prompt: "Example Server", contentType: .organizationName
                )
                SetupField(
                    "Registration HTTPS address", text: $enrollment.address,
                    prompt: "https://register.example.com", contentType: .URL
                )
            } header: {
                Text("Claviron Server")
            } footer: {
                Text("Use the registration address. Claviron receives the management address after registration.")
            }
        }
        .formStyle(.grouped)
    }

    private var identityStep: some View {
        Form {
            Section {
                SetupField("Username", text: $enrollment.username, contentType: .username)
                SetupField(
                    "Account password", text: $enrollment.password,
                    isSecure: true, contentType: .password
                )
            } header: {
                Text("Mutual TLS Identity")
            } footer: {
                Text("Your private key stays on this device.")
            }
        }
        .formStyle(.grouped)
    }

    private var reviewStep: some View {
        Form {
            Section("Server") {
                LabeledContent("Name", value: input.serverName)
                LabeledContent("Registration address", value: enrollment.address)
            }

            Section("Mutual TLS") {
                LabeledContent(
                    "Profile",
                    value: TLSProfile.identityName(
                        username: enrollment.username, serverName: input.serverName
                    )
                )
            }

            Section {
                Text("Saving stores the TLS identity in Claviron's private storage and adds the server to Settings.")
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
                    Text(continueTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(
                isSaving
                    || !step.canContinue(
                        input: input, enrollment: enrollment, hasLoadedKey: hasLoadedKey
                    )
            )
        }
        .padding()
    }

    private var hasLoadedKey: Bool {
        applicationModel.deviceKeyStatus?.isLoaded == true
    }

    private var continueTitle: String {
        switch step {
        case .server: "Check Server"
        case .review: "Save and Continue"
        default: "Continue"
        }
    }

    private func goBack() {
        guard let previous = step.previous else {
            return
        }
        step = previous
    }

    private func advanceOrSave() {
        do {
            try step.validate(
                input: input, enrollment: enrollment, hasLoadedKey: hasLoadedKey
            )
            switch step {
            case .server:
                checkServer()
            case .review:
                save()
            case .key, .identity:
                if let next = step.next { step = next }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func checkServer() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await Enrollment.probe(enrollment)
                step = .identity
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            defer {
                isSaving = false
            }

            do {
                let key = try await applicationModel.enrollmentKey()
                let registered = try await Enrollment.issue(enrollment, key: key)
                var profile = input
                profile.serverAddress = registered.managementAddress
                try await applicationModel.saveEnrollment(
                    profile, username: enrollment.username, certificates: registered.certificates
                )
                enrollment.password = ""
                cancel?()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
