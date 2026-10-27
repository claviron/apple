import Foundation
import SwiftProtobuf

/// Server-reported connection identity. Missing observations remain missing;
/// a responding worker's process clock never stands in for the master clock.
public struct ServerInfoSnapshot: Equatable, Sendable {
    public let name: String
    public let environment: String
    public let fleetName: String?
    public let hostname: String
    public let clavironVersion: String
    public let applicationVersion: String?
    public let instanceID: String?
    public let workersDesired: UInt32?
    public let workersRunning: UInt32?
    public let workersCapturedAt: Date?
    public let startedAt: Date?
    public let uptime: ProtobufDurationObservation?
    public let reloadRevision: UInt64?
    public let respondingProcess: ServerProcessInfo?
    public let capabilities: [String]
    public let capturedAt: Date?

    public init(
        name: String, environment: String, hostname: String, clavironVersion: String,
        fleetName: String? = nil, applicationVersion: String? = nil,
        instanceID: String? = nil, workersDesired: UInt32? = nil,
        workersRunning: UInt32? = nil, workersCapturedAt: Date? = nil,
        startedAt: Date? = nil, uptime: ProtobufDurationObservation? = nil,
        reloadRevision: UInt64? = nil, respondingProcess: ServerProcessInfo? = nil,
        capabilities: [String] = [], capturedAt: Date? = nil
    ) {
        self.name = name
        self.environment = environment
        self.hostname = hostname
        self.clavironVersion = clavironVersion
        self.fleetName = fleetName
        self.applicationVersion = applicationVersion
        self.instanceID = instanceID
        self.workersDesired = workersDesired
        self.workersRunning = workersRunning
        self.workersCapturedAt = workersCapturedAt
        self.startedAt = startedAt
        self.uptime = uptime
        self.reloadRevision = reloadRevision
        self.respondingProcess = respondingProcess
        self.capabilities = capabilities
        self.capturedAt = capturedAt
    }

    init(_ value: Claviron_Server_InfoResponse) {
        name = value.name
        environment = value.environment
        fleetName = value.hasFleetName ? value.fleetName : nil
        hostname = value.hostname
        clavironVersion = value.clavironVersion
        applicationVersion = value.hasApplicationVersion ? value.applicationVersion : nil
        instanceID = value.hasInstanceID ? value.instanceID : nil
        workersDesired = value.hasWorkersDesired ? value.workersDesired : nil
        workersRunning = value.hasWorkersRunning ? value.workersRunning : nil
        workersCapturedAt = value.hasWorkersCapturedAt ? value.workersCapturedAt.date : nil
        startedAt = value.hasStartedAt ? value.startedAt.date : nil
        uptime = value.hasUptime ? ProtobufDurationObservation(
            seconds: value.uptime.seconds, nanoseconds: value.uptime.nanos
        ) : nil
        reloadRevision = value.hasReloadRevision ? value.reloadRevision : nil
        respondingProcess = value.hasRespondingProcess ? ServerProcessInfo(value.respondingProcess) : nil
        capabilities = value.capabilities
        capturedAt = value.hasCapturedAt ? value.capturedAt.date : nil
    }
}

public struct ServerProcessInfo: Equatable, Sendable {
    public let runMode: ServerRunMode
    public let pid: UInt32
    public let workerID: UInt32?
    public let startedAt: Date?
    public let uptime: ProtobufDurationObservation?
    public let reloadRevision: UInt64

    init(_ value: Claviron_Server_ProcessInfo) {
        runMode = switch value.runMode {
        case .unspecified: .unspecified
        case .master: .master
        case .worker: .worker
        case .standalone: .standalone
        case let .UNRECOGNIZED(raw): .unrecognized(raw)
        }
        pid = value.pid
        workerID = value.hasWorkerID ? value.workerID : nil
        startedAt = value.hasStartedAt ? value.startedAt.date : nil
        uptime = value.hasUptime ? ProtobufDurationObservation(
            seconds: value.uptime.seconds, nanoseconds: value.uptime.nanos
        ) : nil
        reloadRevision = value.reloadRevision
    }
}

public enum ServerRunMode: Equatable, Sendable {
    case unspecified, master, worker, standalone
    case unrecognized(Int)

    public var title: String {
        switch self {
        case .unspecified: "Not reported"
        case .master: "Master"
        case .worker: "Worker"
        case .standalone: "Standalone"
        case let .unrecognized(raw): "Unknown (\(raw))"
        }
    }
}
