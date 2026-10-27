import ClavironControlPlane
import Foundation
import Testing
@testable import Claviron

@MainActor
struct ApplicationActionModelTests {
    @Test
    func restartRequiresEveryApplicationGenerationToAdvance() {
        let id = ApplicationIDObservation(runtime: "php", name: "storefront")
        let baseline = snapshot(application: application(
            id: id,
            placements: [
                placement(nodeID: 1, lifecycle: .running, enabled: true, generation: 3),
                placement(nodeID: 2, lifecycle: .running, enabled: true, generation: 7),
            ]
        ), members: 2)
        let action = ApplicationManagementAction.restart(id: id)
        let receipt = ApplicationManagementReceipt(
            action: action,
            accepted: true,
            acknowledgedApplicationID: id
        )
        let context = ApplicationActionContext(receipt: receipt, baseline: baseline)
        let partial = snapshot(application: application(
            id: id,
            placements: [
                placement(nodeID: 1, lifecycle: .running, enabled: true, generation: 4),
                placement(nodeID: 2, lifecycle: .running, enabled: true, generation: 7),
            ]
        ), members: 2)
        let complete = snapshot(application: application(
            id: id,
            placements: [
                placement(nodeID: 1, lifecycle: .running, enabled: true, generation: 4),
                placement(nodeID: 2, lifecycle: .running, enabled: true, generation: 8),
            ]
        ), members: 2)

        #expect(ApplicationActionModel.assess(context: context, observation: partial) == .notYetObserved)
        #expect(ApplicationActionModel.assess(context: context, observation: complete) == .completed)
    }

    @Test
    func acceptedStopUsesTheClientAndWaitsForEveryPlacement() async {
        let id = ApplicationIDObservation(runtime: "php", name: "storefront")
        let baseline = snapshot(application: application(
            id: id,
            placements: [placement(
                nodeID: 1,
                lifecycle: .running,
                enabled: true,
                generation: 2
            )]
        ))
        let stopped = snapshot(application: application(
            id: id,
            placements: [placement(
                nodeID: 1,
                lifecycle: .stopped,
                enabled: false,
                generation: 2
            )]
        ))
        let action = ApplicationManagementAction.stop(id: id)
        let receipt = ApplicationManagementReceipt(
            action: action,
            accepted: true,
            acknowledgedApplicationID: id
        )
        let applicationModel = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let client = MockClavironClient(
            results: [.success(.preview)],
            applicationResults: [.success(stopped)],
            applicationActionResults: [.success(receipt)]
        )
        let connectionModel = ConnectionModel(applicationModel: applicationModel) { _ in client }
        let serverID = TestConfiguration.primaryServerID
        await connectionModel.connect(to: serverID)
        let model = ApplicationActionModel(serverID: serverID, connectionModel: connectionModel)

        await model.perform(action, baseline: baseline)

        #expect(model.state == .succeeded(
            response: ApplicationActionContext(receipt: receipt, baseline: baseline),
            observation: stopped
        ))
        #expect(await client.applicationActions == [action])
    }
}

private func snapshot(
    application: ApplicationObservation,
    members: UInt32 = 1
) -> ApplicationFleetSnapshot {
    ApplicationFleetSnapshot(
        capturedAt: Date(timeIntervalSince1970: 100),
        membersExpected: members,
        membersReporting: members,
        applications: [application]
    )
}

private func application(
    id: ApplicationIDObservation,
    placements: [ApplicationPlacementObservation]
) -> ApplicationObservation {
    ApplicationObservation(applicationID: id, placements: placements)
}

private func placement(
    nodeID: UInt32,
    lifecycle: ApplicationLifecycleObservation,
    enabled: Bool,
    generation: UInt64
) -> ApplicationPlacementObservation {
    ApplicationPlacementObservation(
        member: ApplicationMemberObservation(nodeID: nodeID, role: .worker),
        lifecycle: lifecycle,
        enabled: enabled,
        generation: generation,
        pool: nil,
        lastError: nil,
        lastErrorTruncated: false,
        observedAt: Date(timeIntervalSince1970: 100)
    )
}
