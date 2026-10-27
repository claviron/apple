import Foundation

/// Registrar-held domains (`claviron.domains.DomainManager`).
///
/// The store view is what Claviron has recorded; the registrar view is a
/// live call to the registrar named in `domains.yaml`. Fields a registrar
/// does not report stay absent rather than defaulted.

public struct RegistrarObservation: Equatable, Sendable, Identifiable, Hashable {
    /// The key the registrar has in `domains.yaml`.
    public let name: String
    public let configured: Bool
    public let supportsRegistration: Bool
    public let supportsDns: Bool
    public let supportsGlue: Bool

    public var id: String { name }

    public init(
        name: String,
        configured: Bool,
        supportsRegistration: Bool,
        supportsDns: Bool,
        supportsGlue: Bool
    ) {
        self.name = name
        self.configured = configured
        self.supportsRegistration = supportsRegistration
        self.supportsDns = supportsDns
        self.supportsGlue = supportsGlue
    }
}

public enum DomainStatusObservation: Equatable, Sendable {
    case unspecified
    case pending
    case active
    case expired
    case suspended
    case transferring
    case failed
    case unrecognized(Int)

    public var title: String {
        switch self {
        case .unspecified: "Unspecified"
        case .pending: "Pending"
        case .active: "Active"
        case .expired: "Expired"
        case .suspended: "Suspended"
        case .transferring: "Transferring"
        case .failed: "Failed"
        case let .unrecognized(value): "Unrecognized (\(value))"
        }
    }
}

/// One row of Claviron's domain store.
public struct DomainObservation: Equatable, Sendable, Identifiable {
    public let id: UInt64
    public let name: String
    public let registrar: String
    public let registrarRef: String
    /// Empty when no DNS provider is recorded.
    public let dnsProvider: String
    public let status: DomainStatusObservation
    public let registeredAt: Date?
    public let expiresAt: Date?
    public let autoRenew: Bool
    public let renewBeforeDays: UInt32
    public let whoisPrivacy: Bool
    public let updatedAt: Date?

    public init(
        id: UInt64,
        name: String,
        registrar: String,
        registrarRef: String,
        dnsProvider: String,
        status: DomainStatusObservation,
        registeredAt: Date?,
        expiresAt: Date?,
        autoRenew: Bool,
        renewBeforeDays: UInt32,
        whoisPrivacy: Bool,
        updatedAt: Date?
    ) {
        self.id = id
        self.name = name
        self.registrar = registrar
        self.registrarRef = registrarRef
        self.dnsProvider = dnsProvider
        self.status = status
        self.registeredAt = registeredAt
        self.expiresAt = expiresAt
        self.autoRenew = autoRenew
        self.renewBeforeDays = renewBeforeDays
        self.whoisPrivacy = whoisPrivacy
        self.updatedAt = updatedAt
    }
}

/// The store's domains together with the registrars the server knows.
public struct DomainInventorySnapshot: Equatable, Sendable {
    public let registrars: [RegistrarObservation]
    public let domains: [DomainObservation]

    public init(registrars: [RegistrarObservation], domains: [DomainObservation]) {
        self.registrars = registrars
        self.domains = domains
    }
}

/// The registrar's current record for a domain.
public struct DomainRegistrarInfo: Equatable, Sendable {
    public let name: String
    public let registrar: String
    public let registrarRef: String
    public let registeredAt: Date?
    public let expiresAt: Date?
    public let autoRenew: Bool?
    public let whoisPrivacy: Bool?
    public let nameservers: [String]
    /// The registrar's own status word.
    public let registrarStatus: String

    public init(
        name: String,
        registrar: String,
        registrarRef: String,
        registeredAt: Date?,
        expiresAt: Date?,
        autoRenew: Bool?,
        whoisPrivacy: Bool?,
        nameservers: [String],
        registrarStatus: String
    ) {
        self.name = name
        self.registrar = registrar
        self.registrarRef = registrarRef
        self.registeredAt = registeredAt
        self.expiresAt = expiresAt
        self.autoRenew = autoRenew
        self.whoisPrivacy = whoisPrivacy
        self.nameservers = nameservers
        self.registrarStatus = registrarStatus
    }
}

public struct DomainNameserversSnapshot: Equatable, Sendable {
    public let name: String
    public let nameservers: [String]

    public init(name: String, nameservers: [String]) {
        self.name = name
        self.nameservers = nameservers
    }
}

