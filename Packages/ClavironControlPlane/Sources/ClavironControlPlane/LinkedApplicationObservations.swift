import Foundation

/// Independently hosted applications reached through a reported connection method.
/// Orbit Link is the current implementation, not the application's execution model.
///
/// A runner starts on its own and joins the Link; the edge does not launch or
/// stop its process. What the edge observes is the Link: whether the runner's
/// name is reachable and through which lanes. What the runner hosts is its own
/// report, absent until it has sent one — absent is not stopped.
public struct LinkedApplicationSnapshot: Equatable, Sendable {
    public let capturedAt: Date?
    public let applications: [LinkedApplicationObservation]

    public init(capturedAt: Date?, applications: [LinkedApplicationObservation]) {
        self.capturedAt = capturedAt
        self.applications = applications
    }

    init(_ value: Claviron_LinkedApplications_ListLinkedApplicationsResponse) {
        capturedAt = value.hasCapturedAt ? value.capturedAt.date : nil
        applications = value.applications.map(LinkedApplicationObservation.init)
    }
}

/// The Link destination: a fleet and the name a runner advertises in it. A
/// name is unique only within its fleet.
public struct LinkedApplicationIDObservation: Equatable, Hashable, Sendable {
    public let fleetName: String
    public let name: String
    public let transport: String

    public init(fleetName: String, name: String, transport: String = "") {
        self.fleetName = fleetName
        self.name = name
        self.transport = transport
    }

    init(_ value: Claviron_LinkedApplications_LinkedApplicationId) {
        fleetName = value.fleetName
        name = value.name
        transport = value.transport
    }

    var message: Claviron_LinkedApplications_LinkedApplicationId {
        var id = Claviron_LinkedApplications_LinkedApplicationId()
        id.fleetName = fleetName
        id.name = name
        id.transport = transport
        return id
    }
}

public struct LinkedApplicationObservation: Equatable, Sendable {
    public let id: LinkedApplicationIDObservation?
    /// Advertised by the runner's lanes; empty if it has never joined.
    public let runtime: String
    public var description: ApplicationDescriptionObservation? {
        guard let applications = hosted?.applications,
              let first = applications.first?.description,
              applications.allSatisfy({ $0.description == first }) else { return nil }
        return first
    }

    public var transport: String { id?.transport ?? "" }
    public let link: LinkReachabilityObservation
    public let connectedLanes: UInt32
    public let lanes: [LinkedLaneObservation]
    /// The runner's own application report; nil until one has arrived.
    public let hosted: ApplicationFleetSnapshot?

    public init(
        id: LinkedApplicationIDObservation?,
        runtime: String,
        link: LinkReachabilityObservation,
        connectedLanes: UInt32,
        lanes: [LinkedLaneObservation],
        hosted: ApplicationFleetSnapshot?
    ) {
        self.id = id
        self.runtime = runtime
        self.link = link
        self.connectedLanes = connectedLanes
        self.lanes = lanes
        self.hosted = hosted
    }

    init(_ value: Claviron_LinkedApplications_LinkedApplicationStatus) {
        id = value.hasInfo && value.info.hasID
            ? LinkedApplicationIDObservation(value.info.id)
            : nil
        runtime = value.hasInfo ? value.info.runtime : ""
        link = LinkReachabilityObservation(value.link)
        connectedLanes = value.connectedLanes
        lanes = value.lanes.map(LinkedLaneObservation.init)
        hosted = value.hasHosted ? ApplicationFleetSnapshot(
            capturedAt: value.hosted.hasCapturedAt ? value.hosted.capturedAt.date : nil,
            membersExpected: value.hosted.membersExpected,
            membersReporting: value.hosted.membersReporting,
            applications: value.hosted.applications.map(DirectClavironClient.applicationObservation)
        ) : nil
    }
}

/// One connected worker lane serving the runner's name.
public struct LinkedLaneObservation: Equatable, Sendable {
    public let lane: UInt32
    public let pid: UInt32?
    public let incarnation: UInt64

    public init(lane: UInt32, pid: UInt32?, incarnation: UInt64) {
        self.lane = lane
        self.pid = pid
        self.incarnation = incarnation
    }

    init(_ value: Claviron_LinkedApplications_LinkedApplicationLane) {
        lane = value.lane
        pid = value.hasPid ? value.pid : nil
        incarnation = value.incarnation
    }
}

public enum LinkReachabilityObservation: Equatable, Sendable {
    case unspecified
    case connected
    case disconnected
    case unrecognized(Int)

    init(_ value: Claviron_LinkedApplications_LinkReachability) {
        switch value {
        case .unspecified: self = .unspecified
        case .connected: self = .connected
        case .disconnected: self = .disconnected
        case let .UNRECOGNIZED(raw): self = .unrecognized(raw)
        }
    }
}

/// Forwarded to the runner through its Link inbox. Lifecycle actions name one
/// application the runner hosts; a named command means what the runner says.
public enum LinkedApplicationAction: Equatable, Sendable {
    case start(link: LinkedApplicationIDObservation, application: ApplicationIDObservation)
    case stop(link: LinkedApplicationIDObservation, application: ApplicationIDObservation)
    case restart(link: LinkedApplicationIDObservation, application: ApplicationIDObservation)
    case command(link: LinkedApplicationIDObservation, name: String, payload: Data)

    public var link: LinkedApplicationIDObservation {
        switch self {
        case let .start(link, _), let .stop(link, _), let .restart(link, _),
             let .command(link, _, _):
            link
        }
    }

    public var application: ApplicationIDObservation? {
        switch self {
        case let .start(_, application), let .stop(_, application),
             let .restart(_, application):
            application
        case .command:
            nil
        }
    }
}

/// Accepted means one live Link inbox took the frame — not that the runner
/// carried it out. A later status shows the result.
public struct LinkedApplicationReceipt: Equatable, Sendable {
    public let action: LinkedApplicationAction
    public let accepted: Bool
    public let acknowledgedLink: LinkedApplicationIDObservation?

    public init(
        action: LinkedApplicationAction,
        accepted: Bool,
        acknowledgedLink: LinkedApplicationIDObservation?
    ) {
        self.action = action
        self.accepted = accepted
        self.acknowledgedLink = acknowledgedLink
    }
}
