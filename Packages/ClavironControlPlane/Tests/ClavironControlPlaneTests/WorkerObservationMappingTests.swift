import Testing
@testable import ClavironControlPlane

@Suite("Worker observation mapping")
struct WorkerObservationMappingTests {
    @Test("Worker command acknowledgements must match the requested worker and keep the submission key")
    func workerCommandAcknowledgementIsValidated() throws {
        var response = Claviron_Workers_WorkerCommandResponse()
        response.workerID = 4
        response.accepted = true
        response.submissionKey = 0x0200_0197_0000_0001

        #expect(try DirectClavironClient.workerReceipt(
            action: .restart(workerID: 4),
            workerID: 4,
            response: response
        ) == WorkerManagementReceipt(
            action: .restart(workerID: 4),
            accepted: true,
            submissionKey: 0x0200_0197_0000_0001,
            acknowledgedWorkerID: 4
        ))

        #expect(throws: ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "The worker command targeted worker 3, but the server acknowledged worker 4."
        )) {
            try DirectClavironClient.workerReceipt(
                action: .restart(workerID: 3),
                workerID: 3,
                response: response
            )
        }
    }

    @Test("Accepted resize acknowledgements must change the fleet by exactly one")
    func resizeAcknowledgementIsValidated() throws {
        var response = Claviron_Workers_ResizeWorkersResponse()
        response.accepted = true
        response.previousWorkerCount = 2
        response.targetWorkerCount = 3
        response.submissionKey = 0x0200_0197_0000_0002

        #expect(try DirectClavironClient.resizeWorkerReceipt(
            action: .add,
            response: response
        ) == WorkerManagementReceipt(
            action: .add,
            accepted: true,
            submissionKey: 0x0200_0197_0000_0002,
            previousWorkerCount: 2,
            targetWorkerCount: 3
        ))

        #expect(throws: ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "The accepted worker resize returned an invalid transition from 2 to 3."
        )) {
            try DirectClavironClient.resizeWorkerReceipt(
                action: .remove,
                response: response
            )
        }
    }

    @Test("Worker fields and optional presence are preserved")
    func workerFactsArePreserved() {
        var generated = Claviron_Workers_WorkerStatus()
        generated.workerID = 4
        generated.lifecycle = .UNRECOGNIZED(88)
        generated.ownership = .adopted
        generated.process.pid = 4_321
        generated.process.startedAt = 0x0a0b
        generated.uptime.seconds = 91
        generated.uptime.nanos = 12
        generated.recoveryAttempts = 2
        generated.reloadRevision = 7
        generated.incarnation = 9
        generated.phase = .drainAcknowledged
        generated.phaseAge.seconds = 3
        generated.desired.state = .drain(.with {
            $0.reason = .rollingRestart
            $0.afterExit = .finishFleetShutdown
        })
        generated.desiredAge.seconds = 12
        generated.operation.id = 9
        generated.operation.kind = .resize
        generated.operation.resizeFrom = 3
        generated.operation.resizeTo = 4
        generated.operation.origin.origin = .management(.with {
            $0.viaWorker = 2
            $0.submissionKey = 0x0200_0197_0000_0001
        })
        generated.operation.age.nanos = 250_000_000
        generated.heartbeatAge.nanos = 700_000_000
        generated.blockReason = .masterStillAlive

        let worker = DirectClavironClient.workerObservation(generated)

        #expect(worker.workerID == 4)
        #expect(worker.lifecycle == .unrecognized(88))
        #expect(worker.ownership == .adopted)
        #expect(worker.process == ProcessIdentityObservation(pid: 4_321, startedAt: 0x0a0b))
        #expect(worker.processID == 4_321)
        #expect(worker.uptime == ProtobufDurationObservation(seconds: 91, nanoseconds: 12))
        #expect(worker.recoveryAttempts == 2)
        #expect(worker.reloadRevision == 7)
        #expect(worker.incarnation == 9)
        #expect(worker.phase == .drainAcknowledged)
        #expect(worker.phaseAge == ProtobufDurationObservation(seconds: 3, nanoseconds: 0))
        #expect(worker.desired == .drain(reason: .rollingRestart, afterExit: .finishFleetShutdown))
        #expect(worker.desiredAge == ProtobufDurationObservation(seconds: 12, nanoseconds: 0))
        #expect(worker.operation == WorkerOperationObservation(
            id: 9,
            kind: .resize(from: 3, to: 4),
            origin: .management(viaWorker: 2, submissionKey: 0x0200_0197_0000_0001),
            age: ProtobufDurationObservation(seconds: 0, nanoseconds: 250_000_000)
        ))
        #expect(worker.heartbeatAge == ProtobufDurationObservation(seconds: 0, nanoseconds: 700_000_000))
        #expect(worker.blockReason == .masterStillAlive)
    }

    @Test("Absent optional worker fields remain absent")
    func absentOptionalFieldsRemainAbsent() {
        let worker = DirectClavironClient.workerObservation(
            Claviron_Workers_WorkerStatus()
        )

        #expect(worker.ownership == .unspecified)
        #expect(worker.process == nil)
        #expect(worker.processID == nil)
        #expect(worker.uptime == nil)
        #expect(worker.phase == .unspecified)
        #expect(worker.phaseAge == nil)
        #expect(worker.desired == .unspecified)
        #expect(worker.desiredAge == nil)
        #expect(worker.operation == nil)
        #expect(worker.heartbeatAge == nil)
        #expect(worker.blockReason == nil)
    }

    @Test("An operation without a management origin carries no submission key")
    func supervisorOriginHasNoSubmissionKey() {
        var generated = Claviron_Workers_WorkerStatus()
        generated.operation.id = 3
        generated.operation.kind = .rotation
        generated.operation.origin.origin = .supervisor(Claviron_Workers_WorkerSupervisorOrigin())

        let worker = DirectClavironClient.workerObservation(generated)

        #expect(worker.operation == WorkerOperationObservation(
            id: 3,
            kind: .rotation,
            origin: .supervisor,
            age: nil
        ))
    }

    @Test("The snapshot header carries master, fleet mode and build")
    func snapshotHeaderIsPreserved() {
        var response = Claviron_Workers_ListWorkersResponse()
        response.workersExpected = 1
        response.master.process.pid = 4_242
        response.master.process.startedAt = 0x0102
        response.master.generation = 7
        response.fleetMode = .shuttingDown
        response.build.revision = "0e0d369e"
        response.build.dirty = true

        let snapshot = DirectClavironClient.workerFleetSnapshot(response)

        #expect(snapshot.capturedAt == nil)
        #expect(snapshot.workersExpected == 1)
        #expect(snapshot.master == MasterIdentityObservation(
            process: ProcessIdentityObservation(pid: 4_242, startedAt: 0x0102),
            generation: 7
        ))
        #expect(snapshot.fleetMode == .shuttingDown)
        #expect(snapshot.build == BuildIdentityObservation(revision: "0e0d369e", dirty: true))

        let bare = DirectClavironClient.workerFleetSnapshot(Claviron_Workers_ListWorkersResponse())
        #expect(bare.master == nil)
        #expect(bare.fleetMode == .unspecified)
        #expect(bare.build == nil)
    }

    @Test("Unclaimed worker slots remain an explicit lifecycle")
    func unclaimedLifecycleIsPreserved() {
        var generated = Claviron_Workers_WorkerStatus()
        generated.workerID = 2
        generated.lifecycle = .unclaimed

        let worker = DirectClavironClient.workerObservation(generated)

        #expect(worker.lifecycle == .unclaimed)
    }

    @Test("Worker coverage distinguishes empty, missing, and partial reports")
    func workerCoverageIsExplicit() {
        #expect(snapshot(expected: 0, observed: 0).coverage == .complete)
        #expect(snapshot(expected: 2, observed: 0).coverage == .noReports)
        #expect(snapshot(expected: 2, observed: 1).coverage == .partial)
        #expect(snapshot(expected: 2, observed: 2).coverage == .complete)
        #expect(snapshot(expected: 1, observed: 2).coverage == .partial)
    }

    private func snapshot(expected: UInt32, observed: Int) -> WorkerFleetSnapshot {
        WorkerFleetSnapshot(
            capturedAt: nil,
            workersExpected: expected,
            workers: (0..<observed).map { index in
                WorkerObservation(
                    workerID: UInt32(index),
                    lifecycle: .unspecified,
                    ownership: .unspecified,
                    process: nil,
                    uptime: nil,
                    recoveryAttempts: 0,
                    reloadRevision: 0,
                    incarnation: 0
                )
            }
        )
    }
}
