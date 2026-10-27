#if os(macOS)
import ClavironControlPlane
import Foundation
import Testing
@testable import Claviron

@MainActor
struct ConnectionCommandAvailabilityTests {
    private let snapshot = ServiceFleetSnapshot(
        capturedAt: Date(timeIntervalSince1970: 100),
        membersExpected: 1,
        membersReporting: 1,
        services: []
    )

    @Test
    func commandsFollowConnectionState() {
        let failure = ClavironClientFailure(
            kind: .unavailable,
            diagnosticDetail: "test transport unavailable"
        )

        #expect(ConnectionCommandAvailability(state: .disconnected) == .init(
            canConnect: true,
            canReconnect: false,
            canDisconnect: false
        ))
        #expect(ConnectionCommandAvailability(state: .connected(snapshot)) == .init(
            canConnect: false,
            canReconnect: true,
            canDisconnect: true
        ))
        #expect(ConnectionCommandAvailability(state: .connecting) == .init(
            canConnect: false,
            canReconnect: false,
            canDisconnect: false
        ))
        #expect(ConnectionCommandAvailability(state: .refreshing(snapshot)) == .init(
            canConnect: false,
            canReconnect: false,
            canDisconnect: false
        ))
        #expect(ConnectionCommandAvailability(
            state: .failed(failure, lastSnapshot: snapshot)
        ) == .init(
            canConnect: false,
            canReconnect: true,
            canDisconnect: true
        ))
    }
}
#endif
