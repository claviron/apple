import Foundation

nonisolated enum InitialConfigurationStep: Int, CaseIterable, Equatable, Sendable {
    case key
    case server
    case identity
    case review

    var title: String {
        switch self {
        case .key:
            "Device Key"
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
        enrollment: EnrollmentInput,
        hasLoadedKey: Bool
    ) throws {
        guard hasLoadedKey else {
            throw InitialConfigurationWizardError.deviceKeyRequired
        }
        switch self {
        case .key:
            return
        case .server:
            guard !input.serverName.isBlank else {
                throw InitialConfigurationWizardError.missingServerName
            }
            _ = try enrollment.registrationURL()
        case .identity, .review:
            _ = try enrollment.endpoint()
        }
    }

    func canContinue(
        input: InitialConfigurationInput,
        enrollment: EnrollmentInput,
        hasLoadedKey: Bool
    ) -> Bool {
        do {
            try validate(input: input, enrollment: enrollment, hasLoadedKey: hasLoadedKey)
            return true
        } catch {
            return false
        }
    }
}

nonisolated enum InitialConfigurationWizardError: Error, Equatable, LocalizedError, Sendable {
    case deviceKeyRequired
    case missingServerName

    var errorDescription: String? {
        switch self {
        case .deviceKeyRequired:
            "Generate or unlock your device key."
        case .missingServerName:
            "Give this Claviron server a name."
        }
    }
}
