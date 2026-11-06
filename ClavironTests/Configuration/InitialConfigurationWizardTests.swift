import Foundation
import Testing
@testable import Claviron

struct InitialConfigurationWizardTests {
    private let validInput = InitialConfigurationInput(
        serverName: "Production",
        serverAddress: "https://control.example.com:7443"
    )

    private let enrollment = EnrollmentInput(
        address: "https://enroll.example.com", username: "operator", password: "test-password"
    )

    @Test
    func stepsHaveStableForwardAndBackwardNavigation() {
        #expect(InitialConfigurationStep.key.previous == nil)
        #expect(InitialConfigurationStep.key.next == .server)
        #expect(InitialConfigurationStep.server.previous == .key)
        #expect(InitialConfigurationStep.server.next == .identity)
        #expect(InitialConfigurationStep.identity.previous == .server)
        #expect(InitialConfigurationStep.identity.next == .review)
        #expect(InitialConfigurationStep.review.previous == .identity)
        #expect(InitialConfigurationStep.review.next == nil)
    }

    @Test
    func keyStepRequiresAGeneratedOrUnlockedKey() {
        let input = InitialConfigurationInput()
        #expect(!InitialConfigurationStep.key.canContinue(input: input, enrollment: enrollment, hasLoadedKey: false))
        #expect(InitialConfigurationStep.key.canContinue(input: input, enrollment: enrollment, hasLoadedKey: true))
    }

    @Test
    func serverStepValidatesOnlyTheRegistrationAddress() throws {
        var incomplete = enrollment
        incomplete.address = "http://enroll.example.com:7443/path"
        let input = InitialConfigurationInput(serverName: "Production")

        #expect(throws: EnrollmentError.invalidAddress) {
            try InitialConfigurationStep.server.validate(input: input, enrollment: incomplete, hasLoadedKey: true)
        }
        try InitialConfigurationStep.server.validate(input: input, enrollment: enrollment, hasLoadedKey: true)
    }

    @Test
    func managementAddressMustBeHTTPSAndSeparateFromEnrollment() throws {
        let registration = try enrollment.endpoint()
        try Enrollment.validateManagementAddress("https://control.example.com:7443", registration: registration)
        #expect(throws: EnrollmentError.invalidManagementAddress) {
            try Enrollment.validateManagementAddress("http://control.example.com", registration: registration)
        }
        #expect(throws: EnrollmentError.sameOrigin) {
            try Enrollment.validateManagementAddress("https://ENROLL.example.com.:443", registration: registration)
        }
    }

    @Test
    func probeRequiresTheRegistrationEndpointResponse() throws {
        let url = try enrollment.registrationURL()
        let ready = try #require(HTTPURLResponse(
            url: url, statusCode: 204, httpVersion: nil,
            headerFields: ["Claviron-Registration": "1"]
        ))
        try Enrollment.validateProbeResponse(ready)

        let unrelated = try #require(HTTPURLResponse(
            url: url, statusCode: 204, httpVersion: nil, headerFields: nil
        ))
        #expect(throws: EnrollmentError.invalidProbe) {
            try Enrollment.validateProbeResponse(unrelated)
        }

        let unavailable = try #require(HTTPURLResponse(
            url: url, statusCode: 503, httpVersion: nil,
            headerFields: ["Claviron-Registration": "1"]
        ))
        #expect(throws: EnrollmentError.probeRejected(503)) {
            try Enrollment.validateProbeResponse(unavailable)
        }
    }

    @Test
    func identityStepRequiresEnrollmentCredentials() {
        var incomplete = enrollment
        incomplete.password = ""

        #expect(throws: EnrollmentError.missingCredentials) {
            try InitialConfigurationStep.identity.validate(
                input: validInput,
                enrollment: incomplete,
                hasLoadedKey: true
            )
        }
    }

    @Test
    func completedDraftCanReachReviewAndBuildTheRegistryConfiguration() throws {
        var draft = validInput
        draft.serverAddress = ""
        try InitialConfigurationStep.review.validate(
            input: draft,
            enrollment: enrollment,
            hasLoadedKey: true
        )
        #expect(InitialConfigurationStep.review.canContinue(
            input: draft,
            enrollment: enrollment,
            hasLoadedKey: true
        ))

        let configuration = try validInput.addingTo(
            .empty,
            username: enrollment.username,
            serverID: ServerID(rawValue: "primary"),
            tlsProfileID: TLSProfileID(rawValue: "operator"),
            credentialPaths: .validationPlaceholder
        )
        let server = try #require(configuration.activeServer)
        #expect(server.name == "Production")
        #expect(configuration.tlsProfiles.first?.name == "operator@Production")
        #expect(configuration.connectionName(for: server) == "operator@Production")
    }
}
