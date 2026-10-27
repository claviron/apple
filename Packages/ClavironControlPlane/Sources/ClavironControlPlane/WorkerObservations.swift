import Foundation

public struct WorkerFleetSnapshot: Equatable, Sendable {
    public let capturedAt: Date?
    public let workersExpected: UInt32
    /// The exact master process that published this view. Absent only before
    /// the master has established itself.
    public let master: MasterIdentityObservation?
    public let fleetMode: FleetModeObservation
    /// The source the publishing master was built from, when it reported one.
    public let build: BuildIdentityObservation?
    public let workers: [WorkerObservation]

    public init(
        capturedAt: Date?,
        workersExpected: UInt32,
        master: MasterIdentityObservation? = nil,
        fleetMode: FleetModeObservation = .unspecified,
        build: BuildIdentityObservation? = nil,
        workers: [WorkerObservation]
    ) {
        self.capturedAt = capturedAt
        self.workersExpected = workersExpected
        self.master = master
        self.fleetMode = fleetMode
        self.build = build
        self.workers = workers
    }

    public var coverage: FleetCoverage {
        if workersExpected == 0 {
            workers.isEmpty ? .complete : .partial
        } else if workers.isEmpty {
            .noReports
        } else if workers.count == Int(workersExpected) {
            .complete
        } else {
            .partial
        }
    }
}

/// A PID together with the kernel start stamp of the process that holds it:
/// the exact process, safe against PID reuse.
public struct ProcessIdentityObservation: Equatable, Hashable, Sendable {
    public let pid: UInt32
    /// Raw and platform-specific. Compare it; never present it as a date.
    public let startedAt: UInt64

    public init(pid: UInt32, startedAt: UInt64) {
        self.pid = pid
        self.startedAt = startedAt
    }
}

public struct MasterIdentityObservation: Equatable, Sendable {
    public let process: ProcessIdentityObservation?
    /// Counts master boots on the fleet's shared memory; orders masters of one
    /// instance where two process identities alone cannot say which is newer.
    public let generation: UInt64

    public init(process: ProcessIdentityObservation?, generation: UInt64) {
        self.process = process
        self.generation = generation
    }
}

public struct BuildIdentityObservation: Equatable, Sendable {
    /// The short git hash, empty when the build had no repository.
    public let revision: String
    /// Tracked files carried uncommitted changes.
    public let dirty: Bool

    public init(revision: String, dirty: Bool) {
        self.revision = revision
        self.dirty = dirty
    }
}

public struct WorkerObservation: Equatable, Identifiable, Sendable {
    public var id: UInt32 { workerID }

    public let workerID: UInt32
    /// The master's own derivation from `phase` and `desired`.
    public let lifecycle: WorkerLifecycleObservation
    /// How the publishing master owns the live process in this slot.
    public let ownership: WorkerOwnershipObservation
    /// The exact process in the slot when one is known: the handle the master
    /// owns or, for a slot it could not claim, the presence that occupies it.
    public let process: ProcessIdentityObservation?
    public let uptime: ProtobufDurationObservation?
    public let recoveryAttempts: UInt32
    public let reloadRevision: UInt64
    public let incarnation: UInt64
    /// What the master has observed of the process, and for how long.
    public let phase: WorkerPhaseObservation
    public let phaseAge: ProtobufDurationObservation?
    /// What the master wants of the slot, and for how long.
    public let desired: WorkerDesiredStateObservation
    public let desiredAge: ProtobufDurationObservation?
    /// The lifecycle operation acting on the slot, if one is.
    public let operation: WorkerOperationObservation?
    /// Since the last heartbeat the master accepted; absent until the first.
    public let heartbeatAge: ProtobufDurationObservation?
    /// Why boot reconciliation refused the slot; nil when it is not blocked.
    public let blockReason: WorkerBlockReasonObservation?

    public var processID: UInt32? { process?.pid }

    public init(
        workerID: UInt32,
        lifecycle: WorkerLifecycleObservation,
        ownership: WorkerOwnershipObservation,
        process: ProcessIdentityObservation?,
        uptime: ProtobufDurationObservation?,
        recoveryAttempts: UInt32,
        reloadRevision: UInt64,
        incarnation: UInt64,
        phase: WorkerPhaseObservation = .unspecified,
        phaseAge: ProtobufDurationObservation? = nil,
        desired: WorkerDesiredStateObservation = .unspecified,
        desiredAge: ProtobufDurationObservation? = nil,
        operation: WorkerOperationObservation? = nil,
        heartbeatAge: ProtobufDurationObservation? = nil,
        blockReason: WorkerBlockReasonObservation? = nil
    ) {
        self.workerID = workerID
        self.lifecycle = lifecycle
        self.ownership = ownership
        self.process = process
        self.uptime = uptime
        self.recoveryAttempts = recoveryAttempts
        self.reloadRevision = reloadRevision
        self.incarnation = incarnation
        self.phase = phase
        self.phaseAge = phaseAge
        self.desired = desired
        self.desiredAge = desiredAge
        self.operation = operation
        self.heartbeatAge = heartbeatAge
        self.blockReason = blockReason
    }
}

public struct ProtobufDurationObservation: Equatable, Sendable {
    public let seconds: Int64
    public let nanoseconds: Int32

    public init(seconds: Int64, nanoseconds: Int32) {
        self.seconds = seconds
        self.nanoseconds = nanoseconds
    }
}

