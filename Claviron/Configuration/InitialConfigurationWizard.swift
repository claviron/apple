import Foundation

nonisolated enum InitialConfigurationStep: Int, CaseIterable, Equatable, Sendable {
    case welcome
    case server
    case identity
    case review

    var title: String {
        switch self {
        case .welcome:
            "Welcome"
        case .server:
            "Server"
        case .identity:
            "Mutual TLS"
        case .review:
            "Review"
        }
    }

    var next: InitialConfigurationStep? {
        Self(rawValue: rawValue + 1)
    }

    var previous: InitialConfigurationStep? {
        Self(rawValue: rawValue - 1)
    }

    func validate(
        input: InitialConfigurationInput,
        credentials: TLSCredentialImport
    ) throws {
        switch self {
        case .welcome:
            return
        case .server:
            guard !input.serverName.isBlank else {
                throw InitialConfigurationWizardError.missingServerName
            }
            guard input.serverAddress.isValidHTTPSEndpoint else {
                throw InitialConfigurationWizardError.invalidServerAddress
            }
        case .identity:
            guard !input.tlsProfileName.isBlank else {
                throw InitialConfigurationWizardError.missingTLSProfileName
            }
            try credentials.validate()
        case .review:
            _ = try input.makeConfiguration(
                serverID: ServerID(rawValue: "initial-server"),
                tlsProfileID: TLSProfileID(rawValue: "initial-identity"),
                credentialPaths: .validationPlaceholder
            )
            try credentials.validate()
        }
    }

    func canContinue(
        input: InitialConfigurationInput,
        credentials: TLSCredentialImport
    ) -> Bool {
        do {
            try validate(input: input, credentials: credentials)
            return true
        } catch {
            return false
        }
    }
}

nonisolated enum InitialConfigurationWizardError: Error, Equatable, LocalizedError, Sendable {
    case missingServerName
    case invalidServerAddress
    case missingTLSProfileName

    var errorDescription: String? {
        switch self {
        case .missingServerName:
            "Give this Claviron server a name."
        case .invalidServerAddress:
            "Enter an HTTPS server address without a path."
        case .missingTLSProfileName:
            "Give this mutual TLS identity a name."
        }
    }
}
