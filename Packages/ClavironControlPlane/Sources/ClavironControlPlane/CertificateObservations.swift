import Foundation

public struct CertificateInventorySnapshot: Equatable, Sendable {
    public let certificates: [HostedCertificateObservation]

    public init(certificates: [HostedCertificateObservation]) {
        self.certificates = certificates
    }
}

public struct HostedCertificateObservation: Equatable, Sendable {
    public let certificate: CertificateObservation?
    public let servers: [CertificateServerObservation]

    public init(
        certificate: CertificateObservation?,
        servers: [CertificateServerObservation]
    ) {
        self.certificate = certificate
        self.servers = servers
    }
}

public struct CertificateObservation: Equatable, Sendable {
    public let id: Int32
    public let commonName: String
    public let aliases: [String]
    public let issuedAt: ProtobufTimestampObservation?
    public let expiresAt: ProtobufTimestampObservation?
    public let updatedAt: ProtobufTimestampObservation?
    public let enabled: Bool
    public let revokedAt: ProtobufTimestampObservation?
    public let kind: ReportedLocalCertificateKind

    public init(
        id: Int32,
        commonName: String,
        aliases: [String],
        issuedAt: ProtobufTimestampObservation?,
        expiresAt: ProtobufTimestampObservation?,
        updatedAt: ProtobufTimestampObservation?,
        enabled: Bool,
        kind: ReportedLocalCertificateKind = .unspecified,
        revokedAt: ProtobufTimestampObservation? = nil
    ) {
        self.id = id
        self.commonName = commonName
        self.aliases = aliases
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.updatedAt = updatedAt
        self.enabled = enabled
        self.revokedAt = revokedAt
        self.kind = kind
    }
}

public struct CertificateServerObservation: Equatable, Sendable {
    public let id: Int32
    public let name: String
    public let enabled: Bool

    public init(id: Int32, name: String, enabled: Bool) {
        self.id = id
        self.name = name
        self.enabled = enabled
    }
}

public struct ProtobufTimestampObservation: Equatable, Sendable {
    public let seconds: Int64
    public let nanoseconds: Int32

    public init(seconds: Int64, nanoseconds: Int32) {
        self.seconds = seconds
        self.nanoseconds = nanoseconds
    }

    public var date: Date? {
        guard (-62_135_596_800 ... 253_402_300_799).contains(seconds) else {
            return nil
        }
        guard (0 ..< 1_000_000_000).contains(nanoseconds) else {
            return nil
        }
        let interval = Double(seconds) + Double(nanoseconds) / 1_000_000_000
        guard interval.isFinite else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }
}

public enum CertificateManagementAction: Equatable, Sendable {
    /// Issue through ACME. The first hostname is the common name; the rest
    /// are subject alternative names. The server may attach an existing
    /// certificate that already covers them instead of issuing a new one.
    case add(hostnames: [String])
    /// Permanently delete the certificate with this common name.
    case remove(commonName: String)
    /// Create the self-signed root of the server's local CA.
    case createRootCA(LocalRootCARequest)
    /// Issue a certificate from the server's local CA, apart from ACME.
    case createLocal(LocalCertificateRequest)
    /// Preserve the local certificate's key, subject and every extension.
    case renewLocal(commonName: String, validityDays: UInt32)
    /// Order a fresh ACME certificate; validity is the CA's, never asked for.
    case renewACME(commonName: String)
    /// Revoke a stored certificate and disable it in the hosting database.
    case revoke(commonName: String)
    case importPEM(chain: String, privateKey: String, issuer: String?)
    case exportPEM(commonName: String, includePrivateKey: Bool)

    public var title: String {
        switch self {
        case .add: "Issue with ACME"
        case .remove: "Remove Certificate"
        case .createRootCA: "Create Root CA"
        case .createLocal: "Issue from Local CA"
        case .renewLocal: "Renew Local Certificate"
        case .renewACME: "Renew with ACME"
        case .revoke: "Revoke Certificate"
        case .importPEM: "Import Certificate"
        case .exportPEM: "Export Certificate"
        }
    }
}

