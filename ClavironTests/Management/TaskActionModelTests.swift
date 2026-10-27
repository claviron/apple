import ClavironControlPlane
import Foundation
import Testing
@testable import Claviron

@MainActor
struct TaskActionModelTests {
    @Test
    func synchronousRunUsesAwaitingResultSubmissionLabel() {
        #expect(
            TaskActionStatusView.submittingLabel(for: .run(name: "queue"))
                == "Awaiting task result…"
        )
        #expect(
            TaskActionStatusView.submittingLabel(
                for: .run(name: "queue"),
                elapsedSeconds: 30
            ) == "Still awaiting task result…"
        )
        #expect(TaskActionStatusView.submittingLabel(for: .start(name: "queue")) == nil)
        #expect(TaskActionStatusView.elapsedLabel(seconds: 65) == "01:05")
        #expect(TaskActionStatusView.timeoutLabel(
            ProtobufDurationObservation(seconds: 120, nanoseconds: 0)
        ) == "2m")
        #expect(TaskActionStatusView.remainingSeconds(
            timeout: ProtobufDurationObservation(seconds: 120, nanoseconds: 0),
            elapsedSeconds: 30
        ) == 90)
    }

    @Test
    func startWaitsForTheConfiguredScheduleAndEveryReportedPlacement() async {
        let baseline = snapshot(task: task(
            timing: .daemon(enabled: false),
            placements: [placement(nodeID: 1, lifecycle: .disabled, generation: 1)]
        ))
        let enabled = snapshot(task: task(
            timing: .daemon(enabled: true),
            placements: [placement(nodeID: 1, lifecycle: .active, generation: 2)]
        ))
        let action = TaskManagementAction.start(name: "queue")
        let receipt = TaskManagementReceipt(
            action: action,
            accepted: true,
            acknowledgedTaskName: "queue"
        )
        let (model, client) = await makeModel(
            actionResults: [.success(receipt)],
            taskResults: [.success(enabled)]
        )

        await model.perform(action, baseline: baseline)

        #expect(model.state == .succeeded(
            response: TaskActionContext(receipt: receipt, baseline: baseline),
            observation: enabled
        ))
        #expect(await client.taskActions == [action])
    }

    @Test
    func restartRequiresEveryEligibleDaemonGenerationToAdvance() {
        let baseline = snapshot(task: task(
            timing: .daemon(enabled: true),
            placements: [
                placement(nodeID: 1, lifecycle: .active, generation: 3),
                placement(nodeID: 2, lifecycle: .active, generation: 8),
            ]
        ), members: 2)
        let action = TaskManagementAction.restart(name: "queue")
        let receipt = TaskManagementReceipt(
            action: action,
            accepted: true,
            acknowledgedTaskName: "queue"
        )
        let context = TaskActionContext(receipt: receipt, baseline: baseline)
        let partial = snapshot(task: task(
            timing: .daemon(enabled: true),
            placements: [
                placement(nodeID: 1, lifecycle: .active, generation: 4),
                placement(nodeID: 2, lifecycle: .active, generation: 8),
            ]
        ), members: 2)
        let complete = snapshot(task: task(
            timing: .daemon(enabled: true),
            placements: [
                placement(nodeID: 1, lifecycle: .active, generation: 4),
                placement(nodeID: 2, lifecycle: .active, generation: 9),
            ]
        ), members: 2)

        #expect(TaskActionModel.assess(context: context, observation: partial) == .notYetObserved)
        #expect(TaskActionModel.assess(context: context, observation: complete) == .completed)
    }

    @Test
    func reloadEndsAtAcknowledgementWhileRunEndsAtItsSynchronousResult() async {
        for (action, expectedTerminal) in [
            (TaskManagementAction.reload(name: "queue"), "acknowledged"),
            (TaskManagementAction.run(name: "queue"), "completed"),
        ] {
            let baseline = snapshot(task: task(
                timing: .manual(executionTimeout: nil),
                placements: [placement(nodeID: 1, lifecycle: .inactive, generation: 1)]
            ))
            let receipt = TaskManagementReceipt(
                action: action,
                accepted: true,
                acknowledgedTaskName: "queue",
                runID: action == .run(name: "queue") ? 42 : nil,
                runResult: action == .run(name: "queue") ? .succeeded : nil
            )
            let (model, client) = await makeModel(
                actionResults: [.success(receipt)], taskResults: [.success(baseline), .success(baseline)]
            )

            await model.perform(action, baseline: baseline)

            let context = TaskActionContext(receipt: receipt, baseline: baseline)
            if expectedTerminal == "acknowledged" {
                #expect(model.state == .acknowledged(context))
            } else {
                #expect(model.state == .completed(context))
            }
            if expectedTerminal == "acknowledged" {
                #expect(await client.taskRequestCount == 0)
            } else {
                #expect(await client.taskRequestCount >= 1)
            }
        }
    }

    @Test
    func runUsesTheExecutionTimeoutObservedInItsBaseline() async {
        let timeout = ProtobufDurationObservation(seconds: 120, nanoseconds: 0)
        let baseline = snapshot(task: task(
            timing: .manual(executionTimeout: timeout),
            placements: []
        ))
        let action = TaskManagementAction.run(name: "queue")
        let receipt = TaskManagementReceipt(
            action: action,
            accepted: true,
            acknowledgedTaskName: "queue",
            runID: 42,
            runResult: .succeeded
        )
        let (model, client) = await makeModel(
            actionResults: [.success(receipt)], taskResults: [.success(baseline), .success(baseline)]
        )

        await model.perform(action, baseline: baseline)

        #expect(await client.taskActionRunExecutionTimeouts == [timeout])
        #expect(model.state == .completed(TaskActionContext(
            receipt: receipt,
            baseline: baseline
        )))
    }

    @Test
    func runWithoutAnExecutionResultIsNotCompleted() async {
        let baseline = snapshot(task: task(timing: .manual(executionTimeout: nil), placements: []))
        let receipt = TaskManagementReceipt(
            action: .run(name: "queue"), accepted: true, acknowledgedTaskName: "queue", runID: 42
        )
        let (model, _) = await makeModel(
            actionResults: [.success(receipt)], taskResults: [.success(baseline), .success(baseline)]
        )
        await model.perform(receipt.action, baseline: baseline)
        guard case let .failed(failure, _) = model.state else {
            Issue.record("A run with no execution result was presented as complete.")
            return
        }
        #expect(failure.kind == .protocolMismatch)
    }

    @Test
    func failedRunResultIsKeptSeparateFromAnInventoryRefreshFailure() async {
        let baseline = snapshot(task: task(timing: .manual(executionTimeout: nil), placements: []))
        let receipt = TaskManagementReceipt(
            action: .run(name: "queue"), accepted: true, acknowledgedTaskName: "queue",
            runID: 42, runResult: .failed(TaskRunFailure(kind: .task, message: "example failure"))
        )
        let (model, _) = await makeModel(actionResults: [.success(receipt)])
        await model.perform(receipt.action, baseline: baseline)
        #expect(model.state == .completed(TaskActionContext(receipt: receipt, baseline: baseline)))
    }

    @Test
    func runningRowIsObservedBeforeRunResponseAndRefreshedAfterwards() async {
        let running = snapshot(task: task(
            timing: .manual(executionTimeout: nil),
            placements: [placement(nodeID: 1, lifecycle: .active, generation: 1)]
        ))
        let finished = snapshot(task: task(
            timing: .manual(executionTimeout: nil),
            placements: [placement(nodeID: 1, lifecycle: .inactive, generation: 1)]
        ))
        let receipt = TaskManagementReceipt(
            action: .run(name: "queue"), accepted: true, acknowledgedTaskName: "queue",
            runID: 42, runResult: .succeeded
        )
        let client = PendingRunClient(running: running, finished: finished, receipt: receipt)
        let app = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let connections = ConnectionModel(applicationModel: app) { _ in client }
        let serverID = TestConfiguration.primaryServerID
        await connections.connect(to: serverID)
        let model = TaskActionModel(serverID: serverID, connectionModel: connections)
        let operation = Task { await model.perform(receipt.action, baseline: finished) }

        // Yield until the model consumes the controlled server observation;
        // no clock/sleep or real task execution is involved in this fixture.
        while connections.taskObservationState(for: serverID).snapshot != running {
            await Task.yield()
        }
        #expect(model.state == .submitting)
        #expect(TaskPresentationStatus.summary(for: running.tasks[0]).title == "Running")
        await client.finishRun()
        await operation.value
        #expect(connections.taskObservationState(for: serverID).snapshot == finished)
        #expect(model.state == .completed(TaskActionContext(receipt: receipt, baseline: finished)))
    }

    @Test
    func registeredScheduledAndManualTasksCanRunFromTheInventory() {
        let timings: [TaskTimingObservation] = [
            .manual(executionTimeout: nil),
            .interval(every: nil, executionTimeout: nil, enabled: false),
            .cron(expression: "0 * * * *", executionTimeout: nil, enabled: true),
        ]

        for timing in timings {
            let registered = task(timing: timing, placements: [])
            let inventory = snapshot(task: registered, members: 0)

            #expect(TaskActionModel.canSubmit(
                action: .run(name: registered.name),
                task: registered,
                snapshot: inventory
            ))
        }

        let daemon = task(timing: .daemon(enabled: true), placements: [])
        #expect(!TaskActionModel.canSubmit(
            action: .run(name: daemon.name),
            task: daemon,
            snapshot: snapshot(task: daemon, members: 0)
        ))
    }

    private func makeModel(
        actionResults: [MockClavironClient.TaskActionResult],
        taskResults: [MockClavironClient.TaskResult] = []
    ) async -> (TaskActionModel, MockClavironClient) {
        let applicationModel = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let client = MockClavironClient(
            results: [.success(.preview)],
            taskResults: taskResults,
            taskActionResults: actionResults
        )
        let connectionModel = ConnectionModel(applicationModel: applicationModel) { _ in client }
        let serverID = TestConfiguration.primaryServerID
        await connectionModel.connect(to: serverID)
        return (
            TaskActionModel(serverID: serverID, connectionModel: connectionModel),
            client
        )
    }
}

