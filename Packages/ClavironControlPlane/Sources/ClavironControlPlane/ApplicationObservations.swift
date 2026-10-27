import Foundation

public struct ApplicationFleetSnapshot: Equatable, Sendable {
    public let capturedAt: Date?
    public let membersExpected: UInt32
    public let membersReporting: UInt32
    public let applications: [ApplicationObservation]

    public init(
        capturedAt: Date?,
        membersExpected: UInt32,
        membersReporting: UInt32,
        applications: [ApplicationObservation]
    ) {
        self.capturedAt = capturedAt
        self.membersExpected = membersExpected
        self.membersReporting = membersReporting
        self.applications = applications
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

public struct ApplicationObservation: Equatable, Sendable {
    public let applicationID: ApplicationIDObservation?
    public let placements: [ApplicationPlacementObservation]

    /// Only show common facts when every placement actually reported the same value.
    public var description: ApplicationDescriptionObservation? {
        guard let first = placements.first?.description,
              placements.allSatisfy({ $0.description == first }) else { return nil }
        return first
    }

    public init(
        applicationID: ApplicationIDObservation?,
        placements: [ApplicationPlacementObservation]
    ) {
        self.applicationID = applicationID
        self.placements = placements
    }
}

public struct ApplicationDescriptionObservation: Equatable, Sendable {
    public let runtime: String?
    public let frameworks: [String]
    public let icon: String?
    public let runner: String?
    public let requestMode: String?

    public init(runtime: String?, frameworks: [String], runner: String?, requestMode: String?, icon: String? = nil) {
        self.runtime = runtime
        self.frameworks = frameworks
        self.icon = icon
        self.runner = runner
        self.requestMode = requestMode
    }

    init(_ value: Claviron_Applications_ApplicationDescription) {
        runtime = value.hasRuntime ? value.runtime : nil
        frameworks = value.frameworks
        icon = value.hasIcon ? value.icon : nil
        runner = value.hasRunner ? value.runner : nil
        requestMode = value.hasRequestMode ? value.requestMode : nil
    }
}

public struct ApplicationIDObservation: Equatable, Hashable, Sendable {
    public let runtime: String
    public let name: String

    public init(runtime: String, name: String) {
        self.runtime = runtime
        self.name = name
    }
}

public struct ApplicationPlacementObservation: Equatable, Sendable {
    public let member: ApplicationMemberObservation?
    public let lifecycle: ApplicationLifecycleObservation
    public let enabled: Bool
    public let generation: UInt64
    public let pool: ApplicationPoolObservation?
    public let lastError: String?
    public let lastErrorTruncated: Bool
    public let observedAt: Date?
    public let description: ApplicationDescriptionObservation?

    public init(
        member: ApplicationMemberObservation?,
        lifecycle: ApplicationLifecycleObservation,
        enabled: Bool,
        generation: UInt64,
        pool: ApplicationPoolObservation?,
        lastError: String?,
        lastErrorTruncated: Bool,
        observedAt: Date?,
        description: ApplicationDescriptionObservation? = nil
    ) {
        self.member = member
        self.lifecycle = lifecycle
        self.enabled = enabled
        self.generation = generation
        self.pool = pool
        self.lastError = lastError
        self.lastErrorTruncated = lastErrorTruncated
        self.observedAt = observedAt
        self.description = description
    }
}

public struct ApplicationPoolObservation: Equatable, Sendable {
    public let accepting: Bool?
    public let instances: UInt32
    public let ready: UInt32?
    public let busy: UInt32?
    public let retiring: UInt32?
    public let backingOff: UInt32?
    public let exhausted: UInt32?

    public init(
        accepting: Bool?,
        instances: UInt32,
        ready: UInt32?,
        busy: UInt32?,
        retiring: UInt32?,
        backingOff: UInt32?,
        exhausted: UInt32?
    ) {
        self.accepting = accepting
        self.instances = instances
        self.ready = ready
        self.busy = busy
        self.retiring = retiring
        self.backingOff = backingOff
        self.exhausted = exhausted
    }
}

public struct ApplicationMemberObservation: Equatable, Sendable {
    public let nodeID: UInt32
    public let role: ApplicationMemberRoleObservation

    public init(nodeID: UInt32, role: ApplicationMemberRoleObservation) {
        self.nodeID = nodeID
        self.role = role
    }
}

public enum ApplicationLifecycleObservation: Equatable, Sendable {
    case unspecified
    case starting
    case running
    case stopping
    case stopped
    case failed
    case unrecognized(Int)
}

public enum ApplicationMemberRoleObservation: Equatable, Sendable {
    case unspecified
    case master
    case worker
    case standalone
    case unrecognized(Int)
}

public enum ApplicationManagementAction: Equatable, Sendable {
    case start(id: ApplicationIDObservation)
    case stop(id: ApplicationIDObservation)
    case restart(id: ApplicationIDObservation)

    public var applicationID: ApplicationIDObservation {
        switch self {
        case let .start(id), let .stop(id), let .restart(id):
            id
        }
    }
}

public struct ApplicationManagementReceipt: Equatable, Sendable {
    public let action: ApplicationManagementAction
    public let accepted: Bool
    public let acknowledgedApplicationID: ApplicationIDObservation

    public init(
        action: ApplicationManagementAction,
        accepted: Bool,
        acknowledgedApplicationID: ApplicationIDObservation
    ) {
        self.action = action
        self.accepted = accepted
        self.acknowledgedApplicationID = acknowledgedApplicationID
    }
}
