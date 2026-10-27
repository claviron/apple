import Foundation

public struct ServiceFleetSnapshot: Equatable, Sendable {
    public let capturedAt: Date?
    public let membersExpected: UInt32
    public let membersReporting: UInt32
    public let services: [ServiceObservation]

    public init(
        capturedAt: Date?,
        membersExpected: UInt32,
        membersReporting: UInt32,
        services: [ServiceObservation]
    ) {
        self.capturedAt = capturedAt
        self.membersExpected = membersExpected
        self.membersReporting = membersReporting
        self.services = services
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

public enum FleetCoverage: Equatable, Sendable {
    case complete
    case partial
    case noReports
}

public struct ServiceObservation: Equatable, Identifiable, Sendable {
    public var id: String { name }

    public let name: String
    public let placements: [ServicePlacementObservation]

    public init(name: String, placements: [ServicePlacementObservation]) {
        self.name = name
        self.placements = placements
    }
}

public struct ServicePlacementObservation: Equatable, Sendable {
    public let member: ServiceMemberObservation?
    public let lifecycle: ServiceLifecycleObservation
    public let reloadable: Bool
    public let generation: UInt64
    public let reloadRevision: UInt64
    public let lastError: String?
    public let lastErrorTruncated: Bool
    public let lastReloadError: String?
    public let lastReloadErrorTruncated: Bool
    public let observedAt: Date?
    public let startPolicy: ServiceStartPolicyObservation
    public let activeExecutions: UInt64?
    public let dispatch: ServiceDispatchObservation

    public init(
        member: ServiceMemberObservation?,
        lifecycle: ServiceLifecycleObservation,
        reloadable: Bool,
        generation: UInt64,
        reloadRevision: UInt64,
        lastError: String?,
        lastErrorTruncated: Bool,
        lastReloadError: String?,
        lastReloadErrorTruncated: Bool,
        observedAt: Date?,
        startPolicy: ServiceStartPolicyObservation,
        activeExecutions: UInt64? = nil,
        dispatch: ServiceDispatchObservation = .unspecified
    ) {
        self.member = member
        self.lifecycle = lifecycle
        self.reloadable = reloadable
        self.generation = generation
        self.reloadRevision = reloadRevision
        self.lastError = lastError
        self.lastErrorTruncated = lastErrorTruncated
        self.lastReloadError = lastReloadError
        self.lastReloadErrorTruncated = lastReloadErrorTruncated
        self.observedAt = observedAt
        self.startPolicy = startPolicy
        self.activeExecutions = activeExecutions
        self.dispatch = dispatch
    }
}

public struct ServiceMemberObservation: Equatable, Sendable {
    public let nodeID: UInt32
    public let role: ServiceMemberRoleObservation

    public init(nodeID: UInt32, role: ServiceMemberRoleObservation) {
        self.nodeID = nodeID
        self.role = role
    }
}

public enum ServiceLifecycleObservation: Equatable, Sendable {
    case unspecified
    case running
    case stopping
    case stopped
    case failed
    case unrecognized(Int)
}

public enum ServiceDispatchObservation: Equatable, Sendable {
    case unspecified
    case each
    case one
    case pool
    case unrecognized(Int)
}

public enum ServiceStartPolicyObservation: Equatable, Sendable {
    case unspecified
    case automatic
    case manual
    case unavailable
    case unrecognized(Int)
}

public enum ServiceMemberRoleObservation: Equatable, Sendable {
    case unspecified
    case master
    case worker
    case standalone
    case unrecognized(Int)
}

public enum ServiceManagementAction: Equatable, Sendable {
    case start(name: String)
    case stop(name: String)
    case reload(name: String)
    case restart(name: String)

    public var serviceName: String {
        switch self {
        case let .start(name), let .stop(name), let .reload(name), let .restart(name):
            name
        }
    }
}

public struct ServiceManagementReceipt: Equatable, Sendable {
    public let action: ServiceManagementAction
    public let accepted: Bool
    public let acknowledgedServiceName: String

    public init(
        action: ServiceManagementAction,
        accepted: Bool,
        acknowledgedServiceName: String
    ) {
        self.action = action
        self.accepted = accepted
        self.acknowledgedServiceName = acknowledgedServiceName
    }
}
