import ClavironControlPlane
import SwiftUI
import Testing
@testable import Claviron

@MainActor
struct LinkedApplicationPresentationTests {
    private func runner(
        _ link: LinkReachabilityObservation,
        runtime: String = "php",
        lanes: UInt32 = 0
    ) -> LinkedApplicationObservation {
        LinkedApplicationObservation(
            id: LinkedApplicationIDObservation(fleetName: "octane", name: "octane-app", transport: "orbit"),
            runtime: runtime,
            link: link,
            connectedLanes: lanes,
            lanes: [],
            hosted: nil
        )
    }

    /// The edge observes the Link, not the runner's process: the row says
    /// whether the runner is reachable and through how many lanes, and a
    /// disconnected runner cannot be sent a command.
    @Test
    func theRowReportsTheLinkAndNothingElse() {
        let connected = LinkedApplicationPresentation(application: runner(.connected, lanes: 4))
        #expect(connected.status.title == "Connected · 4 lanes")
        #expect(connected.status.color == .green)
        #expect(connected.detail == "PHP · Orbit · octane")
        #expect(connected.canReceive)

        let disconnected = LinkedApplicationPresentation(application: runner(.disconnected))
        #expect(disconnected.status.title == "Disconnected")
        #expect(!disconnected.canReceive)
    }

    @Test
    func aRunnerThatNeverJoinedHasNoRuntimeTag() {
        let unseen = LinkedApplicationPresentation(application: runner(.disconnected, runtime: ""))
        #expect(unseen.detail == "Orbit · octane")
    }

    /// Rows of the native and linked lists were once matched by position, so
    /// linked runners were drawn with native rows' content. Identities come
    /// from the applications themselves and never collide across lists.
    @Test
    func rowIdentitiesDoNotCollideAcrossLists() {
        let native = ApplicationObservation(
            applicationID: ApplicationIDObservation(runtime: "php", name: "api"),
            placements: []
        )
        let shop = runner(.connected)
        let sameNameElsewhere = LinkedApplicationObservation(
            id: LinkedApplicationIDObservation(fleetName: "fastapi", name: "octane-app"),
            runtime: "asgi",
            link: .connected,
            connectedLanes: 1,
            lanes: [],
            hosted: nil
        )
        #expect(native.rowID != shop.rowID)
        #expect(shop.rowID != sameNameElsewhere.rowID)
    }
}
