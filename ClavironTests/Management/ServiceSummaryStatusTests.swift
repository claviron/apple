import ClavironControlPlane
import Testing
@testable import Claviron

struct ServiceSummaryStatusTests {
    @Test
    func emptyOrUnreportedPlacementsAreUnknown() {
        #expect(summary() == .unknown)
        #expect(summary(.unspecified, .unrecognized(42)) == .unknown)
    }

    @Test
    func uniformPlacementsKeepTheirLifecycle() {
        #expect(summary(.running, .running) == .controllerRunning)
        #expect(summary(.stopping, .stopping) == .stopping)
        #expect(summary(.stopped, .stopped) == .stopped)
        #expect(summary(.failed, .failed) == .failed)
    }

    @Test
    func partialFailureIsDegradedAndOtherDisagreementIsMixed() {
        #expect(summary(.running, .failed) == .degraded)
        #expect(summary(.running, .stopped) == .mixed)
        #expect(summary(.running, .unspecified) == .mixed)
    }

    @Test
    func listSummaryCountsExecutionsRatherThanControllers() {
        let service = ServiceObservation(name: "pool", placements: [
            servicePlacement(active: 3, dispatch: .pool),
            servicePlacement(active: 5, dispatch: .pool),
            servicePlacement(active: 0, dispatch: .pool),
        ])
        #expect(ServiceSummaryStatus.instanceSummary(service) == " · 8 instances")
        #expect(ServiceSummaryStatus.instanceSummary(ServiceObservation(
            name: "one", placements: [servicePlacement(active: 1, dispatch: .one)]
        )) == " · 1 instance")
        #expect(ServiceSummaryStatus.instanceSummary(ServiceObservation(
            name: "waiting", placements: [servicePlacement(active: 0, dispatch: .one)]
        )) == "")
        #expect(ServiceSummaryStatus.instanceSummary(ServiceObservation(
            name: "unreported", placements: []
        )) == "")
    }
}

@Test
func dispatchedExecutionIsIndependentOfControllerLifecycle() {
    for dispatch in [ServiceDispatchObservation.one, .pool] {
        let owner = servicePlacement(active: 1, dispatch: dispatch)
        let waiter = servicePlacement(active: 0, dispatch: dispatch)
        #expect(ServiceSummaryStatus(placement: owner) == .running)
        #expect(ServiceSummaryStatus(placement: waiter) == .waiting)
        #expect(ServiceSummaryStatus(service: ServiceObservation(
            name: "dns", placements: [owner, waiter]
        )) == .running)
    }
}

private func servicePlacement(active: UInt64, dispatch: ServiceDispatchObservation) -> ServicePlacementObservation {
    ServicePlacementObservation(
        member: nil, lifecycle: .running, reloadable: false, generation: 1,
        reloadRevision: 0, lastError: nil, lastErrorTruncated: false,
        lastReloadError: nil, lastReloadErrorTruncated: false, observedAt: nil,
        startPolicy: .automatic, activeExecutions: active, dispatch: dispatch
    )
}

private func summary(
    _ lifecycles: ServiceLifecycleObservation...
) -> ServiceSummaryStatus {
    ServiceSummaryStatus(
        service: ServiceObservation(
            name: "http",
            placements: lifecycles.enumerated().map { offset, lifecycle in
                ServicePlacementObservation(
                    member: ServiceMemberObservation(
                        nodeID: UInt32(offset + 1),
                        role: .worker
                    ),
                    lifecycle: lifecycle,
                    reloadable: true,
                    generation: 1,
                    reloadRevision: 1,
                    lastError: nil,
                    lastErrorTruncated: false,
                    lastReloadError: nil,
                    lastReloadErrorTruncated: false,
                    observedAt: nil,
                    startPolicy: .automatic
                )
            }
        )
    )
}
