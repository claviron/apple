import ClavironControlPlane
import SwiftUI

/// How the worker observation reads on screen. Labels only: no rule lives
/// here, the master derives the lifecycle and the action model proves
/// completion.
extension WorkerObservation {
    /// The process in this slot was accepted from an earlier master rather
    /// than spawned by the current one. Shown in yellow wherever the slot's
    /// status appears, so an operator sees at a glance which workers the
    /// running master did not start.
    var isAdopted: Bool {
        ownership == .adopted
    }

    var statusColor: Color {
        isAdopted ? .yellow : lifecycle.color
    }

    /// The marker shown next to the name in the concise list.
    var listMarker: String? {
        isAdopted ? WorkerOwnershipObservation.adopted.title : nil
    }
}

extension WorkerLifecycleObservation {
    var title: String {
        switch self {
        case .unspecified:
            "Unspecified"
        case .starting:
            "Starting"
        case .running:
            "Running"
        case .reloading:
            "Reloading"
        case .stopping:
            "Stopping"
        case .stopped:
            "Stopped"
        case .exited:
            "Exited"
        case .crashed:
            "Crashed"
        case .unclaimed:
            "Unclaimed"
        case let .unrecognized(rawValue):
            "Unknown (\(rawValue))"
        }
    }

    var color: Color {
        switch self {
        case .running:
            .green
        case .starting, .reloading, .stopping, .unclaimed:
            .orange
        case .crashed:
            .red
        case .unspecified, .stopped, .exited, .unrecognized:
            .secondary
        }
    }
}

extension WorkerOwnershipObservation {
    var title: String {
        switch self {
        case .unspecified:
            "Unspecified"
        case .unowned:
            "Unowned"
        case .spawned:
            "Spawned"
        case .adopted:
            "Adopted"
        case let .unrecognized(rawValue):
            "Unknown (\(rawValue))"
        }
    }

    var color: Color {
        switch self {
        case .adopted:
            .yellow
        case .unspecified, .unowned, .spawned, .unrecognized:
            .secondary
        }
    }
}

extension FleetModeObservation {
    var title: String {
        switch self {
        case .unspecified:
            "Unspecified"
        case .running:
            "Running"
        case .shuttingDown:
            "Shutting down"
        case let .unrecognized(rawValue):
            "Unknown (\(rawValue))"
        }
    }
}

extension WorkerPhaseObservation {
    var title: String {
        switch self {
        case .unspecified:
            "Unspecified"
        case .unclaimed:
            "Unclaimed"
        case .ownershipPending:
            "Ownership pending"
        case .reconciliationBlocked:
            "Reconciliation blocked"
        case .starting:
            "Starting"
        case .running:
            "Running"
        case .reloading:
            "Reloading"
        case .drainAcknowledged:
            "Drain acknowledged"
        case .teardownCompleted:
            "Teardown completed"
        case .exitedPlanned:
            "Exited as planned"
        case .exitedFailed:
            "Exited unexpectedly"
        case let .unrecognized(rawValue):
            "Unknown (\(rawValue))"
        }
    }
}

extension WorkerDesiredStateObservation {
    var title: String {
        switch self {
        case .unspecified:
            "Unspecified"
        case .ensureRunning:
            "Ensure running"
        case .stopped:
            "Stopped"
        case let .drain(reason, afterExit):
            "Drain for \(reason.title), then \(afterExit.title)"
        }
    }
}

extension WorkerDrainReasonObservation {
    var title: String {
        switch self {
        case .unspecified:
            "an unspecified reason"
        case .shutdown:
            "shutdown"
        case .scaleDown:
            "scale-down"
        case .rotation:
            "rotation"
        case .heartbeatTimeout:
            "heartbeat timeout"
        case .manualStop:
            "manual stop"
        case .rollingRestart:
            "rolling restart"
        case let .unrecognized(rawValue):
            "unknown reason (\(rawValue))"
        }
    }
}

extension WorkerExitDispositionObservation {
    var title: String {
        switch self {
        case .unspecified:
            "unspecified"
        case .stayStopped:
            "stay stopped"
        case .replace:
            "replace"
        case .removeSlot:
            "remove the slot"
        case .finishFleetShutdown:
            "finish the fleet shutdown"
        case let .unrecognized(rawValue):
            "unknown (\(rawValue))"
        }
    }
}

extension WorkerOperationKindObservation {
    var title: String {
        switch self {
        case .unspecified:
            "Unspecified"
        case .start:
            "Start"
        case .stop:
            "Stop"
        case .restart:
            "Restart"
        case .reload:
            "Reload"
        case .rotation:
            "Rotation"
        case .heartbeatRecovery:
            "Heartbeat recovery"
        case .crashRecovery:
            "Crash recovery"
        case .reloadAll:
            "Reload all"
        case .restartAll:
            "Restart all"
        case let .resize(from, to):
            "Resize \(from) to \(to)"
        case .configReload:
            "Configuration reload"
        case .fleetShutdown:
            "Fleet shutdown"
        case let .unrecognized(rawValue):
            "Unknown (\(rawValue))"
        }
    }
}

extension WorkerOperationOriginObservation {
    var title: String {
        switch self {
        case .unspecified:
            "Unspecified"
        case let .management(viaWorker, _):
            viaWorker.map { "Management via worker \($0)" } ?? "Management"
        case .supervisor:
            "Supervisor"
        case .signal:
            "Signal"
        }
    }

    var submissionKey: UInt64? {
        if case let .management(_, submissionKey) = self {
            return submissionKey
        }
        return nil
    }
}

extension WorkerBlockReasonObservation {
    var title: String {
        switch self {
        case .stalePresence:
            "Stale presence"
        case .workerNotRunning:
            "Worker not running"
        case .workerBusy:
            "Worker busy"
        case .unknownMaster:
            "Unknown master"
        case .masterStillAlive:
            "Master still alive"
        case .masterNotOlder:
            "Master not older"
        case .identityChanged:
            "Identity changed"
        case let .unrecognized(rawValue):
            "Unknown (\(rawValue))"
        }
    }
}

extension ProcessIdentityObservation {
    /// The raw kernel stamp, shown as the opaque value it is.
    var startStampFormatted: String {
        "0x" + String(startedAt, radix: 16)
    }
}

extension BuildIdentityObservation {
    var formatted: String {
        let revision = revision.isEmpty ? "No repository" : revision
        return dirty ? "\(revision) (dirty)" : revision
    }
}

extension UInt64 {
    /// The sixteen hex digits claviron-client prints for the same key.
    var submissionKeyFormatted: String {
        String(format: "%016llx", self)
    }
}

extension ProtobufDurationObservation {
    var formatted: String {
        guard seconds >= 0, nanoseconds >= 0 else {
            return "\(seconds)s \(nanoseconds)ns"
        }

        let totalSeconds = seconds + Int64(nanoseconds) / 1_000_000_000
        let days = totalSeconds / 86_400
        let hours = totalSeconds % 86_400 / 3_600
        let minutes = totalSeconds % 3_600 / 60
        let remainingSeconds = totalSeconds % 60
        var components: [String] = []
        if days > 0 { components.append("\(days)d") }
        if hours > 0 { components.append("\(hours)h") }
        if minutes > 0 { components.append("\(minutes)m") }
        components.append("\(remainingSeconds)s")
        return components.joined(separator: " ")
    }

    /// An age: sub-second ages keep their milliseconds, since a heartbeat or
    /// an operation that is 700 ms old is not "0s" old.
    var formattedAge: String {
        if seconds == 0, nanoseconds >= 0 {
            return "\(nanoseconds / 1_000_000) ms"
        }
        return formatted
    }
}