public enum CertificateManagementReceipt: Equatable, Sendable {
    case added(id: Int32, attachedExisting: Bool)
    /// The server's own outcome sentence, kept as it was sent.
    case operation(success: Bool, message: String?)
    /// Issuance returns metadata only; material stays in hosting until an
    /// explicit, authorized export is requested through CertificateTransfer.
    case local(LocalCertificateObservation)
    case imported(commonName: String)
    case exported(chain: String, privateKey: String?)
    /// ACME renewed the certificate; when it now expires.
    case renewed(expiresAt: Date?)
}

/// What a local-CA certificate is for.
public enum LocalCertificateKind: Equatable, Sendable, CaseIterable {
    /// TLS server identity for an internal host.
    case server
    /// Client identity, for mutual TLS.
    case client
    /// An intermediate CA below the issuing authority.
    case ca
}

public enum ReportedLocalCertificateKind: Equatable, Sendable {
    case kind(LocalCertificateKind)
    case unspecified
    case unrecognized(Int)
}

public struct LocalRootCARequest: Equatable, Sendable {
    public var commonName: String
    /// Declared by the operator; never defaulted by the client.
    public var validityDays: UInt32
    public var organization: String?
    public var country: String?

    public init(
        commonName: String,
        validityDays: UInt32,
        organization: String?,
        country: String?
    ) {
        self.commonName = commonName
        self.validityDays = validityDays
        self.organization = organization
        self.country = country
    }
}

public struct LocalCertificateRequest: Equatable, Sendable {
    public var commonName: String
    public var aliases: [String]
    /// Declared by the operator; must fit within the issuer's validity.
    public var validityDays: UInt32
    public var kind: LocalCertificateKind
    /// Required for `.ca`: the maximum intermediate depth below it.
    public var caPathLength: UInt32?
    /// A named local CA; `nil` selects the configured authority.
    public var issuer: String?
    /// Client application identity in a separate URI SAN; CN remains a label.
    public var subjectURI: String?
    /// Nil omits the declaration; an empty scope explicitly declares no permissions.
    public var permissions: CertificatePermissions?

    public init(
        commonName: String,
        aliases: [String],
        validityDays: UInt32,
        kind: LocalCertificateKind,
        caPathLength: UInt32?,
        issuer: String?,
        subjectURI: String? = nil,
        permissions: CertificatePermissions? = nil
    ) {
        self.commonName = commonName
        self.aliases = aliases
        self.validityDays = validityDays
        self.kind = kind
        self.caPathLength = caPathLength
        self.issuer = issuer
        self.subjectURI = subjectURI
        self.permissions = permissions
    }
}

public struct LocalCertificateObservation: Equatable, Sendable {
    public let id: Int32
    public let commonName: String
    public let aliases: [String]
    public let issuedAt: ProtobufTimestampObservation?
    public let expiresAt: ProtobufTimestampObservation?
    public let enabled: Bool
    public let revokedAt: ProtobufTimestampObservation?
    public let kind: ReportedLocalCertificateKind
    /// Absent only for a self-signed root CA.
    public let issuerID: Int32?
    public let subjectURIs: [String]
    public let permissions: [String]?

    public init(
        id: Int32,
        commonName: String,
        aliases: [String],
        issuedAt: ProtobufTimestampObservation?,
        expiresAt: ProtobufTimestampObservation?,
        enabled: Bool,
        kind: ReportedLocalCertificateKind,
        issuerID: Int32?,
        subjectURIs: [String] = [],
        revokedAt: ProtobufTimestampObservation? = nil,
        permissions: [String]? = nil
    ) {
        self.id = id
        self.commonName = commonName
        self.aliases = aliases
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.enabled = enabled
        self.revokedAt = revokedAt
        self.kind = kind
        self.issuerID = issuerID
        self.subjectURIs = subjectURIs
        self.permissions = permissions
    }
}
