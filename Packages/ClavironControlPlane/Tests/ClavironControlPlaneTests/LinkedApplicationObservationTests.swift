import Foundation
import Testing
@testable import ClavironControlPlane

struct LinkedApplicationObservationTests {
    /// A runner that has not reported what it hosts has no hosted snapshot:
    /// absent stays absent rather than reading as an empty or stopped list,
    /// and a lane's missing pid is not a zero.
    @Test
    func anUnreportedRunnerHasNoHostedSnapshot() {
        var message = Claviron_LinkedApplications_LinkedApplicationStatus()
        message.info.id.fleetName = "octane"
        message.info.id.name = "octane-app"
        message.info.id.transport = "orbit"
        message.info.runtime = "php"
        message.link = .connected
        message.connectedLanes = 1
        var lane = Claviron_LinkedApplications_LinkedApplicationLane()
        lane.lane = 4
        lane.incarnation = 2
        message.lanes = [lane]

        let observation = LinkedApplicationObservation(message)
        #expect(observation.id == LinkedApplicationIDObservation(fleetName: "octane", name: "octane-app", transport: "orbit"))
        #expect(observation.transport == "orbit")
        #expect(observation.runtime == "php")
        #expect(observation.link == .connected)
        #expect(observation.hosted == nil)
        #expect(observation.lanes == [LinkedLaneObservation(lane: 4, pid: nil, incarnation: 2)])
    }

    @Test
    func aReportedRunnerCarriesItsApplications() {
        var message = Claviron_LinkedApplications_LinkedApplicationStatus()
        message.link = .disconnected
        message.hosted.membersExpected = 1
        message.hosted.membersReporting = 1
        var application = Claviron_Applications_ApplicationStatus()
        application.id.runtime = "php"
        application.id.name = "shop"
        message.hosted.applications = [application]

        let observation = LinkedApplicationObservation(message)
        #expect(observation.link == .disconnected)
        #expect(observation.hosted?.applications.first?.applicationID
            == ApplicationIDObservation(runtime: "php", name: "shop"))
    }
}
