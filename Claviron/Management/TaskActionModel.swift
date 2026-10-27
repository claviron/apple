import ClavironControlPlane
import Foundation
import Observation

nonisolated struct TaskActionContext: Equatable, Sendable {
    let receipt: TaskManagementReceipt
    let baseline: TaskFleetSnapshot
}

@MainActor
@Observable
final class TaskActionModel {
    let serverID: ServerID
    private let connectionModel: ConnectionModel
    private let pipeline = ManagementActionPipeline<TaskActionContext, TaskFleetSnapshot>()
    private(set) var submittedAt: Date?
    private(set) var submittedRunExecutionTimeout: ProtobufDurationObservation?

    init(serverID: ServerID, connectionModel: ConnectionModel) {
        self.serverID = serverID
        self.connectionModel = connectionModel
    }

    var state: ManagementActionState<TaskActionContext, TaskFleetSnapshot> {
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
        _ action: TaskManagementAction,
        baseline: TaskFleetSnapshot
    ) async {
        let runExecutionTimeout = Self.runExecutionTimeout(for: action, in: baseline)
        submittedAt = Date()
        submittedRunExecutionTimeout = runExecutionTimeout

        await pipeline.perform(waitPolicy: Self.waitPolicy(for: action)) {
            let receipt = try await submit(action, runExecutionTimeout: runExecutionTimeout)
            let context = TaskActionContext(receipt: receipt, baseline: baseline)
            guard receipt.accepted else {
                return .rejected(context)
            }
            switch action {
            case .reload:
                return .acknowledged(context)
            case .run:
                guard receipt.runResult != nil else {
                    throw Self.protocolFailure("Task '\(action.taskName)' returned no execution result.")
                }
                return .completed(context)
            case .start, .stop, .restart:
                return .accepted(context)
            }
        } refresh: {
            try await connectionModel.refreshTasksForAction(for: serverID)
        } assess: { context, observation in
            Self.assess(context: context, observation: observation)
        }
    }

    private func submit(
        _ action: TaskManagementAction,
        runExecutionTimeout: ProtobufDurationObservation?
    ) async throws -> TaskManagementReceipt {
        guard case .run = action else {
            return try await connectionModel.performTaskAction(
                action, for: serverID, runExecutionTimeout: runExecutionTimeout
            )
        }

        // Run's RPC remains open until execution ends. Keep the inventory
        // observing real placements in the meantime, using the existing
        // management refresh cadence, not an execution/convergence timeout.
        let cadence = Self.waitPolicy(for: action).pollInterval
        let observer = Task {
            while !Task.isCancelled {
                // ConnectionModel retains a stale observation on failure.
                _ = try? await connectionModel.refreshTasksForAction(for: serverID)
                do {
                    try await Task.sleep(for: cadence)
                } catch {
                    return
                }
            }
        }
        let result: Result<TaskManagementReceipt, Error>
        do {
            result = .success(try await connectionModel.performTaskAction(
                action, for: serverID, runExecutionTimeout: runExecutionTimeout
            ))
        } catch {
            result = .failure(error)
        }
        observer.cancel()
        await observer.value
        // Refresh even after an RPC failure: a transport error does not prove
        // that server-owned work stopped. Never overwrite its execution result
        // with a failure to observe the inventory.
        _ = try? await connectionModel.refreshTasksForAction(for: serverID)
        return try result.get()
    }

    func incorporate(_ observation: TaskFleetSnapshot) {
        pipeline.incorporate(observation: observation) { context, observation in
            Self.assess(context: context, observation: observation)
        }
    }

    nonisolated static func assess(
        context: TaskActionContext,
        observation: TaskFleetSnapshot
    ) -> ManagementActionObservationAssessment {
        let receipt = context.receipt
        guard receipt.accepted,
              receipt.acknowledgedTaskName == receipt.action.taskName else {
            return .notYetObserved
        }

        switch receipt.action {
        case .reload, .run:
            return .completed
        case .start, .stop:
            return assessScheduleState(action: receipt.action, observation: observation)
        case .restart:
            return assessRestart(context: context, observation: observation)
        }
    }

    nonisolated static func canSubmit(
        action: TaskManagementAction,
        task: TaskObservation,
        snapshot: TaskFleetSnapshot
    ) -> Bool {
        guard !action.taskName.isEmpty,
              action.taskName == task.name,
              snapshot.tasks.filter({ $0.name == task.name }).count == 1 else {
            return false
        }

        if case .run = action {
            return task.timing.supportsRun
        }

        guard snapshot.membersReporting > 0 else {
            return false
        }

        switch action {
        case .start:
            return task.timing.scheduleEnabled == false
        case .stop:
            return task.timing.scheduleEnabled == true
        case .reload:
            return true
        case .restart:
            return task.timing.isEnabledDaemon && task.hasRestartTarget
        case .run:
            return false
        }
    }

    private nonisolated static func waitPolicy(
        for action: TaskManagementAction
    ) -> ManagementActionWaitPolicy {
        switch action {
        case .start, .stop:
            ManagementActionWaitPolicy(timeout: .seconds(10))
        case .restart:
            ManagementActionWaitPolicy(timeout: .seconds(30))
        case .reload, .run:
            ManagementActionWaitPolicy(timeout: .seconds(1))
        }
    }

