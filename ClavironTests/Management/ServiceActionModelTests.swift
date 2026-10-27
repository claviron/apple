import ClavironControlPlane
import Testing
@testable import Claviron

@MainActor
struct ServiceActionModelTests {
    @Test
    func startRequiresAStoppedPlacementToReachANewerRunningGeneration() {
        let baseline = serviceSnapshot(placements: [
            placement(nodeID: 1, lifecycle: .stopped, generation: 3),
        ])
        let action = ServiceManagementAction.start(name: "http")
        let context = ServiceActionContext(
            receipt: serviceReceipt(action),
            baseline: baseline
        )

        #expect(ServiceActionModel.assess(
            context: context,
            observation: serviceSnapshot(placements: [
                placement(nodeID: 1, lifecycle: .running, generation: 3),
            ])
        ) == .notYetObserved)
        #expect(ServiceActionModel.assess(
            context: context,
            observation: serviceSnapshot(placements: [
                placement(nodeID: 1, lifecycle: .running, generation: 4),
            ])
        ) == .completed)
    }

    @Test
    func reloadRequiresEveryRevisionAndSurfacesTheLatestReloadError() {
        let baseline = serviceSnapshot(placements: [
            placement(nodeID: 1, reloadRevision: 2),
            placement(nodeID: 2, role: .worker, reloadRevision: 5),
        ])
        let action = ServiceManagementAction.reload(name: "http")
        let context = ServiceActionContext(
            receipt: serviceReceipt(action),
            baseline: baseline
        )

        #expect(ServiceActionModel.assess(
            context: context,
            observation: serviceSnapshot(placements: [
                placement(nodeID: 1, reloadRevision: 3),
                placement(nodeID: 2, role: .worker, reloadRevision: 5),
            ])
        ) == .notYetObserved)
        #expect(ServiceActionModel.assess(
            context: context,
            observation: serviceSnapshot(placements: [
                placement(nodeID: 1, reloadRevision: 3),
                placement(
                    nodeID: 2,
                    role: .worker,
                    reloadRevision: 6,
                    lastReloadError: "reload hook failed"
                ),
            ])
        ) == .failed(ClavironClientFailure(
            kind: .operationFailed,
            diagnosticDetail: "Service 'http' failed to reload on worker:2: reload hook failed"
        )))
    }

    @Test
    func restartAcceptsANewerGenerationThatCompletedCleanly() {
        let baseline = serviceSnapshot(placements: [
            placement(nodeID: 0, lifecycle: .stopped, generation: 3),
            placement(nodeID: 1, role: .worker, generation: 6),
        ])
        let action = ServiceManagementAction.restart(name: "http")
        let context = ServiceActionContext(
            receipt: serviceReceipt(action),
            baseline: baseline
        )

        #expect(ServiceActionModel.assess(
            context: context,
            observation: serviceSnapshot(placements: [
                placement(nodeID: 0, lifecycle: .stopped, generation: 4),
                placement(nodeID: 1, role: .worker, generation: 7),
            ])
        ) == .completed)
    }

    @Test
    func actionStoresRetainIndependentModelsForEachService() {
        final class Marker {}

        let store = ManagementResourceActionStore<String, Marker> {
            Marker()
        }
        let watchdog = store.value(for: "watchdog")

        #expect(store.value(for: "watchdog") === watchdog)
        #expect(store.value(for: "http") !== watchdog)
        #expect(store.values.count == 2)
    }

    @Test
    func incompleteOrAmbiguousPlacementStateCannotSubmitAnAction() {
        let duplicate = ServiceObservation(
            name: "http",
            placements: [
                placement(nodeID: 1),
                placement(nodeID: 1),
            ]
        )
        let partial = ServiceFleetSnapshot(
            capturedAt: nil,
            membersExpected: 2,
            membersReporting: 1,
            services: [duplicate]
        )

        #expect(!ServiceActionModel.canSubmit(
            action: .restart(name: "http"),
            service: duplicate,
            snapshot: partial
        ))
    }

    @Test
    func everyServiceActionUsesTheDirectClientAndCanReachObservedSuccess() async {
        for testCase in serviceActionCases {
            let client = MockClavironClient(
                results: [
                    .success(testCase.baseline),
                    .success(testCase.observation),
                ],
                serviceActionResults: [.success(testCase.receipt)]
            )
            let applicationModel = ApplicationModel.preview(
                configuration: TestConfiguration.valid
            )
            let connectionModel = ConnectionModel(applicationModel: applicationModel) { _ in
                client
            }
            let model = ServiceActionModel(
                serverID: TestConfiguration.primaryServerID,
                connectionModel: connectionModel
            )

            await model.perform(testCase.action, baseline: testCase.baseline)

            guard case .succeeded = model.state else {
                Issue.record("\(testCase.action) did not reach observed success")
                continue
            }
            #expect(await client.serviceActions == [testCase.action])
            #expect(await client.serviceStatusNames == [testCase.action.serviceName])
            #expect(await client.requestCount == 2)
        }
    }

    @Test
    func everyServiceActionPreservesItsSubmissionFailureWithoutRefreshing() async {
        let failure = ClavironClientFailure(
            kind: .serverRejected,
            diagnosticDetail: "service action rejected"
        )

        for testCase in serviceActionCases {
            let client = MockClavironClient(
                results: [.success(testCase.baseline)],
                serviceActionResults: [.failure(failure)]
            )
            let applicationModel = ApplicationModel.preview(
                configuration: TestConfiguration.valid
            )
            let connectionModel = ConnectionModel(applicationModel: applicationModel) { _ in
                client
            }
            let model = ServiceActionModel(
                serverID: TestConfiguration.primaryServerID,
                connectionModel: connectionModel
            )

            await model.perform(testCase.action, baseline: testCase.baseline)

            #expect(model.state == .failed(failure, acceptedResponse: nil))
            #expect(await client.serviceActions == [testCase.action])
            #expect(await client.requestCount == 1)
        }
    }
}

