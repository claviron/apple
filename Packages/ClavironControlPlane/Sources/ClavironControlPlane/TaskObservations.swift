import Foundation

public struct TaskFleetSnapshot: Equatable, Sendable {
    public let capturedAt: Date?
    public let membersExpected: UInt32
    public let membersReporting: UInt32
    public let tasks: [TaskObservation]

    public init(
        capturedAt: Date?,
        membersExpected: UInt32,
        membersReporting: UInt32,
        tasks: [TaskObservation]
    ) {
        self.capturedAt = capturedAt
        self.membersExpected = membersExpected
        self.membersReporting = membersReporting
        self.tasks = tasks
    }

    public var coverage: FleetCoverage {
        if membersReporting == 0 {
            .noReports
        } else if membersReporting == membersExpected {
            .complete
        } else {
            .partial
        }
    }
}

public struct TaskObservation: Equatable, Sendable {
    public let name: String
    public let kind: TaskKindObservation
    public let scope: TaskScopeObservation
    public let dispatch: TaskDispatchObservation
    public let timing: TaskTimingObservation?
    public let concurrency: UInt32
    public let placements: [TaskPlacementObservation]

    public init(
        name: String,
        kind: TaskKindObservation,
        scope: TaskScopeObservation,
        dispatch: TaskDispatchObservation,
        timing: TaskTimingObservation?,
        concurrency: UInt32,
        placements: [TaskPlacementObservation]
    ) {
        self.name = name
        self.kind = kind
        self.scope = scope
        self.dispatch = dispatch
        self.timing = timing
        self.concurrency = concurrency
        self.placements = placements
    }
}

public enum TaskTimingObservation: Equatable, Sendable {
    case unspecified
    case daemon(enabled: Bool)
    case interval(
        every: ProtobufDurationObservation?,
        executionTimeout: ProtobufDurationObservation?,
        enabled: Bool
    )
    case cron(
        expression: String,
        executionTimeout: ProtobufDurationObservation?,
        enabled: Bool
    )
    case manual(executionTimeout: ProtobufDurationObservation?)

    public var executionTimeout: ProtobufDurationObservation? {
        switch self {
        case let .interval(_, executionTimeout, _),
             let .cron(_, executionTimeout, _),
             let .manual(executionTimeout):
            executionTimeout
        case .unspecified, .daemon:
            nil
        }
    }
}

public struct TaskPlacementObservation: Equatable, Sendable {
    public let member: TaskMemberObservation?
    public let lifecycle: TaskLifecycleObservation
    public let inFlight: UInt64
    public let lastExecution: TaskExecutionOutcomeObservation?
    public let observedAt: Date?
    public let generation: UInt64
    public let ownedSlots: UInt64

    public init(
        member: TaskMemberObservation?,
        lifecycle: TaskLifecycleObservation,
        inFlight: UInt64,
        lastExecution: TaskExecutionOutcomeObservation?,
        observedAt: Date?,
        generation: UInt64,
        ownedSlots: UInt64 = 0
    ) {
        self.member = member
        self.lifecycle = lifecycle
        self.inFlight = inFlight
        self.lastExecution = lastExecution
        self.observedAt = observedAt
        self.generation = generation
        self.ownedSlots = ownedSlots
    }
}

public struct TaskMemberObservation: Equatable, Sendable {
    public let nodeID: UInt32
    public let role: TaskMemberRoleObservation

    public init(nodeID: UInt32, role: TaskMemberRoleObservation) {
        self.nodeID = nodeID
        self.role = role
    }
}

public struct TaskExecutionOutcomeObservation: Equatable, Sendable {
    public let result: TaskExecutionResultObservation
    public let finishedAt: Date?

    public init(result: TaskExecutionResultObservation, finishedAt: Date?) {
        self.result = result
        self.finishedAt = finishedAt
    }
}

public enum TaskKindObservation: Equatable, Sendable {
    case unspecified
    case builtin
    case command
    case php
    case js
    case lua
    case unrecognized(Int)
}

public enum TaskScopeObservation: Equatable, Sendable {
    case unspecified
    case master
    case workers
    case fleet
    case unrecognized(Int)
}

public enum TaskDispatchObservation: Equatable, Sendable {
    case unspecified
    case each
    case one
    case pool
    case unrecognized(Int)
}

public enum TaskMemberRoleObservation: Equatable, Sendable {
    case unspecified
    case master
    case worker
    case standalone
    case unrecognized(Int)
}

public enum TaskLifecycleObservation: Equatable, Sendable {
    case unspecified
    case ineligible
    case disabled
    case inactive
    case active
    case stopping
    case finished
    case missingRunner
    case unrecognized(Int)
}

public enum TaskExecutionResultObservation: Equatable, Sendable {
    case unspecified
    case succeeded
    case failed
    case cancelled
    case timedOut
    case gaveUp
    case unrecognized(Int)
}

public enum TaskRunFailureKind: Equatable, Sendable {
    case unspecified
    case io
    case cancelled
    case shutdown
    case gracefulTimeout
    case executionTimeout
    case task
    case unrecognized(Int)
}

public struct TaskRunFailure: Equatable, Sendable {
    public let kind: TaskRunFailureKind
    public let message: String

    public init(kind: TaskRunFailureKind, message: String) {
        self.kind = kind
        self.message = message
    }
}

public enum TaskRunResult: Equatable, Sendable {
    case succeeded
    case failed(TaskRunFailure)
}

public enum TaskManagementAction: Equatable, Sendable {
    case start(name: String)
    case stop(name: String)
    case reload(name: String)
    case restart(name: String)
    case run(name: String)

    public var taskName: String {
        switch self {
        case let .start(name), let .stop(name), let .reload(name),
             let .restart(name), let .run(name):
            name
        }
    }
}

public struct TaskManagementReceipt: Equatable, Sendable {
    public let action: TaskManagementAction
    public let accepted: Bool
    public let acknowledgedTaskName: String
    public let runID: UInt64?
    public let runResult: TaskRunResult?

    public init(
        action: TaskManagementAction,
        accepted: Bool,
        acknowledgedTaskName: String,
        runID: UInt64? = nil,
        runResult: TaskRunResult? = nil
    ) {
        self.action = action
        self.accepted = accepted
        self.acknowledgedTaskName = acknowledgedTaskName
        self.runID = runID
        self.runResult = runResult
    }
}