    nonisolated static func runExecutionTimeout(
        for action: TaskManagementAction,
        in snapshot: TaskFleetSnapshot
    ) -> ProtobufDurationObservation? {
        guard case .run = action else {
            return nil
        }
        return snapshot.uniqueTask(named: action.taskName)?.timing?.executionTimeout
    }

    private nonisolated static func assessScheduleState(
        action: TaskManagementAction,
        observation: TaskFleetSnapshot
    ) -> ManagementActionObservationAssessment {
        guard observation.membersReporting > 0,
              let task = observation.uniqueTask(named: action.taskName),
              task.placements.count == Int(observation.membersReporting) else {
            return .notYetObserved
        }

        let wantsEnabled: Bool
        switch action {
        case .start:
            wantsEnabled = true
        case .stop:
            wantsEnabled = false
        case .reload, .restart, .run:
            return .notYetObserved
        }
        guard task.timing.scheduleEnabled == wantsEnabled else {
            return .notYetObserved
        }

        var members: [TaskMemberObservation] = []
        for placement in task.placements {
            guard let member = placement.member,
                  !members.contains(member) else {
                return .failed(protocolFailure(
                    "Task '\(task.name)' reported a missing or duplicate fleet member."
                ))
            }
            members.append(member)
            if let failure = terminalFailure(task: task, placement: placement) {
                return .failed(failure)
            }

            let complete = wantsEnabled
                ? enableConfirmed(task: task, placement: placement)
                : placement.lifecycle == .ineligible || placement.lifecycle == .disabled
            guard complete else {
                return .notYetObserved
            }
        }
        return .completed
    }

    private nonisolated static func assessRestart(
        context: TaskActionContext,
        observation: TaskFleetSnapshot
    ) -> ManagementActionObservationAssessment {
        let name = context.receipt.action.taskName
        guard let before = context.baseline.uniqueTask(named: name),
              before.timing.isEnabledDaemon else {
            return .failed(operationFailure(
                "Task '\(name)' did not have an enabled daemon baseline."
            ))
        }

        let targets = before.placements.compactMap { placement -> (TaskMemberObservation, UInt64)? in
            guard let member = placement.member,
                  placement.lifecycle != .ineligible else {
                return nil
            }
            return (member, placement.generation)
        }
        guard !targets.isEmpty,
              let after = observation.uniqueTask(named: name),
              after.timing.isEnabledDaemon else {
            return .notYetObserved
        }

        for (member, generation) in targets {
            guard let placement = after.placements.first(where: { $0.member == member }) else {
                return .notYetObserved
            }
            if let failure = terminalFailure(task: after, placement: placement) {
                return .failed(failure)
            }
            guard placement.generation > generation,
                  enableConfirmed(task: after, placement: placement) else {
                return .notYetObserved
            }
        }
        return .completed
    }

    private nonisolated static func enableConfirmed(
        task: TaskObservation,
        placement: TaskPlacementObservation
    ) -> Bool {
        if placement.lifecycle == .ineligible || placement.lifecycle == .active {
            return true
        }
        return task.timing.isDaemon
            && placement.lifecycle == .finished
            && placement.lastExecution?.result == .succeeded
    }

    private nonisolated static func terminalFailure(
        task: TaskObservation,
        placement: TaskPlacementObservation
    ) -> ClavironClientFailure? {
        switch placement.lifecycle {
        case .missingRunner:
            operationFailure("Task '\(task.name)' has no runner on a target fleet member.")
        case .unspecified, .unrecognized:
            protocolFailure("Task '\(task.name)' reported an unknown lifecycle.")
        case .ineligible, .disabled, .inactive, .active, .stopping, .finished:
            nil
        }
    }

    private nonisolated static func protocolFailure(
        _ detail: String
    ) -> ClavironClientFailure {
        ClavironClientFailure(kind: .protocolMismatch, diagnosticDetail: detail)
    }

    private nonisolated static func operationFailure(
        _ detail: String
    ) -> ClavironClientFailure {
        ClavironClientFailure(kind: .operationFailed, diagnosticDetail: detail)
    }
}

extension TaskTimingObservation? {
    nonisolated var scheduleEnabled: Bool? {
        switch self {
        case let .daemon(enabled), let .interval(_, _, enabled), let .cron(_, _, enabled):
            enabled
        case .manual, .unspecified, nil:
            nil
        }
    }

    nonisolated var isDaemon: Bool {
        if case .daemon = self {
            return true
        }
        return false
    }

    nonisolated var isEnabledDaemon: Bool {
        if case .daemon(enabled: true) = self {
            return true
        }
        return false
    }

    nonisolated var supportsRun: Bool {
        switch self {
        case .interval, .cron, .manual:
            true
        case .daemon, .unspecified, nil:
            false
        }
    }

    nonisolated var hasScheduleControl: Bool {
        switch self {
        case .daemon, .interval, .cron:
            true
        case .manual, .unspecified, nil:
            false
        }
    }
}

private extension TaskObservation {
    nonisolated var hasRestartTarget: Bool {
        placements.contains { placement in
            placement.member != nil
                && placement.lifecycle != .ineligible
                && placement.lifecycle != .missingRunner
        }
    }
}

private extension TaskFleetSnapshot {
    nonisolated func uniqueTask(named name: String) -> TaskObservation? {
        let matches = tasks.filter { $0.name == name }
        return matches.count == 1 ? matches[0] : nil
    }
}
