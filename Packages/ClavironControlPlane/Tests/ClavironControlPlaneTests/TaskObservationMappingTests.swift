import Foundation
import Testing
@testable import ClavironControlPlane

@Suite("Task observation mapping")
struct TaskObservationMappingTests {
    @Test("Builtin, command, and PHP task kinds remain distinct")
    func supportedTaskKindsArePreserved() {
        var generated = Claviron_Tasks_TaskStatus()

        generated.kind = .builtin
        #expect(DirectClavironClient.taskObservation(generated).kind == .builtin)

        generated.kind = .command
        #expect(DirectClavironClient.taskObservation(generated).kind == .command)

        generated.kind = .php
        #expect(DirectClavironClient.taskObservation(generated).kind == .php)
    }

    @Test("Task command receipts reject a mismatched acknowledged name")
    func taskCommandReceiptValidatesIdentity() throws {
        let action = TaskManagementAction.start(name: "queue")
        var response = Claviron_Tasks_TaskCommandResponse()
        response.name = "other"
        response.accepted = true

        #expect(throws: ClavironClientFailure.self) {
            try DirectClavironClient.taskReceipt(action: action, response: response)
        }
    }

    @Test("Run receipts preserve terminal success, failure, and correlation id")
    func taskRunReceiptsPreserveTerminalResult() throws {
        let action = TaskManagementAction.run(name: "queue")
        var success = Claviron_Tasks_RunTaskResponse()
        success.name = "queue"
        success.runID = 41
        success.success = Claviron_Tasks_RunTaskSuccess()

        #expect(try DirectClavironClient.taskRunReceipt(
            action: action,
            response: success
        ) == TaskManagementReceipt(
            action: action,
            accepted: true,
            acknowledgedTaskName: "queue",
            runID: 41,
            runResult: .succeeded
        ))

        var failure = Claviron_Tasks_RunTaskResponse()
        failure.name = "queue"
        failure.runID = 42
        failure.failure.kind = .executionTimeout
        failure.failure.message = "execution exceeded 30 seconds"

        #expect(try DirectClavironClient.taskRunReceipt(
            action: action,
            response: failure
        ) == TaskManagementReceipt(
            action: action,
            accepted: true,
            acknowledgedTaskName: "queue",
            runID: 42,
            runResult: .failed(TaskRunFailure(
                kind: .executionTimeout,
                message: "execution exceeded 30 seconds"
            ))
        ))
    }

    @Test("Run receipts reject an absent terminal result")
    func taskRunReceiptRequiresTerminalResult() {
        let action = TaskManagementAction.run(name: "queue")
        var response = Claviron_Tasks_RunTaskResponse()
        response.name = "queue"
        response.runID = 43

        #expect(throws: ClavironClientFailure.self) {
            try DirectClavironClient.taskRunReceipt(
                action: action,
                response: response
            )
        }
    }

    @Test("Run transport deadline leaves room for the terminal response")
    func taskRunResponseTimeoutIncludesResponseAllowance() {
        let executionTimeout = ProtobufDurationObservation(
            seconds: 120,
            nanoseconds: 250_000_000
        )

        #expect(DirectClavironClient.taskRunResponseTimeout(
            executionTimeout: executionTimeout
        ) == .seconds(150) + .milliseconds(250))
        #expect(DirectClavironClient.taskRunResponseTimeout(
            executionTimeout: nil
        ) == nil)
    }

    @Test("Task configuration, placement, freshness, and execution facts are preserved")
    func taskFactsArePreserved() {
        var generated = Claviron_Tasks_TaskStatus()
        generated.name = "wallet-reconciliation"
        generated.kind = .UNRECOGNIZED(101)
        generated.scope = .UNRECOGNIZED(102)
        generated.dispatch = .UNRECOGNIZED(103)
        generated.concurrency = 4
        generated.timing.interval.every.seconds = 60
        generated.timing.interval.every.nanos = 7
        generated.timing.interval.enabled = true

        var placement = Claviron_Tasks_TaskPlacementStatus()
        placement.member.nodeID = 9
        placement.member.role = .UNRECOGNIZED(104)
        placement.lifecycle = .UNRECOGNIZED(105)
        placement.inFlight = 3
        placement.ownedSlots = 2
        placement.lastExecution.result = .UNRECOGNIZED(106)
        placement.lastExecution.finishedAt.seconds = 240
        placement.observedAt.seconds = 250
        placement.generation = 11
        generated.placements = [placement]

        let task = DirectClavironClient.taskObservation(generated)

        #expect(task.name == "wallet-reconciliation")
        #expect(task.kind == .unrecognized(101))
        #expect(task.scope == .unrecognized(102))
        #expect(task.dispatch == .unrecognized(103))
        #expect(task.concurrency == 4)
        #expect(task.timing == .interval(
            every: ProtobufDurationObservation(seconds: 60, nanoseconds: 7),
            executionTimeout: nil,
            enabled: true
        ))
        #expect(task.placements.count == 1)
        let mapped = task.placements[0]
        #expect(mapped.member == TaskMemberObservation(
            nodeID: 9,
            role: .unrecognized(104)
        ))
        #expect(mapped.lifecycle == .unrecognized(105))
        #expect(mapped.inFlight == 3)
        #expect(mapped.ownedSlots == 2)
        #expect(mapped.lastExecution == TaskExecutionOutcomeObservation(
            result: .unrecognized(106),
            finishedAt: Date(timeIntervalSince1970: 240)
        ))
        #expect(mapped.observedAt?.timeIntervalSince1970 == 250)
        #expect(mapped.generation == 11)
    }

    @Test("Absent task messages remain absent while a present empty timing stays explicit")
    func absentMessagesRemainAbsent() {
        var absentTiming = Claviron_Tasks_TaskStatus()
        absentTiming.placements = [Claviron_Tasks_TaskPlacementStatus()]

        let absent = DirectClavironClient.taskObservation(absentTiming)
        #expect(absent.timing == nil)
        #expect(absent.placements[0].member == nil)
        #expect(absent.placements[0].lastExecution == nil)
        #expect(absent.placements[0].observedAt == nil)

        var emptyTiming = Claviron_Tasks_TaskStatus()
        emptyTiming.timing = Claviron_Tasks_TaskTiming()
        #expect(DirectClavironClient.taskObservation(emptyTiming).timing == .unspecified)
    }

    @Test("Task fleet coverage does not fabricate a complete report")
    func fleetCoverageIsExplicit() {
        #expect(snapshot(expected: 2, reporting: 2).coverage == .complete)
        #expect(snapshot(expected: 2, reporting: 1).coverage == .partial)
        #expect(snapshot(expected: 0, reporting: 0).coverage == .noReports)
        #expect(snapshot(expected: 2, reporting: 0).coverage == .noReports)
    }

    private func snapshot(expected: UInt32, reporting: UInt32) -> TaskFleetSnapshot {
        TaskFleetSnapshot(
            capturedAt: nil,
            membersExpected: expected,
            membersReporting: reporting,
            tasks: []
        )
    }
}