public enum WorkerLifecycleObservation: Equatable, Sendable {
    case unspecified
    case starting
    case running
    case reloading
    case stopping
    case stopped
    case exited
    case crashed
    case unclaimed
    case unrecognized(Int)
}

public enum WorkerOwnershipObservation: Equatable, Sendable {
    case unspecified
    case unowned
    case spawned
    case adopted
    case unrecognized(Int)
}

public enum FleetModeObservation: Equatable, Sendable {
    case unspecified
    case running
    /// Shutdown has latched in the master: no operation is accepted and every
    /// live slot is draining.
    case shuttingDown
    case unrecognized(Int)
}

/// What the master has observed of a slot's process. Never desired state: a
/// draining worker is still `running` here until it is seen to exit.
public enum WorkerPhaseObservation: Equatable, Sendable {
    case unspecified
    case unclaimed
    case ownershipPending
    case reconciliationBlocked
    case starting
    case running
    case reloading
    case drainAcknowledged
    case teardownCompleted
    case exitedPlanned
    case exitedFailed
    case unrecognized(Int)
}

public enum WorkerDesiredStateObservation: Equatable, Sendable {
    /// The master set no case.
    case unspecified
    case ensureRunning
    case stopped
    case drain(reason: WorkerDrainReasonObservation, afterExit: WorkerExitDispositionObservation)
}

public enum WorkerDrainReasonObservation: Equatable, Sendable {
    case unspecified
    case shutdown
    case scaleDown
    case rotation
    case heartbeatTimeout
    case manualStop
    case rollingRestart
    case unrecognized(Int)
}

/// What a slot becomes once the process it is draining has exited.
public enum WorkerExitDispositionObservation: Equatable, Sendable {
    case unspecified
    case stayStopped
    case replace
    case removeSlot
    case finishFleetShutdown
    case unrecognized(Int)
}

/// The operation acting on a slot: by authority, the fleet shutdown outranks a
/// fleet-wide operation, which outranks the slot's own.
public struct WorkerOperationObservation: Equatable, Sendable {
    /// The master's number for the operation, unique within one master lifetime.
    public let id: UInt64
    public let kind: WorkerOperationKindObservation
    public let origin: WorkerOperationOriginObservation
    public let age: ProtobufDurationObservation?

    public init(
        id: UInt64,
        kind: WorkerOperationKindObservation,
        origin: WorkerOperationOriginObservation,
        age: ProtobufDurationObservation?
    ) {
        self.id = id
        self.kind = kind
        self.origin = origin
        self.age = age
    }
}

public enum WorkerOperationKindObservation: Equatable, Sendable {
    case unspecified
    case start
    case stop
    case restart
    case reload
    case rotation
    case heartbeatRecovery
    case crashRecovery
    case reloadAll
    case restartAll
    case resize(from: UInt32, to: UInt32)
    case configReload
    case fleetShutdown
    case unrecognized(Int)
}

/// Who asked for the operation. Distinct from its kind: a rolling restart is
/// one whether the GUI, claviron-client or a signal asked.
public enum WorkerOperationOriginObservation: Equatable, Sendable {
    /// The master set no case.
    case unspecified
    /// A management command: the worker whose control plane relayed it, when
    /// one did, and the submission key its response carried.
    case management(viaWorker: UInt32?, submissionKey: UInt64)
    /// The supervisor's own monitor: rotation, heartbeat or crash recovery.
    case supervisor
    /// A process signal to the master.
    case signal
}

/// Why boot reconciliation refused a slot whose lane carried typed presence.
public enum WorkerBlockReasonObservation: Equatable, Sendable {
    case stalePresence
    case workerNotRunning
    case workerBusy
    case unknownMaster
    case masterStillAlive
    case masterNotOlder
    case identityChanged
    case unrecognized(Int)
}

public enum WorkerManagementAction: Equatable, Sendable {
    case start(workerID: UInt32)
    case stop(workerID: UInt32)
    case reload(workerID: UInt32)
    case restart(workerID: UInt32)
    case reloadAll
    case restartAll
    case add
    case remove
}

/// What the control plane answered when a command was submitted. Acceptance
/// means the command was validated and published to the master; it is not the
/// master's acknowledgement, and completion is proven only by observing the
/// postcondition on a later snapshot.
public struct WorkerManagementReceipt: Equatable, Sendable {
    public let action: WorkerManagementAction
    public let accepted: Bool
    /// The key of this one submission. While the master runs the operation it
    /// opened for it, the operation's management origin carries the same key.
    /// A refused submission opens nothing and a repeated click is a new key,
    /// so this correlates; it neither acknowledges nor deduplicates.
    public let submissionKey: UInt64?
    public let acknowledgedWorkerID: UInt32?
    public let previousWorkerCount: UInt32?
    public let targetWorkerCount: UInt32?

    public init(
        action: WorkerManagementAction,
        accepted: Bool,
        submissionKey: UInt64? = nil,
        acknowledgedWorkerID: UInt32? = nil,
        previousWorkerCount: UInt32? = nil,
        targetWorkerCount: UInt32? = nil
    ) {
        self.action = action
        self.accepted = accepted
        self.submissionKey = submissionKey
        self.acknowledgedWorkerID = acknowledgedWorkerID
        self.previousWorkerCount = previousWorkerCount
        self.targetWorkerCount = targetWorkerCount
    }
}
