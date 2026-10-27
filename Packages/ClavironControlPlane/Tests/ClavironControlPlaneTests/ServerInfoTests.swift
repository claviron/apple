import Foundation
import Testing
@testable import ClavironControlPlane

struct ServerInfoTests {
    @Test
    func missingObservationsAreNotZerosOrWorkerClocks() {
        var message = Claviron_Server_InfoResponse()
        message.respondingProcess.runMode = .worker
        message.respondingProcess.workerID = 2
        message.respondingProcess.uptime.seconds = 15
        let snapshot = ServerInfoSnapshot(message)
        #expect(snapshot.workersDesired == nil)
        #expect(snapshot.workersRunning == nil)
        #expect(snapshot.startedAt == nil)
        #expect(snapshot.uptime == nil)
        #expect(snapshot.reloadRevision == nil)
        #expect(snapshot.respondingProcess?.runMode == .worker)
        #expect(snapshot.respondingProcess?.workerID == 2)
        #expect(snapshot.respondingProcess?.uptime?.seconds == 15)
    }

    @Test
    func explicitStandaloneZerosAndVersionsSurviveMapping() {
        var message = Claviron_Server_InfoResponse()
        message.name = "example"
        message.environment = "production"
        message.fleetName = "exm"
        message.clavironVersion = "1.0"
        message.applicationVersion = "2.0"
        message.workersDesired = 0
        message.workersRunning = 0
        message.reloadRevision = 0
        message.respondingProcess.runMode = .standalone
        message.capabilities = ["server", "services"]
        let snapshot = ServerInfoSnapshot(message)
        #expect(snapshot.workersDesired == 0)
        #expect(snapshot.workersRunning == 0)
        #expect(snapshot.reloadRevision == 0)
        #expect(snapshot.fleetName == "exm")
        #expect(snapshot.applicationVersion == "2.0")
        #expect(snapshot.clavironVersion == "1.0")
        #expect(snapshot.respondingProcess?.workerID == nil)
        #expect(snapshot.capabilities == ["server", "services"])
    }

    @Test
    func futureRolesRemainVisibleAndProcessMayBeAbsent() {
        var message = Claviron_Server_InfoResponse()
        #expect(ServerInfoSnapshot(message).respondingProcess == nil)
        message.respondingProcess.runMode = .UNRECOGNIZED(99)
        #expect(ServerInfoSnapshot(message).respondingProcess?.runMode == .unrecognized(99))
    }
}
