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
    func managementAddressMustBeHTTPSAndMayShareTheEnrollHost() throws {
        try Enrollment.validateManagementAddress("https://control.example.com:7443")
        // Enrollment and management can share one host: ALPN tells them apart.
        try Enrollment.validateManagementAddress("https://enroll.example.com")
        #expect(throws: EnrollmentError.invalidManagementAddress) {
            try Enrollment.validateManagementAddress("http://control.example.com")
        }
    }

    @Test
    func probeRequiresTheEnrollmentEndpointResponse() throws {
        let marker = ["claviron-mtls-enroll": "1"]
        try Enrollment.validateProbe(EnrollmentHTTPResponse(status: 204, headers: marker, body: Data()))
        #expect(throws: EnrollmentError.invalidProbe) {
            try Enrollment.validateProbe(EnrollmentHTTPResponse(status: 204, headers: [:], body: Data()))
        }
        #expect(throws: EnrollmentError.probeRejected(503)) {
            try Enrollment.validateProbe(EnrollmentHTTPResponse(status: 503, headers: marker, body: Data()))
        }
    }

    @Test
    func anAnswerIsReadUpToItsDeclaredLength() throws {
        let raw = Data("HTTP/1.1 201 Created\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}trailing".utf8)
        let response = try EnrollmentHTTPResponse.parse(raw)
        #expect(response.status == 201)
        #expect(response.headers["content-type"] == "application/json")
        #expect(response.body == Data("{}".utf8))
        #expect(throws: EnrollmentError.invalidResponse) {
            try EnrollmentHTTPResponse.parse(Data("HTTP/1.1 201 Created\r\nTransfer-Encoding: chunked\r\n\r\n".utf8))
        }
    }

    @Test
    func aDeviceIsLabelledAfterItsHost() {
        #expect(EnrollmentInput.deviceLabel(host: "Laptop.local") == "laptop-app")
        #expect(EnrollmentInput.deviceLabel(host: "MacBook_Pro") == "macbook-pro-app")
        #expect(EnrollmentInput.isDeviceLabel("laptop-app"))
        #expect(!EnrollmentInput.isDeviceLabel("Laptop"))
        #expect(!EnrollmentInput.isDeviceLabel("-app"))
        var unnamed = enrollment
        unnamed.device = ""
        #expect(throws: EnrollmentError.invalidDevice) { try unnamed.endpoint() }
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
