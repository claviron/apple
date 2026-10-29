import ClavironControlPlane
import Observation

nonisolated struct WorkerActionContext: Equatable, Sendable {
    let receipt: WorkerManagementReceipt
    let baseline: WorkerFleetSnapshot
}

@MainActor
@Observable
final class WorkerActionModel {
    let serverID: ServerID
    private let connectionModel: ConnectionModel
    private let pipeline = ManagementActionPipeline<WorkerActionContext, WorkerFleetSnapshot>()

    init(serverID: ServerID, connectionModel: ConnectionModel) {
        self.serverID = serverID
        self.connectionModel = connectionModel
    }

    var state: ManagementActionState<WorkerActionContext, WorkerFleetSnapshot> {
        pipeline.state
    }

    var isBusy: Bool {
        switch state {
        case .submitting, .accepted, .refreshing, .waiting:
            true
        case .idle, .acknowledged, .completed, .succeeded, .rejected, .failed:
            false
        }
    }

    func perform(
        _ action: WorkerManagementAction,
        baseline: WorkerFleetSnapshot
    ) async {
        await pipeline.perform(waitPolicy: Self.waitPolicy(for: action)) {
            let receipt = try await connectionModel.performWorkerAction(
                action,
                for: serverID
            )
            let context = WorkerActionContext(receipt: receipt, baseline: baseline)
            return receipt.accepted ? .accepted(context) : .rejected(context)
        } refresh: {
            try await connectionModel.refreshWorkersForAction(for: serverID)
        } assess: { context, observation in
            Self.assess(context: context, observation: observation)
        }
    }

    private nonisolated static func waitPolicy(
        for action: WorkerManagementAction
    ) -> ManagementActionWaitPolicy {
        switch action {
        case .start, .reload, .reloadAll:
            ManagementActionWaitPolicy(timeout: .seconds(10))
        case .stop:
            ManagementActionWaitPolicy(timeout: .seconds(30))
        case .restart, .restartAll, .add, .remove:
            ManagementActionWaitPolicy(timeout: .seconds(60))
        }
    }

    func incorporate(_ observation: WorkerFleetSnapshot) {
        pipeline.incorporate(observation: observation) { context, observation in
            Self.assess(context: context, observation: observation)
        }
    }

    func reset() {
        pipeline.reset()
    }

    /// Completion follows the supervisor's authoritative runtime postconditions.
    ///
    /// Acceptance is only a submission; completion is the postcondition on the
    /// authoritative snapshot. A running worker counts only while the master
    /// owns its process: start, restart and fleet growth expect a process this
    /// master spawned, reload and fleet shrink accept an adopted one, and a
    /// stop is complete once the slot is unowned with no process left. A
    /// contradiction — an incarnation that changed under a reload, a retained
    /// worker replaced by a shrink, a running slot nobody owns — is a failure,
    /// not something to keep waiting for.
    nonisolated static func assess(
        context: WorkerActionContext,
        observation: WorkerFleetSnapshot
    ) -> ManagementActionObservationAssessment {
        let baseline = context.baseline
        let receipt = context.receipt
        guard receipt.accepted,
              baseline.coverage == .complete,
              observation.coverage == .complete,
              hasConfiguredMembership(baseline),
              hasConfiguredMembership(observation) else {
            return .notYetObserved
        }

        switch receipt.action {
        case let .start(workerID):
            guard receipt.acknowledgedWorkerID == workerID,
                  let before = baseline.worker(id: workerID),
                  let after = observation.worker(id: workerID) else {
                return .notYetObserved
            }
            if let failure = terminalFailure(worker: after, operation: "start") {
                return .failed(failure)
            }
            guard after.lifecycle == .running,
                  before.lifecycle == .running || after.incarnation > before.incarnation else {
                return .notYetObserved
            }
            return completion(ownershipFailure(running: after, spawnedOnly: true))
        case let .stop(workerID):
            guard receipt.acknowledgedWorkerID == workerID,
                  baseline.worker(id: workerID) != nil,
                  let after = observation.worker(id: workerID) else {
                return .notYetObserved
            }
            if let failure = terminalFailure(worker: after, operation: "stop") {
                return .failed(failure)
            }
            guard after.lifecycle == .stopped else {
                return .notYetObserved
            }
            return completion(ownershipFailure(stopped: after))
        case let .reload(workerID):
            guard receipt.acknowledgedWorkerID == workerID,
                  let before = baseline.worker(id: workerID),
                  let after = observation.worker(id: workerID) else {
                return .notYetObserved
            }
            return reloaded(before: before, after: after, operation: "reload")
        case let .restart(workerID):
            guard receipt.acknowledgedWorkerID == workerID,
                  let before = baseline.worker(id: workerID),
                  let after = observation.worker(id: workerID) else {
                return .notYetObserved
            }
            return restarted(before: before, after: after, operation: "restart")
        case .reloadAll:
            let targets = baseline.workers.filter { $0.lifecycle == .running }
            guard !targets.isEmpty else {
                return .notYetObserved
            }
            for before in targets {
                guard let after = observation.worker(id: before.workerID) else {
                    return .notYetObserved
                }
                let assessment = reloaded(before: before, after: after, operation: "fleet reload")
                guard assessment == .completed else {
                    return assessment
                }
            }
            return .completed
        case .restartAll:
            let targets = baseline.workers.filter { $0.lifecycle == .running }
            guard !targets.isEmpty else {
                return .notYetObserved
            }
            for before in targets {
                guard let after = observation.worker(id: before.workerID) else {
                    return .notYetObserved
                }
                let assessment = restarted(
                    before: before,
                    after: after,
                    operation: "rolling restart"
                )
                guard assessment == .completed else {
                    return assessment
                }
            }
            return .completed
        case .add, .remove:
            return resizeAssessment(
                receipt: receipt,
                baseline: baseline,
                observation: observation
            )
        }
    }

