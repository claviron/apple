/// The operator-managed authoritative DNS store (`claviron.dns.DnsManager`).
///
/// Configurations mirror the protocol's full-replacement writes: an update
/// carries every field, never a partial patch. Optional values keep proto3
/// presence, so an SRV weight of zero stays distinct from an absent weight.

public struct DnsInventorySnapshot: Equatable, Sendable {
    public let zones: [DnsZoneObservation]

    public init(zones: [DnsZoneObservation]) {
        self.zones = zones
    }
}

public struct DnsZoneObservation: Equatable, Sendable, Identifiable {
    public let id: UInt64
    public let configuration: DnsZoneConfiguration?
    /// Advanced by the store with each zone or record mutation.
    public let serial: UInt32

    public init(id: UInt64, configuration: DnsZoneConfiguration?, serial: UInt32) {
        self.id = id
        self.configuration = configuration
        self.serial = serial
    }
}

public struct DnsZoneConfiguration: Equatable, Sendable {
    public var domain: String
    public var soa: DnsSOAConfiguration?
    public var enabled: Bool

    public init(domain: String, soa: DnsSOAConfiguration?, enabled: Bool) {
        self.domain = domain
        self.soa = soa
        self.enabled = enabled
    }
}

public struct DnsSOAConfiguration: Equatable, Sendable {
    public var mname: String
    public var rname: String
    public var refresh: UInt32
    public var retry: UInt32
    public var expire: UInt32
    public var minimum: UInt32

    public init(
        mname: String,
        rname: String,
        refresh: UInt32,
        retry: UInt32,
        expire: UInt32,
        minimum: UInt32
    ) {
        self.mname = mname
        self.rname = rname
        self.refresh = refresh
        self.retry = retry
        self.expire = expire
        self.minimum = minimum
    }
}

public struct DnsRecordsSnapshot: Equatable, Sendable {
    public let zone: String
    public let records: [DnsRecordObservation]

    public init(zone: String, records: [DnsRecordObservation]) {
        self.zone = zone
        self.records = records
    }
}

public struct DnsRecordObservation: Equatable, Sendable, Identifiable {
    public let id: UInt64
    public let zone: String
    public let configuration: DnsRecordConfiguration?

    public init(id: UInt64, zone: String, configuration: DnsRecordConfiguration?) {
        self.id = id
        self.zone = zone
        self.configuration = configuration
    }
}

public struct DnsRecordConfiguration: Equatable, Sendable {
    public var name: String
    public var type: String
    public var value: String
    public var ttl: UInt32
    public var priority: UInt32?
    public var weight: UInt32?
    public var port: UInt32?
    public var enabled: Bool

    public init(
        name: String,
        type: String,
        value: String,
        ttl: UInt32,
        priority: UInt32?,
        weight: UInt32?,
        port: UInt32?,
        enabled: Bool
    ) {
        self.name = name
        self.type = type
        self.value = value
        self.ttl = ttl
        self.priority = priority
        self.weight = weight
        self.port = port
        self.enabled = enabled
    }
}

public enum DnsManagementAction: Equatable, Sendable {
    case addZone(DnsZoneConfiguration)
    case updateZone(id: UInt64, DnsZoneConfiguration)
    /// Without `cascade` the store refuses a zone that still has records.
    case removeZone(id: UInt64, cascade: Bool)
    case addRecord(zone: String, DnsRecordConfiguration)
    case updateRecord(id: UInt64, DnsRecordConfiguration)
    case removeRecord(id: UInt64)
    case reload

    public var title: String {
        switch self {
        case .addZone: "Add Zone"
        case .updateZone: "Update Zone"
        case .removeZone: "Remove Zone"
        case .addRecord: "Add Record"
        case .updateRecord: "Update Record"
        case .removeRecord: "Remove Record"
        case .reload: "Reload DNS"
        }
    }
}

public enum DnsManagementReceipt: Equatable, Sendable {
    /// A write proves a database commit, not fleet-wide serving reload.
    case zone(DnsZoneObservation)
    case record(DnsRecordObservation, zoneSerial: UInt32)
    /// `zoneSerial` is absent when the zone itself was removed.
    case removed(zone: String, zoneSerial: UInt32?)
    /// Acceptance only; it does not claim every fleet member reloaded.
    case reload(accepted: Bool)
}
