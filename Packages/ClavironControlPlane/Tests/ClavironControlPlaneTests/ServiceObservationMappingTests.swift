import Testing
@testable import ClavironControlPlane

@Suite("Service observation mapping")
struct ServiceObservationMappingTests {
    @Test("Service command acknowledgements must match the requested service")
    func serviceCommandAcknowledgementIsValidated() throws {
        var response = Claviron_Services_ServiceCommandResponse()
        response.name = "http"
        response.accepted = true

        #expect(try DirectClavironClient.serviceReceipt(
            action: .restart(name: "http"),
            response: response
        ) == ServiceManagementReceipt(
            action: .restart(name: "http"),
            accepted: true,
            acknowledgedServiceName: "http"
        ))

        #expect(throws: ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "The service command targeted 'grpc', but the server acknowledged 'http'."
        )) {
            try DirectClavironClient.serviceReceipt(
                action: .restart(name: "grpc"),
                response: response
            )
        }
    }

    @Test("Raw placement facts and optional presence are preserved")
    func placementFactsArePreserved() throws {
        var member = Claviron_Services_ServiceMember()
        member.nodeID = 17
        member.role = .UNRECOGNIZED(91)

        var placement = Claviron_Services_ServicePlacement()
        placement.member = member
        placement.lifecycle = .failed
        placement.reloadable = false
        placement.generation = 8
        placement.reloadRevision = 3
        placement.lastError = "boot failed"
        placement.lastErrorTruncated = true
        placement.startPolicy = .manual
        placement.dispatch = .pool
        placement.activeExecutions = 0

        var generated = Claviron_Services_ServiceStatus()
        generated.name = "HttpsServer"
        generated.placements = [placement]

        let service = DirectClavironClient.serviceObservation(generated)
        let observedPlacement = try #require(service.placements.first)

        #expect(service.name == "HttpsServer")
        #expect(observedPlacement.member == ServiceMemberObservation(
            nodeID: 17,
            role: .unrecognized(91)
        ))
        #expect(observedPlacement.lifecycle == .failed)
        #expect(!observedPlacement.reloadable)
        #expect(observedPlacement.generation == 8)
        #expect(observedPlacement.reloadRevision == 3)
        #expect(observedPlacement.lastError == "boot failed")
        #expect(observedPlacement.lastErrorTruncated)
        #expect(observedPlacement.lastReloadError == nil)
        #expect(!observedPlacement.lastReloadErrorTruncated)
        #expect(observedPlacement.observedAt == nil)
        #expect(observedPlacement.startPolicy == .manual)
        #expect(observedPlacement.dispatch == .pool)
        #expect(observedPlacement.activeExecutions == 0)

        placement.clearActiveExecutions()
        generated.placements = [placement]
        #expect(DirectClavironClient.serviceObservation(generated).placements[0].activeExecutions == nil)
    }

    @Test("Fleet coverage does not fabricate health from an empty report")
    func fleetCoverageIsExplicit() {
        #expect(snapshot(expected: 2, reporting: 2).coverage == .complete)
        #expect(snapshot(expected: 2, reporting: 1).coverage == .partial)
        #expect(snapshot(expected: 0, reporting: 0).coverage == .noReports)
        #expect(snapshot(expected: 2, reporting: 0).coverage == .noReports)
    }

    private func snapshot(
        expected: UInt32,
        reporting: UInt32
    ) -> ServiceFleetSnapshot {
        ServiceFleetSnapshot(
            capturedAt: nil,
            membersExpected: expected,
            membersReporting: reporting,
            services: []
        )
    }
}
