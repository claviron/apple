import ClavironControlPlane
import Testing
@testable import Claviron

@MainActor
struct WorkerActionModelTests {
    @Test
    func acceptedReloadSucceedsOnlyAfterItsRevisionAdvances() async {
        let baseline = snapshot(workerCount: 2, workers: [
            worker(1, reloadRevision: 3, incarnation: 4),
            worker(2, reloadRevision: 7, incarnation: 8),
        ])
        let action = WorkerManagementAction.reload(workerID: 1)
        let context = WorkerActionContext(
            receipt: receipt(action, workerID: 1),
            baseline: baseline
        )

        #expect(WorkerActionModel.assess(
            context: context,
            observation: baseline
        ) == .notYetObserved)
        #expect(WorkerActionModel.assess(
            context: context,
            observation: snapshot(workerCount: 2, workers: [
                worker(1, reloadRevision: 4, incarnation: 4),
                worker(2, reloadRevision: 7, incarnation: 8),
            ])
        ) == .completed)

        let duplicateMembership = snapshot(workerCount: 2, workers: [
            worker(1, reloadRevision: 4, incarnation: 4),
            worker(1, reloadRevision: 4, incarnation: 4),
        ])
        #expect(WorkerActionModel.assess(
            context: context,
            observation: duplicateMembership
        ) == .notYetObserved)
    }

    @Test
    func startStopAndRestartRequireTheirAuthoritativeEndState() {
        let baseline = snapshot(workerCount: 2, workers: [
            worker(1, lifecycle: .stopped, incarnation: 2),
            worker(2, incarnation: 5),
        ])
        let started = snapshot(workerCount: 2, workers: [
            worker(1, incarnation: 3),
            worker(2, incarnation: 5),
        ])
        let start = WorkerManagementAction.start(workerID: 1)
        #expect(WorkerActionModel.assess(
            context: WorkerActionContext(
                receipt: receipt(start, workerID: 1),
                baseline: baseline
            ),
            observation: started
        ) == .completed)

        // A stopped slot that still names a process is a contradiction in the
        // master's own protocol, not a stop that has yet to finish.
        let stop = WorkerManagementAction.stop(workerID: 2)
        let stoppedWithPID = snapshot(workerCount: 2, workers: [
            worker(1, incarnation: 3),
            WorkerObservation(
                workerID: 2,
                lifecycle: .stopped,
                ownership: .unowned,
                process: ProcessIdentityObservation(pid: 202, startedAt: 2_005),
                uptime: nil,
                recoveryAttempts: 0,
                reloadRevision: 1,
                incarnation: 5
            ),
        ])
        #expect(WorkerActionModel.assess(
            context: WorkerActionContext(
                receipt: receipt(stop, workerID: 2),
                baseline: started
            ),
            observation: stoppedWithPID
        ) == .failed(ClavironClientFailure(
            kind: .operationFailed,
            diagnosticDetail: "Worker 2 is stopped but still reports PID 202."
        )))

        let stopped = snapshot(workerCount: 2, workers: [
            worker(1, incarnation: 3),
            worker(2, lifecycle: .stopped, incarnation: 5),
        ])
        #expect(WorkerActionModel.assess(
            context: WorkerActionContext(
                receipt: receipt(stop, workerID: 2),
                baseline: started
            ),
            observation: stopped
        ) == .completed)

        let restart = WorkerManagementAction.restart(workerID: 2)
        #expect(WorkerActionModel.assess(
            context: WorkerActionContext(
                receipt: receipt(restart, workerID: 2),
                baseline: started
            ),
            observation: snapshot(workerCount: 2, workers: [
                worker(1, incarnation: 3),
                worker(2, incarnation: 6),
            ])
        ) == .completed)
    }

    /// The rules claviron-client applies: a running worker proves a
    /// completion only under the master's ownership. Reload accepts an
    /// adopted process; restart expects one this master spawned; a running
    /// slot nobody owns is a failure, not a wait.
    @Test
    func runningCompletionsRequireSupervisorOwnership() {
        let baseline = snapshot(workerCount: 2, workers: [
            worker(1, ownership: .adopted, reloadRevision: 3, incarnation: 4),
            worker(2, reloadRevision: 7, incarnation: 8),
        ])

        let reload = WorkerManagementAction.reload(workerID: 1)
        #expect(WorkerActionModel.assess(
            context: WorkerActionContext(
                receipt: receipt(reload, workerID: 1),
                baseline: baseline
            ),
            observation: snapshot(workerCount: 2, workers: [
                worker(1, ownership: .adopted, reloadRevision: 4, incarnation: 4),
                worker(2, reloadRevision: 7, incarnation: 8),
            ])
        ) == .completed)

        let restart = WorkerManagementAction.restart(workerID: 1)
        #expect(WorkerActionModel.assess(
            context: WorkerActionContext(
                receipt: receipt(restart, workerID: 1),
                baseline: baseline
            ),
            observation: snapshot(workerCount: 2, workers: [
                worker(1, ownership: .adopted, reloadRevision: 3, incarnation: 5),
                worker(2, reloadRevision: 7, incarnation: 8),
            ])
        ) == .failed(ClavironClientFailure(
            kind: .operationFailed,
            diagnosticDetail: "Worker 1 is adopted rather than spawned by the current master."
        )))
        #expect(WorkerActionModel.assess(
            context: WorkerActionContext(
                receipt: receipt(restart, workerID: 1),
                baseline: baseline
            ),
            observation: snapshot(workerCount: 2, workers: [
                worker(1, reloadRevision: 3, incarnation: 5),
                worker(2, reloadRevision: 7, incarnation: 8),
            ])
        ) == .completed)

        #expect(WorkerActionModel.assess(
            context: WorkerActionContext(
                receipt: receipt(reload, workerID: 1),
                baseline: baseline
            ),
            observation: snapshot(workerCount: 2, workers: [
                worker(1, ownership: .unowned, reloadRevision: 4, incarnation: 4),
                worker(2, reloadRevision: 7, incarnation: 8),
            ])
        ) == .failed(ClavironClientFailure(
            kind: .operationFailed,
            diagnosticDetail: "Worker 1 is running without supervisor process ownership."
        )))
    }

    @Test
    func aCrashAfterAcceptanceIsAnObservedOperationFailure() {
        let baseline = snapshot(workerCount: 2, workers: [
            worker(1, incarnation: 3),
            worker(2, incarnation: 5),
        ])
        let action = WorkerManagementAction.restart(workerID: 1)

        #expect(WorkerActionModel.assess(
            context: WorkerActionContext(
                receipt: receipt(action, workerID: 1),
                baseline: baseline
            ),
            observation: snapshot(workerCount: 2, workers: [
                worker(1, lifecycle: .crashed, incarnation: 4),
                worker(2, incarnation: 5),
            ])
        ) == .failed(ClavironClientFailure(
            kind: .operationFailed,
            diagnosticDetail: "Worker 1 crashed while waiting for restart completion."
        )))
    }

    @Test
    func fleetActionsRequireEveryInitiallyRunningWorkerToAdvance() {
        let baseline = snapshot(workerCount: 3, workers: [
            worker(1, reloadRevision: 2, incarnation: 3),
            worker(2, lifecycle: .stopped, reloadRevision: 4, incarnation: 5),
            worker(3, reloadRevision: 6, incarnation: 7),
        ])
        let reloaded = snapshot(workerCount: 3, workers: [
            worker(1, reloadRevision: 3, incarnation: 3),
            worker(2, lifecycle: .stopped, reloadRevision: 4, incarnation: 5),
            worker(3, reloadRevision: 7, incarnation: 7),
        ])
        #expect(WorkerActionModel.assess(
            context: WorkerActionContext(
                receipt: WorkerManagementReceipt(action: .reloadAll, accepted: true),
                baseline: baseline
            ),
            observation: reloaded
        ) == .completed)

        let onlyOneRestarted = snapshot(workerCount: 3, workers: [
            worker(1, reloadRevision: 2, incarnation: 4),
            worker(2, lifecycle: .stopped, reloadRevision: 4, incarnation: 5),
            worker(3, reloadRevision: 6, incarnation: 7),
        ])
        #expect(WorkerActionModel.assess(
            context: WorkerActionContext(
                receipt: WorkerManagementReceipt(action: .restartAll, accepted: true),
                baseline: baseline
            ),
            observation: onlyOneRestarted
        ) == .notYetObserved)
    }

    @Test
    func growthRequiresReceiptCountMembershipAndIncarnationConvergence() {
        let baseline = snapshot(workerCount: 2, workers: [
            worker(1, incarnation: 4),
            worker(2, incarnation: 8),
        ])
        let action = WorkerManagementAction.add
        let context = WorkerActionContext(
            receipt: WorkerManagementReceipt(
                action: action,
                accepted: true,
                previousWorkerCount: 2,
                targetWorkerCount: 3
            ),
            baseline: baseline
        )
        let converged = snapshot(workerCount: 3, workers: [
            worker(1, incarnation: 5),
            worker(2, incarnation: 9),
            worker(3, incarnation: 1),
        ])

        #expect(WorkerActionModel.assess(
            context: context,
            observation: converged
        ) == .completed)
        #expect(WorkerActionModel.assess(
            context: context,
            observation: snapshot(workerCount: 3, workers: Array(converged.workers.dropLast()))
        ) == .notYetObserved)
        // Growth rolls the retained workers; until they carry new incarnations
        // the fleet has not converged.
        #expect(WorkerActionModel.assess(
            context: context,
            observation: snapshot(workerCount: 3, workers: [
                worker(1, incarnation: 4),
                worker(2, incarnation: 8),
                worker(3, incarnation: 1),
            ])
        ) == .notYetObserved)
    }

    /// Shrink drains only the removed slot. A retained worker that shows a new
    /// incarnation was rolled by a shrink that must not touch it.
    @Test
    func shrinkKeepsEveryRetainedWorker() {
        let baseline = snapshot(workerCount: 3, workers: [
            worker(1, incarnation: 3),
            worker(2, ownership: .adopted, incarnation: 7),
            worker(3, incarnation: 9),
        ])
        let context = WorkerActionContext(
            receipt: WorkerManagementReceipt(
                action: .remove,
                accepted: true,
                previousWorkerCount: 3,
                targetWorkerCount: 2
            ),
            baseline: baseline
        )

        #expect(WorkerActionModel.assess(
            context: context,
            observation: snapshot(workerCount: 2, workers: [
                worker(1, incarnation: 3),
                worker(2, ownership: .adopted, incarnation: 7),
            ])
        ) == .completed)
        #expect(WorkerActionModel.assess(
            context: context,
            observation: snapshot(workerCount: 2, workers: [
                worker(1, incarnation: 4),
                worker(2, ownership: .adopted, incarnation: 7),
            ])
        ) == .failed(ClavironClientFailure(
            kind: .operationFailed,
            diagnosticDetail: "Worker 1 was replaced during fleet shrink: expected incarnation 3, observed 4."
        )))
    }

    @Test
    func actionPipelineUsesTheDirectClientAndRefreshesTheWorkerSnapshot() async {
        let baseline = snapshot(workerCount: 2, workers: [
            worker(1, reloadRevision: 3),
            worker(2, reloadRevision: 4),
        ])
        let observed = snapshot(workerCount: 2, workers: [
            worker(1, reloadRevision: 4),
            worker(2, reloadRevision: 4),
        ])
        let action = WorkerManagementAction.reload(workerID: 1)
        let actionReceipt = receipt(action, workerID: 1)
        let client = MockClavironClient(
            results: [.success(.preview)],
            workerResults: [.success(observed)],
            workerActionResults: [.success(actionReceipt)]
        )
        let applicationModel = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let connectionModel = ConnectionModel(applicationModel: applicationModel) { _ in client }
        let model = WorkerActionModel(
            serverID: TestConfiguration.primaryServerID,
            connectionModel: connectionModel
        )

        await model.perform(action, baseline: baseline)

        #expect(model.state == .succeeded(
            response: WorkerActionContext(receipt: actionReceipt, baseline: baseline),
            observation: observed
        ))
        #expect(await client.workerActions == [action])
        #expect(await client.workerRequestCount == 1)
        #expect(connectionModel.workerObservationState(
            for: TestConfiguration.primaryServerID
        ) == .loaded(observed))
    }

    @Test
    func everyWorkerActionUsesTheDirectClientAndCanReachObservedSuccess() async {
        for testCase in actionCases {
            let client = MockClavironClient(
                results: [.success(.preview)],
                workerResults: [.success(testCase.observation)],
                workerActionResults: [.success(testCase.receipt)]
            )
            let applicationModel = ApplicationModel.preview(
                configuration: TestConfiguration.valid
            )
            let connectionModel = ConnectionModel(applicationModel: applicationModel) { _ in
                client
            }
            let model = WorkerActionModel(
                serverID: TestConfiguration.primaryServerID,
                connectionModel: connectionModel
            )

            await model.perform(testCase.action, baseline: testCase.baseline)

            guard case .succeeded = model.state else {
                Issue.record("\(testCase.action) did not reach observed success: \(model.state)")
                continue
            }
            #expect(await client.workerActions == [testCase.action])
            #expect(await client.workerRequestCount == 1)
        }
    }

    @Test
    func everyWorkerActionPreservesItsSubmissionFailureWithoutRefreshing() async {
        let failure = ClavironClientFailure(
            kind: .serverRejected,
            diagnosticDetail: "worker action rejected"
        )

        for testCase in actionCases {
            let client = MockClavironClient(
                results: [.success(.preview)],
                workerActionResults: [.failure(failure)]
            )
            let applicationModel = ApplicationModel.preview(
                configuration: TestConfiguration.valid
            )
            let connectionModel = ConnectionModel(applicationModel: applicationModel) { _ in
                client
            }
            let model = WorkerActionModel(
                serverID: TestConfiguration.primaryServerID,
                connectionModel: connectionModel
            )

            await model.perform(testCase.action, baseline: testCase.baseline)

            #expect(model.state == .failed(failure, acceptedResponse: nil))
            #expect(await client.workerActions == [testCase.action])
            #expect(await client.workerRequestCount == 0)
        }
    }

    @Test
    func workerCommandResultNamesTheAffectedWorker() {
        let added = WorkerManagementReceipt(
            action: .add,
            accepted: true,
            previousWorkerCount: 2,
            targetWorkerCount: 3
        )
        let removed = WorkerManagementReceipt(
            action: .remove,
            accepted: true,
            previousWorkerCount: 3,
            targetWorkerCount: 2
        )

        #expect(WorkerActionStatusView.progressLabel(
            for: .add,
            receipt: added
        ) == "Adding Worker 3…")
        #expect(WorkerActionStatusView.successLabel(
            for: added
        ) == "Worker 3 added successfully.")
        #expect(WorkerActionStatusView.progressLabel(
            for: .remove,
            receipt: removed
        ) == "Removing Worker 3…")
        #expect(WorkerActionStatusView.successLabel(
            for: removed
        ) == "Worker 3 removed successfully.")
        #expect(WorkerActionStatusView.successLabel(
            for: receipt(.restart(workerID: 2), workerID: 2)
        ) == "Worker 2 restarted successfully.")
    }
}