    /// Reloaded in place: the same incarnation, still running under the
    /// master's ownership, with a higher reload revision.
    private nonisolated static func reloaded(
        before: WorkerObservation,
        after: WorkerObservation,
        operation: String
    ) -> ManagementActionObservationAssessment {
        if let failure = terminalFailure(worker: after, operation: operation) {
            return .failed(failure)
        }
        guard after.incarnation == before.incarnation else {
            return .failed(ClavironClientFailure(
                kind: .operationFailed,
                diagnosticDetail: "Worker \(after.workerID) changed incarnation during \(operation): expected \(before.incarnation), observed \(after.incarnation)."
            ))
        }
        guard after.lifecycle == .running else {
            return .notYetObserved
        }
        if let failure = ownershipFailure(running: after, spawnedOnly: false) {
            return .failed(failure)
        }
        return after.reloadRevision > before.reloadRevision ? .completed : .notYetObserved
    }

    /// Replaced: a higher incarnation, running as a process this master spawned.
    private nonisolated static func restarted(
        before: WorkerObservation,
        after: WorkerObservation,
        operation: String
    ) -> ManagementActionObservationAssessment {
        if let failure = terminalFailure(worker: after, operation: operation) {
            return .failed(failure)
        }
        guard after.lifecycle == .running,
              after.incarnation > before.incarnation else {
            return .notYetObserved
        }
        return completion(ownershipFailure(running: after, spawnedOnly: true))
    }

    /// Resize preserves retained workers. Growth boots only the added slot;
    /// shrink drains only the removed slot. Bootstrap counts describe a
    /// process's birth and do not require replacing it when fleet size changes.
    private nonisolated static func resizeAssessment(
        receipt: WorkerManagementReceipt,
        baseline: WorkerFleetSnapshot,
        observation: WorkerFleetSnapshot
    ) -> ManagementActionObservationAssessment {
        guard let previousCount = receipt.previousWorkerCount,
              let targetCount = receipt.targetWorkerCount,
              previousCount == baseline.workersExpected,
              observation.workersExpected == targetCount else {
            return .notYetObserved
        }

        let growing = receipt.action == .add
        let expectedDelta: Int64 = growing ? 1 : -1
        guard targetCount > 0,
              Int64(targetCount) - Int64(previousCount) == expectedDelta,
              observation.workers.map(\.workerID) == Array(1...targetCount) else {
            return .notYetObserved
        }
        let operation = growing ? "fleet growth" : "fleet shrink"

        for before in baseline.workers where before.workerID <= targetCount {
            guard let after = observation.worker(id: before.workerID) else {
                return .notYetObserved
            }
            if let failure = terminalFailure(worker: after, operation: operation) {
                return .failed(failure)
            }
            switch before.lifecycle {
            case .running:
                guard after.incarnation == before.incarnation else {
                    return .failed(ClavironClientFailure(
                        kind: .operationFailed,
                        diagnosticDetail: "Worker \(after.workerID) was replaced during \(operation): expected incarnation \(before.incarnation), observed \(after.incarnation)."
                    ))
                }
                guard after.lifecycle == .running else {
                    return .notYetObserved
                }
                if let failure = ownershipFailure(running: after, spawnedOnly: false) {
                    return .failed(failure)
                }
            case .stopped:
                guard after.lifecycle == .stopped else {
                    return .notYetObserved
                }
            case .unspecified, .starting, .reloading, .stopping, .exited, .crashed, .unclaimed,
                 .unrecognized:
                return .notYetObserved
            }
        }

        if growing {
            guard let added = observation.worker(id: targetCount) else {
                return .notYetObserved
            }
            if let failure = terminalFailure(worker: added, operation: operation) {
                return .failed(failure)
            }
            guard added.lifecycle == .running else {
                return .notYetObserved
            }
            if let failure = ownershipFailure(running: added, spawnedOnly: true) {
                return .failed(failure)
            }
        }
        return .completed
    }

