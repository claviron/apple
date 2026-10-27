import Foundation

nonisolated struct ServerID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated struct TLSProfileID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated struct ServerProfile: Identifiable, Codable, Equatable, Sendable {
    let id: ServerID
    var name: String
    var address: String
    var tlsProfileID: TLSProfileID
}

nonisolated struct TLSProfile: Identifiable, Codable, Equatable, Sendable {
    let id: TLSProfileID
    var name: String
    var caCertificatePath: String
    var clientCertificatePath: String
    var clientPrivateKeyPath: String
}

nonisolated struct ClientConfiguration: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var activeServerID: ServerID?
    var servers: [ServerProfile]
    var tlsProfiles: [TLSProfile]

    init(
        schemaVersion: Int = currentSchemaVersion,
        activeServerID: ServerID? = nil,
        servers: [ServerProfile] = [],
        tlsProfiles: [TLSProfile] = []
    ) {
        self.schemaVersion = schemaVersion
        self.activeServerID = activeServerID
        self.servers = servers
        self.tlsProfiles = tlsProfiles
    }

    static let empty = ClientConfiguration()

    static let preview = ClientConfiguration(
        activeServerID: ServerID(rawValue: "local"),
        servers: [
            ServerProfile(
                id: ServerID(rawValue: "local"),
                name: "Local",
                address: "https://localhost:7443",
                tlsProfileID: TLSProfileID(rawValue: "operator")
            ),
        ],
        tlsProfiles: [
            TLSProfile(
                id: TLSProfileID(rawValue: "operator"),
                name: "Operator",
                caCertificatePath: "credentials/operator/ca.pem",
                clientCertificatePath: "credentials/operator/client.pem",
                clientPrivateKeyPath: "credentials/operator/client-key.pem"
            ),
        ]
    )

    var activeServer: ServerProfile? {
        guard let activeServerID else {
            return nil
        }

        return servers.first { $0.id == activeServerID }
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ConfigurationValidationError.unsupportedSchemaVersion(
                found: schemaVersion,
                supported: Self.currentSchemaVersion
            )
        }

        var serverIDs = Set<ServerID>()
        for server in servers {
            guard !server.id.rawValue.isBlank else {
                throw ConfigurationValidationError.emptyServerID
            }
            guard server.id.rawValue.isSafeIdentifier else {
                throw ConfigurationValidationError.invalidServerID(server.id)
            }
            guard serverIDs.insert(server.id).inserted else {
                throw ConfigurationValidationError.duplicateServerID(server.id)
            }
            guard !server.name.isBlank else {
                throw ConfigurationValidationError.emptyServerName(server.id)
            }
            guard server.address.isValidHTTPSEndpoint else {
                throw ConfigurationValidationError.invalidServerAddress(
                    server.id,
                    server.address
                )
            }
        }

        var tlsProfileIDs = Set<TLSProfileID>()
        for profile in tlsProfiles {
            guard !profile.id.rawValue.isBlank else {
                throw ConfigurationValidationError.emptyTLSProfileID
            }
            guard profile.id.rawValue.isSafeIdentifier else {
                throw ConfigurationValidationError.invalidTLSProfileID(profile.id)
            }
            guard tlsProfileIDs.insert(profile.id).inserted else {
                throw ConfigurationValidationError.duplicateTLSProfileID(profile.id)
            }
            guard !profile.name.isBlank else {
                throw ConfigurationValidationError.emptyTLSProfileName(profile.id)
            }

            try validateCredentialPath(
                profile.caCertificatePath,
                field: .certificateAuthority,
                profileID: profile.id
            )
            try validateCredentialPath(
                profile.clientCertificatePath,
                field: .clientCertificate,
                profileID: profile.id
            )
            try validateCredentialPath(
                profile.clientPrivateKeyPath,
                field: .clientPrivateKey,
                profileID: profile.id
            )
        }

        for server in servers where !tlsProfileIDs.contains(server.tlsProfileID) {
            throw ConfigurationValidationError.missingTLSProfile(
                serverID: server.id,
                tlsProfileID: server.tlsProfileID
            )
        }

        if servers.isEmpty {
            if let activeServerID {
                throw ConfigurationValidationError.unknownActiveServer(activeServerID)
            }
        } else {
            guard let activeServerID else {
                throw ConfigurationValidationError.missingActiveServer
            }
            guard serverIDs.contains(activeServerID) else {
                throw ConfigurationValidationError.unknownActiveServer(activeServerID)
            }
        }
    }

    private func validateCredentialPath(
        _ path: String,
        field: TLSCredentialField,
        profileID: TLSProfileID
    ) throws {
        guard !path.isBlank else {
            throw ConfigurationValidationError.emptyCredentialPath(
                profileID: profileID,
                field: field
            )
        }
    }
}

nonisolated enum TLSCredentialField: String, Equatable, Sendable {
    case certificateAuthority = "CA certificate"
    case clientCertificate = "client certificate"
    case clientPrivateKey = "client private key"
}

nonisolated enum ConfigurationValidationError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case emptyServerID
    case invalidServerID(ServerID)
    case duplicateServerID(ServerID)
    case emptyServerName(ServerID)
    case invalidServerAddress(ServerID, String)
    case emptyTLSProfileID
    case invalidTLSProfileID(TLSProfileID)
    case duplicateTLSProfileID(TLSProfileID)
    case emptyTLSProfileName(TLSProfileID)
    case emptyCredentialPath(profileID: TLSProfileID, field: TLSCredentialField)
    case missingTLSProfile(serverID: ServerID, tlsProfileID: TLSProfileID)
    case missingActiveServer
    case unknownActiveServer(ServerID)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(found, supported):
            "Configuration schema version \(found) is unsupported; expected \(supported)."
        case .emptyServerID:
            "A server ID cannot be empty."
        case let .invalidServerID(id):
            "Server ID '\(id.rawValue)' contains unsupported characters."
        case let .duplicateServerID(id):
            "Server ID '\(id.rawValue)' is duplicated."
        case let .emptyServerName(id):
            "Server '\(id.rawValue)' must have a name."
        case let .invalidServerAddress(id, address):
            "Server '\(id.rawValue)' has an invalid HTTPS address: \(address)"
        case .emptyTLSProfileID:
            "A TLS profile ID cannot be empty."
        case let .invalidTLSProfileID(id):
            "TLS profile ID '\(id.rawValue)' contains unsupported characters."
        case let .duplicateTLSProfileID(id):
            "TLS profile ID '\(id.rawValue)' is duplicated."
        case let .emptyTLSProfileName(id):
            "TLS profile '\(id.rawValue)' must have a name."
        case let .emptyCredentialPath(profileID, field):
            "TLS profile '\(profileID.rawValue)' is missing its \(field.rawValue)."
        case let .missingTLSProfile(serverID, tlsProfileID):
            "Server '\(serverID.rawValue)' references missing TLS profile '\(tlsProfileID.rawValue)'."
        case .missingActiveServer:
            "A non-empty configuration must select one active server."
        case let .unknownActiveServer(id):
            "Active server '\(id.rawValue)' is not present in the configuration."
        }
    }
}

nonisolated extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isValidHTTPSEndpoint: Bool {
        guard
            let components = URLComponents(string: self),
            components.scheme?.lowercased() == "https",
            let host = components.host,
            !host.isEmpty,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil,
            components.path.isEmpty || components.path == "/"
        else {
            return false
        }

        guard let port = components.port else {
            return true
        }

        return (1 ... 65_535).contains(port)
    }

    var isSafeIdentifier: Bool {
        self != "." && self != ".." && unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0)
        }
    }
}