private struct WorkerActionCase {
    let action: WorkerManagementAction
    let receipt: WorkerManagementReceipt
    let baseline: WorkerFleetSnapshot
    let observation: WorkerFleetSnapshot
}

private let actionCases: [WorkerActionCase] = {
    let runningTwo = snapshot(workerCount: 2, workers: [
        worker(1, reloadRevision: 2, incarnation: 3),
        worker(2, reloadRevision: 5, incarnation: 7),
    ])
    return [
        WorkerActionCase(
            action: .start(workerID: 1),
            receipt: receipt(.start(workerID: 1), workerID: 1),
            baseline: snapshot(workerCount: 2, workers: [
                worker(1, lifecycle: .stopped, incarnation: 2),
                worker(2, incarnation: 7),
            ]),
            observation: runningTwo
        ),
        WorkerActionCase(
            action: .stop(workerID: 1),
            receipt: receipt(.stop(workerID: 1), workerID: 1),
            baseline: runningTwo,
            observation: snapshot(workerCount: 2, workers: [
                worker(1, lifecycle: .stopped, reloadRevision: 2, incarnation: 3),
                worker(2, reloadRevision: 5, incarnation: 7),
            ])
        ),
        WorkerActionCase(
            action: .reload(workerID: 1),
            receipt: receipt(.reload(workerID: 1), workerID: 1),
            baseline: runningTwo,
            observation: snapshot(workerCount: 2, workers: [
                worker(1, reloadRevision: 3, incarnation: 3),
                worker(2, reloadRevision: 5, incarnation: 7),
            ])
        ),
        WorkerActionCase(
            action: .restart(workerID: 1),
            receipt: receipt(.restart(workerID: 1), workerID: 1),
            baseline: runningTwo,
            observation: snapshot(workerCount: 2, workers: [
                worker(1, reloadRevision: 2, incarnation: 4),
                worker(2, reloadRevision: 5, incarnation: 7),
            ])
        ),
        WorkerActionCase(
            action: .reloadAll,
            receipt: WorkerManagementReceipt(action: .reloadAll, accepted: true),
            baseline: runningTwo,
            observation: snapshot(workerCount: 2, workers: [
                worker(1, reloadRevision: 3, incarnation: 3),
                worker(2, reloadRevision: 6, incarnation: 7),
            ])
        ),
        WorkerActionCase(
            action: .restartAll,
            receipt: WorkerManagementReceipt(action: .restartAll, accepted: true),
            baseline: runningTwo,
            observation: snapshot(workerCount: 2, workers: [
                worker(1, reloadRevision: 2, incarnation: 4),
                worker(2, reloadRevision: 5, incarnation: 8),
            ])
        ),
        WorkerActionCase(
            action: .add,
            receipt: WorkerManagementReceipt(
                action: .add,
                accepted: true,
                previousWorkerCount: 2,
                targetWorkerCount: 3
            ),
            baseline: runningTwo,
            observation: snapshot(workerCount: 3, workers: [
                worker(1, reloadRevision: 2, incarnation: 4),
                worker(2, reloadRevision: 5, incarnation: 8),
                worker(3, incarnation: 1),
            ])
        ),
        WorkerActionCase(
            action: .remove,
            receipt: WorkerManagementReceipt(
                action: .remove,
                accepted: true,
                previousWorkerCount: 3,
                targetWorkerCount: 2
            ),
            baseline: snapshot(workerCount: 3, workers: [
                worker(1, incarnation: 3),
                worker(2, incarnation: 7),
                worker(3, incarnation: 9),
            ]),
            observation: snapshot(workerCount: 2, workers: [
                worker(1, incarnation: 3),
                worker(2, incarnation: 7),
            ])
        ),
    ]
}()