private struct ServiceActionCase {
    let action: ServiceManagementAction
    let receipt: ServiceManagementReceipt
    let baseline: ServiceFleetSnapshot
    let observation: ServiceFleetSnapshot
}

private let serviceActionCases: [ServiceActionCase] = {
    let baseline = serviceSnapshot(placements: [
        placement(nodeID: 1, generation: 4, reloadRevision: 2),
        placement(nodeID: 2, role: .worker, generation: 7, reloadRevision: 5),
    ])
    return [
        ServiceActionCase(
            action: .start(name: "http"),
            receipt: serviceReceipt(.start(name: "http")),
            baseline: baseline,
            observation: baseline
        ),
        ServiceActionCase(
            action: .stop(name: "http"),
            receipt: serviceReceipt(.stop(name: "http")),
            baseline: baseline,
            observation: serviceSnapshot(placements: [
                placement(nodeID: 1, lifecycle: .stopped, generation: 4),
                placement(nodeID: 2, role: .worker, lifecycle: .stopped, generation: 7),
            ])
        ),
        ServiceActionCase(
            action: .reload(name: "http"),
            receipt: serviceReceipt(.reload(name: "http")),
            baseline: baseline,
            observation: serviceSnapshot(placements: [
                placement(nodeID: 1, generation: 4, reloadRevision: 3),
                placement(nodeID: 2, role: .worker, generation: 7, reloadRevision: 6),
            ])
        ),
        ServiceActionCase(
            action: .restart(name: "http"),
            receipt: serviceReceipt(.restart(name: "http")),
            baseline: baseline,
            observation: serviceSnapshot(placements: [
                placement(nodeID: 1, generation: 5, reloadRevision: 2),
                placement(nodeID: 2, role: .worker, generation: 8, reloadRevision: 5),
            ])
        ),
    ]
}()

private func serviceReceipt(
    _ action: ServiceManagementAction
) -> ServiceManagementReceipt {
    ServiceManagementReceipt(
        action: action,
        accepted: true,
        acknowledgedServiceName: action.serviceName
    )
}

private func serviceSnapshot(
    placements: [ServicePlacementObservation]
) -> ServiceFleetSnapshot {
    ServiceFleetSnapshot(
        capturedAt: nil,
        membersExpected: 2,
        membersReporting: 2,
        services: [ServiceObservation(name: "http", placements: placements)]
    )
}

private func placement(
    nodeID: UInt32,
    role: ServiceMemberRoleObservation = .master,
    lifecycle: ServiceLifecycleObservation = .running,
    reloadable: Bool = true,
    generation: UInt64 = 1,
    reloadRevision: UInt64 = 1,
    lastError: String? = nil,
    lastReloadError: String? = nil,
    startPolicy: ServiceStartPolicyObservation = .automatic
) -> ServicePlacementObservation {
    ServicePlacementObservation(
        member: ServiceMemberObservation(nodeID: nodeID, role: role),
        lifecycle: lifecycle,
        reloadable: reloadable,
        generation: generation,
        reloadRevision: reloadRevision,
        lastError: lastError,
        lastErrorTruncated: false,
        lastReloadError: lastReloadError,
        lastReloadErrorTruncated: false,
        observedAt: nil,
        startPolicy: startPolicy
    )
}
