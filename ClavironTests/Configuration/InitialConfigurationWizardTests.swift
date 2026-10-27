import Foundation
import Testing
@testable import Claviron

struct InitialConfigurationWizardTests {
    private let validInput = InitialConfigurationInput(
        serverName: "Production",
        serverAddress: "https://control.example.com:7443",
        tlsProfileName: "Operator"
    )

    @Test
    func stepsHaveStableForwardAndBackwardNavigation() {
        #expect(InitialConfigurationStep.welcome.previous == nil)
        #expect(InitialConfigurationStep.welcome.next == .server)
        #expect(InitialConfigurationStep.server.previous == .welcome)
        #expect(InitialConfigurationStep.server.next == .identity)
        #expect(InitialConfigurationStep.identity.previous == .server)
        #expect(InitialConfigurationStep.identity.next == .review)
        #expect(InitialConfigurationStep.review.previous == .identity)
        #expect(InitialConfigurationStep.review.next == nil)
    }

    @Test
    func serverStepUsesTheRegistryEndpointRules() {
        var input = validInput
        input.serverAddress = "http://control.example.com:7443/path"

        #expect(throws: InitialConfigurationWizardError.invalidServerAddress) {
            try InitialConfigurationStep.server.validate(
                input: input,
                credentials: .validWizardCredentials
            )
        }
        #expect(!InitialConfigurationStep.server.canContinue(
            input: input,
            credentials: .validWizardCredentials
        ))
    }

    @Test
    func identityStepRequiresEveryMutualTLSFile() {
        var credentials = TLSCredentialImport.validWizardCredentials
        credentials.clientPrivateKey = nil

        #expect(throws: CredentialStoreError.missingCredential(.clientPrivateKey)) {
            try InitialConfigurationStep.identity.validate(
                input: validInput,
                credentials: credentials
            )
        }
    }

    @Test
    func completedDraftCanReachReviewAndBuildTheRegistryConfiguration() throws {
        try InitialConfigurationStep.review.validate(
            input: validInput,
            credentials: .validWizardCredentials
        )
        #expect(InitialConfigurationStep.review.canContinue(
            input: validInput,
            credentials: .validWizardCredentials
        ))

        let configuration = try validInput.makeConfiguration(
            serverID: ServerID(rawValue: "primary"),
            tlsProfileID: TLSProfileID(rawValue: "operator"),
            credentialPaths: .validationPlaceholder
        )
        #expect(configuration.activeServer?.name == "Production")
        #expect(configuration.tlsProfiles.first?.name == "Operator")
    }
}

private extension TLSCredentialImport {
    static let validWizardCredentials = TLSCredentialImport(
        certificateAuthority: ImportedCredential(
            fileName: "ca.pem",
            data: Data("ca".utf8)
        ),
        clientCertificate: ImportedCredential(
            fileName: "client.pem",
            data: Data("certificate".utf8)
        ),
        clientPrivateKey: ImportedCredential(
            fileName: "client-key.pem",
            data: Data("private key".utf8)
        )
    )
}
