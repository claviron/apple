public struct HostingInventorySnapshot: Equatable, Sendable {
    public let vhosts: [HostedVhostObservation]

    public init(vhosts: [HostedVhostObservation]) {
        self.vhosts = vhosts
    }
}

public struct HostedVhostObservation: Equatable, Sendable {
    public let vhost: VhostObservation?
    public let aliases: [VhostAliasObservation]
    public let servers: [HostingServerObservation]

    public init(
        vhost: VhostObservation?,
        aliases: [VhostAliasObservation],
        servers: [HostingServerObservation]
    ) {
        self.vhost = vhost
        self.aliases = aliases
        self.servers = servers
    }
}

public struct VhostObservation: Equatable, Sendable {
    public let id: Int32
    public let name: String
    public let enabled: Bool

    /// Host definition only; adding a dynamic alias is a separate operation.
    public let readOnly: Bool
    public let readOnlyReason: String?

    public init(id: Int32, name: String, enabled: Bool, readOnly: Bool = false, readOnlyReason: String? = nil) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.readOnly = readOnly
        self.readOnlyReason = readOnlyReason
    }
}

public struct VhostAliasObservation: Equatable, Sendable {
    public let id: Int32
    public let hostname: String
    public let enabled: Bool?

    public let readOnly: Bool
    public let readOnlyReason: String?

    public init(id: Int32, hostname: String, enabled: Bool?, readOnly: Bool = false, readOnlyReason: String? = nil) {
        self.id = id
        self.hostname = hostname
        self.enabled = enabled
        self.readOnly = readOnly
        self.readOnlyReason = readOnlyReason
    }
}

public struct HostingServerObservation: Equatable, Sendable {
    public let id: Int32
    public let name: String
    public let enabled: Bool

    public init(id: Int32, name: String, enabled: Bool) {
        self.id = id
        self.name = name
        self.enabled = enabled
    }
}

/// One alias write. The server applies each to the store and to the running
/// vhost table in the same call; there is no separate publish step.
public enum HostingManagementAction: Equatable, Sendable {
    case addAlias(vhostName: String, hostname: String)
    case removeAlias(hostname: String)
    /// Move an existing alias to another vhost.
    case replaceAlias(hostname: String, vhostName: String)

    public var title: String {
        switch self {
        case .addAlias: "Add Alias"
        case .removeAlias: "Remove Alias"
        case .replaceAlias: "Move Alias"
        }
    }
}

public enum HostingManagementReceipt: Equatable, Sendable {
    case alias(VhostAliasObservation, vhostName: String)
    /// The server's own outcome sentence, kept as it was sent.
    case operation(success: Bool, message: String?)
}