private actor PendingRunClient: ClavironClient {
    let running: TaskFleetSnapshot
    let finished: TaskFleetSnapshot
    let receipt: TaskManagementReceipt
    private var runContinuation: CheckedContinuation<TaskManagementReceipt, Never>?
    private var completed = false

    init(running: TaskFleetSnapshot, finished: TaskFleetSnapshot, receipt: TaskManagementReceipt) {
        self.running = running
        self.finished = finished
        self.receipt = receipt
    }

    func performTaskAction(
        _ action: TaskManagementAction, runExecutionTimeout: ProtobufDurationObservation?
    ) async throws -> TaskManagementReceipt {
        if completed { return receipt }
        return await withCheckedContinuation { runContinuation = $0 }
    }

    func finishRun() {
        completed = true
        runContinuation?.resume(returning: receipt)
        runContinuation = nil
    }

    func loadTasks() async throws -> TaskFleetSnapshot { completed ? finished : running }
    func loadServices() async throws -> ServiceFleetSnapshot { .preview }
    func loadWorkers() async throws -> WorkerFleetSnapshot { throw CancellationError() }
    func loadApplications() async throws -> ApplicationFleetSnapshot { throw CancellationError() }
    func loadHosting() async throws -> HostingInventorySnapshot { throw CancellationError() }
    func loadCertificates() async throws -> CertificateInventorySnapshot { throw CancellationError() }
    func disconnect() async { }
}

private func snapshot(
    task: TaskObservation,
    members: UInt32 = 1
) -> TaskFleetSnapshot {
    TaskFleetSnapshot(
        capturedAt: Date(timeIntervalSince1970: 100),
        membersExpected: members,
        membersReporting: members,
        tasks: [task]
    )
}

private func task(
    timing: TaskTimingObservation,
    placements: [TaskPlacementObservation]
) -> TaskObservation {
    TaskObservation(
        name: "queue",
        kind: .command,
        scope: .workers,
        dispatch: .pool,
        timing: timing,
        concurrency: 2,
        placements: placements
    )
}

private func placement(
    nodeID: UInt32,
    lifecycle: TaskLifecycleObservation,
    generation: UInt64
) -> TaskPlacementObservation {
    TaskPlacementObservation(
        member: TaskMemberObservation(nodeID: nodeID, role: .worker),
        lifecycle: lifecycle,
        inFlight: lifecycle == .active ? 1 : 0,
        lastExecution: nil,
        observedAt: Date(timeIntervalSince1970: 100),
        generation: generation
    )
}