private func receipt(
    _ action: WorkerManagementAction,
    workerID: UInt32
) -> WorkerManagementReceipt {
    WorkerManagementReceipt(
        action: action,
        accepted: true,
        acknowledgedWorkerID: workerID
    )
}

private func snapshot(
    workerCount: UInt32,
    workers: [WorkerObservation]
) -> WorkerFleetSnapshot {
    WorkerFleetSnapshot(
        capturedAt: nil,
        workersExpected: workerCount,
        workers: workers
    )
}

/// A slot as the master reports it: a live lifecycle comes with the process
/// the master owns (spawned unless said otherwise), a dead one with neither.
private func worker(
    _ workerID: UInt32,
    lifecycle: WorkerLifecycleObservation = .running,
    ownership: WorkerOwnershipObservation? = nil,
    reloadRevision: UInt64 = 1,
    incarnation: UInt64 = 1
) -> WorkerObservation {
    let isLive: Bool = switch lifecycle {
    case .starting, .running, .reloading, .stopping:
        true
    case .unspecified, .stopped, .exited, .crashed, .unclaimed, .unrecognized:
        false
    }
    return WorkerObservation(
        workerID: workerID,
        lifecycle: lifecycle,
        ownership: ownership ?? (isLive ? .spawned : .unowned),
        process: isLive ? ProcessIdentityObservation(
            pid: workerID + 100,
            startedAt: UInt64(workerID) * 1_000 + incarnation
        ) : nil,
        uptime: nil,
        recoveryAttempts: 0,
        reloadRevision: reloadRevision,
        incarnation: incarnation
    )
}