/// One registrar contact as a template holds it.
public struct DomainContact: Equatable, Sendable, Hashable {
    public var firstName: String
    public var lastName: String
    public var address1: String
    public var address2: String
    public var city: String
    public var stateProvince: String
    public var postalCode: String
    public var country: String
    public var phone: String
    public var email: String

    public init(
        firstName: String = "",
        lastName: String = "",
        address1: String = "",
        address2: String = "",
        city: String = "",
        stateProvince: String = "",
        postalCode: String = "",
        country: String = "",
        phone: String = "",
        email: String = ""
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.address1 = address1
        self.address2 = address2
        self.city = city
        self.stateProvince = stateProvince
        self.postalCode = postalCode
        self.country = country
        self.phone = phone
        self.email = email
    }
}

public struct DomainContacts: Equatable, Sendable, Hashable {
    public var registrant: DomainContact
    public var admin: DomainContact?
    public var tech: DomainContact?
    public var billing: DomainContact?

    public init(
        registrant: DomainContact,
        admin: DomainContact? = nil,
        tech: DomainContact? = nil,
        billing: DomainContact? = nil
    ) {
        self.registrant = registrant
        self.admin = admin
        self.tech = tech
        self.billing = billing
    }
}

/// A registration template: contacts and nameservers a new registration
/// starts from.
public struct DomainTemplateObservation: Equatable, Sendable, Identifiable {
    public let id: UInt64
    public let name: String
    public let contacts: DomainContacts?
    public let nameservers: [String]
    public let updatedAt: Date?

    public init(
        id: UInt64,
        name: String,
        contacts: DomainContacts?,
        nameservers: [String],
        updatedAt: Date?
    ) {
        self.id = id
        self.name = name
        self.contacts = contacts
        self.nameservers = nameservers
        self.updatedAt = updatedAt
    }
}

public enum DomainManagementAction: Equatable, Sendable {
    /// Insert or replace the template under `name`.
    case putTemplate(name: String, contacts: DomainContacts, nameservers: [String])
    case removeTemplate(name: String)
    /// Record a domain the registrar already holds, from the registrar's data.
    case add(registrar: String, name: String)
    /// Re-read a stored domain from the registrar its row names and replace the row.
    case refresh(name: String)
    /// Renew at the registrar the store row names, for a number of years.
    case renew(name: String, years: UInt32)
    /// Pull the registrar-hosted records of one domain into the store.
    case syncRecords(name: String)
    /// Full replacement of the delegation set at the registrar.
    case setNameservers(registrar: String, name: String, nameservers: [String])
    /// Delegate to the nameservers the store lists for Claviron's own DNS.
    case useClavironNameservers(registrar: String, name: String)
    /// Pull the registrar's domain list into the store; nil means every
    /// configured registrar.
    case sync(registrar: String?)

    public var title: String {
        switch self {
        case .add: "Add Domain"
        case .refresh: "Refresh from Registrar"
        case .renew: "Renew Domain"
        case .syncRecords: "Sync DNS Records"
        case .setNameservers: "Set Nameservers"
        case .useClavironNameservers: "Use Claviron DNS"
        case .sync: "Sync Domains"
        case .putTemplate: "Save Template"
        case .removeTemplate: "Remove Template"
        }
    }
}

public struct DomainSyncReceipt: Equatable, Sendable {
    public let found: UInt32
    public let skipped: UInt32
    public let created: [String]
    public let updated: [String]
    public let failed: [(domain: String, message: String)]

    public init(
        found: UInt32,
        skipped: UInt32,
        created: [String],
        updated: [String],
        failed: [(domain: String, message: String)]
    ) {
        self.found = found
        self.skipped = skipped
        self.created = created
        self.updated = updated
        self.failed = failed
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.found == rhs.found
            && lhs.skipped == rhs.skipped
            && lhs.created == rhs.created
            && lhs.updated == rhs.updated
            && lhs.failed.map(\.domain) == rhs.failed.map(\.domain)
            && lhs.failed.map(\.message) == rhs.failed.map(\.message)
    }
}

public enum DomainManagementReceipt: Equatable, Sendable {
    case template(DomainTemplateObservation)
    case templateRemoved(name: String, removed: Bool)
    case domain(DomainObservation)
    case nameservers(DomainNameserversSnapshot)
    case sync(DomainSyncReceipt)
}