    private nonisolated static func completion(
        _ failure: ClavironClientFailure?
    ) -> ManagementActionObservationAssessment {
        failure.map(ManagementActionObservationAssessment.failed) ?? .completed
    }

    /// A running worker only proves a running completion when the master owns
    /// its process — spawned by it, or adopted where the operation allows —
    /// and knows which process that is.
    private nonisolated static func ownershipFailure(
        running worker: WorkerObservation,
        spawnedOnly: Bool
    ) -> ClavironClientFailure? {
        switch worker.ownership {
        case .unspecified, .unrecognized:
            return ClavironClientFailure(
                kind: .protocolMismatch,
                diagnosticDetail: "Worker \(worker.workerID) reported an unknown process ownership."
            )
        case .unowned:
            return ClavironClientFailure(
                kind: .operationFailed,
                diagnosticDetail: "Worker \(worker.workerID) is running without supervisor process ownership."
            )
        case .adopted where spawnedOnly:
            return ClavironClientFailure(
                kind: .operationFailed,
                diagnosticDetail: "Worker \(worker.workerID) is adopted rather than spawned by the current master."
            )
        case .spawned, .adopted:
            break
        }
        guard worker.process != nil else {
            return ClavironClientFailure(
                kind: .operationFailed,
                diagnosticDetail: "Worker \(worker.workerID) is owned and running without a PID."
            )
        }
        return nil
    }

    /// A stopped slot is only stopped once nothing owns a process in it.
    private nonisolated static func ownershipFailure(
        stopped worker: WorkerObservation
    ) -> ClavironClientFailure? {
        switch worker.ownership {
        case .unspecified, .unrecognized:
            return ClavironClientFailure(
                kind: .protocolMismatch,
                diagnosticDetail: "Worker \(worker.workerID) reported an unknown process ownership."
            )
        case .spawned:
            return ClavironClientFailure(
                kind: .operationFailed,
                diagnosticDetail: "Worker \(worker.workerID) is stopped but still has spawned process ownership."
            )
        case .adopted:
            return ClavironClientFailure(
                kind: .operationFailed,
                diagnosticDetail: "Worker \(worker.workerID) is stopped but still has adopted process ownership."
            )
        case .unowned:
            break
        }
        if let pid = worker.processID {
            return ClavironClientFailure(
                kind: .operationFailed,
                diagnosticDetail: "Worker \(worker.workerID) is stopped but still reports PID \(pid)."
            )
        }
        return nil
    }

    private nonisolated static func terminalFailure(
        worker: WorkerObservation,
        operation: String
    ) -> ClavironClientFailure? {
        switch worker.lifecycle {
        case .crashed:
            ClavironClientFailure(
                kind: .operationFailed,
                diagnosticDetail: "Worker \(worker.workerID) crashed while waiting for \(operation) completion."
            )
        case .unspecified, .unrecognized:
            ClavironClientFailure(
                kind: .protocolMismatch,
                diagnosticDetail: "Worker \(worker.workerID) reported an unknown lifecycle while waiting for \(operation) completion."
            )
        case .starting, .running, .reloading, .stopping, .stopped, .exited, .unclaimed:
            nil
        }
    }

    private nonisolated static func hasConfiguredMembership(
        _ snapshot: WorkerFleetSnapshot
    ) -> Bool {
        if snapshot.workersExpected == 0 {
            return snapshot.workers.isEmpty
        }
        return snapshot.workers.map(\.workerID) == Array(1...snapshot.workersExpected)
    }
}

private extension WorkerFleetSnapshot {
    nonisolated func worker(id: UInt32) -> WorkerObservation? {
        workers.first { $0.workerID == id }
    }
}
