import Testing
@testable import ClavironControlPlane

@Suite("Application observation mapping")
struct ApplicationObservationMappingTests {
    @Test("Application command receipts reject a mismatched acknowledged identity")
    func applicationCommandReceiptValidatesIdentity() throws {
        let id = ApplicationIDObservation(runtime: "php", name: "storefront")
        let action = ApplicationManagementAction.start(id: id)
        var response = Claviron_Applications_ApplicationCommandResponse()
        response.id.runtime = "php"
        response.id.name = "other"
        response.accepted = true

        #expect(throws: ClavironClientFailure.self) {
            try DirectClavironClient.applicationReceipt(action: action, response: response)
        }
    }

    @Test("Application, placement, and pool facts preserve optional presence")
    func applicationFactsArePreserved() {
        var generated = Claviron_Applications_ApplicationStatus()
        generated.id.runtime = "php"
        generated.id.name = "storefront"

        var placement = Claviron_Applications_ApplicationPlacement()
        placement.member.nodeID = 3
        placement.member.role = .UNRECOGNIZED(81)
        placement.lifecycle = .UNRECOGNIZED(82)
        placement.enabled = true
        placement.generation = 7
        placement.pool.accepting = false
        placement.pool.instances = 8
        placement.pool.ready = 5
        placement.pool.busy = 2
        placement.pool.retiring = 1
        placement.pool.backingOff = 0
        placement.lastError = ""
        placement.lastErrorTruncated = true
        placement.observedAt.seconds = 120
        placement.description_p.runtime = "php"
        placement.description_p.frameworks = ["example-framework", "example-adapter"]
        placement.description_p.icon = "server"
        placement.description_p.runner = "example-runner"
        placement.description_p.requestMode = "application"
        generated.placements = [placement]

        let application = DirectClavironClient.applicationObservation(generated)

        #expect(application.applicationID == ApplicationIDObservation(
            runtime: "php",
            name: "storefront"
        ))
        #expect(application.placements.count == 1)
        let mapped = application.placements[0]
        #expect(mapped.member == ApplicationMemberObservation(
            nodeID: 3,
            role: .unrecognized(81)
        ))
        #expect(mapped.lifecycle == .unrecognized(82))
        #expect(mapped.enabled)
        #expect(mapped.generation == 7)
        #expect(mapped.pool == ApplicationPoolObservation(
            accepting: false,
            instances: 8,
            ready: 5,
            busy: 2,
            retiring: 1,
            backingOff: 0,
            exhausted: nil
        ))
        #expect(mapped.lastError == "")
        #expect(mapped.lastErrorTruncated)
        #expect(mapped.observedAt?.timeIntervalSince1970 == 120)
        #expect(application.description == ApplicationDescriptionObservation(
            runtime: "php", frameworks: ["example-framework", "example-adapter"],
            runner: "example-runner", requestMode: "application", icon: "server"
        ))
        // An absent report must not be replaced with another worker's description.
        let otherPlacement = ApplicationPlacementObservation(
            member: mapped.member, lifecycle: mapped.lifecycle, enabled: mapped.enabled,
            generation: mapped.generation, pool: mapped.pool, lastError: mapped.lastError,
            lastErrorTruncated: mapped.lastErrorTruncated, observedAt: mapped.observedAt
        )
        #expect(ApplicationObservation(applicationID: application.applicationID,
            placements: [mapped, otherPlacement]).description == nil)
    }

    @Test("Absent application messages remain absent")
    func absentMessagesRemainAbsent() {
        var generated = Claviron_Applications_ApplicationStatus()
        generated.placements = [Claviron_Applications_ApplicationPlacement()]

        let application = DirectClavironClient.applicationObservation(generated)

        #expect(application.applicationID == nil)
        #expect(application.placements[0].member == nil)
        #expect(application.placements[0].pool == nil)
        #expect(application.placements[0].lastError == nil)
        #expect(application.placements[0].observedAt == nil)
        #expect(application.placements[0].description == nil)
    }

    @Test("Application fleet coverage does not fabricate a complete report")
    func fleetCoverageIsExplicit() {
        #expect(snapshot(expected: 2, reporting: 2).coverage == .complete)
        #expect(snapshot(expected: 2, reporting: 1).coverage == .partial)
        #expect(snapshot(expected: 0, reporting: 0).coverage == .noReports)
        #expect(snapshot(expected: 2, reporting: 0).coverage == .noReports)
    }

    private func snapshot(expected: UInt32, reporting: UInt32) -> ApplicationFleetSnapshot {
        ApplicationFleetSnapshot(
            capturedAt: nil,
            membersExpected: expected,
            membersReporting: reporting,
            applications: []
        )
    }
}
