import CryptoKit
import Foundation
import Observation
import ClavironControlPlane

@MainActor
@Observable
final class ApplicationModel {
    private let registry: ConfigurationRegistry?
    private let credentialStore: CredentialStore?
    private let startupError: String?
    private var isSavingConfiguration = false

    private(set) var loadState: ApplicationLoadState = .idle
    private(set) var configuration: ClientConfiguration = .empty

    private(set) var deviceKeyStatus: DeviceKeyStatus?
    @ObservationIgnored private var unlockedDeviceKey: P256.Signing.PrivateKey?

    init(
        registry: ConfigurationRegistry,
        credentialStore: CredentialStore? = nil
    ) {
        self.registry = registry
        self.credentialStore = credentialStore ?? CredentialStore(
            rootDirectoryURL: registry.fileURL.deletingLastPathComponent()
        )
        startupError = nil
    }

    private init(startupError: String) {
        registry = nil
        credentialStore = nil
        self.startupError = startupError
        loadState = .failed(startupError)
    }

    static func live() -> ApplicationModel {
        do {
            let fileURL = try ConfigurationRegistry.applicationFileURL()
            return ApplicationModel(
                registry: ConfigurationRegistry(fileURL: fileURL)
            )
        } catch {
            return ApplicationModel(startupError: error.localizedDescription)
        }
    }

    static func preview(
        configuration: ClientConfiguration = .empty
    ) -> ApplicationModel {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClavironPreview-\(UUID())", isDirectory: true)
            .appendingPathComponent("configuration.plist", isDirectory: false)
        let model = ApplicationModel(
            registry: ConfigurationRegistry(fileURL: fileURL)
        )
        model.configuration = configuration
        model.loadState = .ready
        return model
    }

    var activeServer: ServerProfile? {
        configuration.activeServer
    }

    var needsInitialConfiguration: Bool {
        loadState == .ready && configuration.servers.isEmpty
    }

    func endpoint(for serverID: ServerID) async throws -> ClavironEndpoint {
        guard let server = configuration.servers.first(where: { $0.id == serverID }) else {
            throw ApplicationModelError.unknownServer(serverID)
        }
        guard let tlsProfile = configuration.tlsProfiles.first(
            where: { $0.id == server.tlsProfileID }
        ) else {
            throw ApplicationModelError.unknownTLSProfile(server.tlsProfileID)
        }
        guard let credentialStore else {
            throw ApplicationModelError.registryUnavailable
        }

        let certificateAuthority: URL?
        if let path = tlsProfile.caCertificatePath {
            certificateAuthority = try await credentialStore.fileURL(for: path)
        } else {
            certificateAuthority = nil
        }
        let certificate = try await credentialStore.fileURL(for: tlsProfile.clientCertificatePath)
        let privateKey: ClavironTLSCredentials.PrivateKey
        if tlsProfile.clientPrivateKeyPath == CredentialStore.deviceKeyPath {
            guard let stored = try await credentialStore.loadDeviceKey() else {
                throw CredentialStoreError.missingDeviceKey
            }
            switch stored {
            case .unencrypted:
                privateKey = .file(try await credentialStore.fileURL(for: tlsProfile.clientPrivateKeyPath))
            case .encrypted:
                guard let unlockedDeviceKey else { throw DeviceKeyError.locked }
                privateKey = .pem(Data(unlockedDeviceKey.pemRepresentation.utf8))
            }
        } else {
            privateKey = .file(try await credentialStore.fileURL(for: tlsProfile.clientPrivateKeyPath))
        }
        let credentials = ClavironTLSCredentials(
            certificateAuthorityFile: certificateAuthority,
            clientCertificateFile: certificate,
            clientPrivateKey: privateKey
        )
        return try ClavironEndpoint(
            serverAddress: server.address,
            credentials: credentials
        )
    }

    func loadIfNeeded() async {
        guard loadState == .idle else {
            return
        }

        await reload()
    }

    func reload() async {
        guard let registry else {
            loadState = .failed(
                startupError ?? "The configuration registry is unavailable."
            )
            return
        }

        loadState = .loading
        do {
            configuration = try await registry.load()
            try await refreshDeviceKeyStatus()
            loadState = .ready
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private var hasDeviceKeyReferences: Bool {
        configuration.tlsProfiles.contains {
            $0.clientPrivateKeyPath == CredentialStore.deviceKeyPath
        }
    }

    func refreshDeviceKeyStatus() async throws {
        guard let credentialStore else { throw ApplicationModelError.registryUnavailable }
        switch try await credentialStore.loadDeviceKey() {
        case .none:
            guard !hasDeviceKeyReferences else { throw CredentialStoreError.missingDeviceKey }
            deviceKeyStatus = .missing
        case .unencrypted:
            deviceKeyStatus = .unencrypted
        case .encrypted:
            deviceKeyStatus = unlockedDeviceKey == nil ? .locked : .unlocked
        }
    }

    func createDeviceKey(password: String?) async throws {
        guard let credentialStore else { throw ApplicationModelError.registryUnavailable }
        guard !hasDeviceKeyReferences else { throw DeviceKeyError.alreadyExists }
        let key = try await credentialStore.createDeviceKey(password: password)
        unlockedDeviceKey = password == nil ? nil : key
        deviceKeyStatus = password == nil ? .unencrypted : .unlocked
    }

    func unlockDeviceKey(password: String) async throws {
        guard let credentialStore else { throw ApplicationModelError.registryUnavailable }
        unlockedDeviceKey = try await credentialStore.unlockDeviceKey(password: password)
        deviceKeyStatus = .unlocked
    }

    func lockDeviceKey() {
        unlockedDeviceKey = nil
        deviceKeyStatus = .locked
    }

    func enrollmentKey() async throws -> P256.Signing.PrivateKey {
        guard let credentialStore else { throw ApplicationModelError.registryUnavailable }
        switch try await credentialStore.loadDeviceKey() {
        case .none:
            throw CredentialStoreError.missingDeviceKey
        case let .unencrypted(key):
            return key
        case .encrypted:
            guard let unlockedDeviceKey else { throw DeviceKeyError.locked }
            return unlockedDeviceKey
        }
    }

    func saveEnrollment(
        _ input: InitialConfigurationInput,
        username: String,
        certificates: EnrollmentCertificates,
        serverID: ServerID = ServerID(rawValue: UUID().uuidString.lowercased()),
        tlsProfileID: TLSProfileID = TLSProfileID(rawValue: UUID().uuidString.lowercased())
    ) async throws {
        guard let credentialStore else {
            throw ApplicationModelError.registryUnavailable
        }

        _ = try input.addingTo(
            configuration,
            username: username,
            serverID: serverID,
            tlsProfileID: tlsProfileID,
            credentialPaths: .validationPlaceholder
        )
        let paths = try await credentialStore.install(certificates, for: tlsProfileID)
        do {
            let candidate = try input.addingTo(
                configuration,
                username: username,
                serverID: serverID,
                tlsProfileID: tlsProfileID,
                credentialPaths: paths
            )
            try await persist(candidate)
        } catch {
            try? await credentialStore.removeCredentials(for: tlsProfileID)
            throw error
        }
        loadState = .ready
    }

    func selectActiveServer(_ serverID: ServerID) async throws {
        guard configuration.activeServerID != serverID else {
            return
        }
        guard configuration.servers.contains(where: { $0.id == serverID }) else {
            throw ApplicationModelError.unknownServer(serverID)
        }
        var candidate = configuration
        candidate.activeServerID = serverID
        try await persist(candidate)
    }

    func addServer(
        name: String,
        address: String,
        tlsProfileID: TLSProfileID,
        serverID: ServerID = ServerID(rawValue: UUID().uuidString.lowercased())
    ) async throws {
        var candidate = configuration
        candidate.servers.append(
            ServerProfile(
                id: serverID,
                name: name,
                address: address,
                tlsProfileID: tlsProfileID
            )
        )
        try await persist(candidate)
    }

    func updateServer(
        _ serverID: ServerID,
        name: String,
        address: String,
        tlsProfileID: TLSProfileID
    ) async throws {
        guard let index = configuration.servers.firstIndex(
            where: { $0.id == serverID }
        ) else {
            throw ApplicationModelError.unknownServer(serverID)
        }

        var candidate = configuration
        candidate.servers[index].name = name
        candidate.servers[index].address = address
        candidate.servers[index].tlsProfileID = tlsProfileID
        try await persist(candidate)
    }

    func removeServer(_ serverID: ServerID) async throws {
        guard configuration.servers.contains(where: { $0.id == serverID }) else {
            throw ApplicationModelError.unknownServer(serverID)
        }
        var candidate = configuration
        candidate.servers.removeAll { $0.id == serverID }
        // Removing the server you are looking at is an ordinary thing to
        // want. The selection moves to whatever is left, and becomes
        // nothing when nothing is left, which is the shape the
        // configuration validates against.
        if candidate.activeServerID == serverID {
            candidate.activeServerID = candidate.servers.first?.id
        }
        try await persist(candidate)
    }

    func updateTLSProfileName(
        _ profileID: TLSProfileID,
        name: String
    ) async throws {
        guard let index = configuration.tlsProfiles.firstIndex(
            where: { $0.id == profileID }
        ) else {
            throw ApplicationModelError.unknownTLSProfile(profileID)
        }

        var candidate = configuration
        candidate.tlsProfiles[index].name = name
        try await persist(candidate)
    }

    func removeTLSProfile(_ profileID: TLSProfileID) async throws {
        guard configuration.tlsProfiles.contains(where: { $0.id == profileID }) else {
            throw ApplicationModelError.unknownTLSProfile(profileID)
        }

        let referencingServers = configuration.servers.filter {
            $0.tlsProfileID == profileID
        }
        guard referencingServers.isEmpty else {
            throw ApplicationModelError.tlsProfileInUse(
                profileID,
                serverNames: referencingServers.map(\.name)
            )
        }
        guard let credentialStore else {
            throw ApplicationModelError.registryUnavailable
        }

        var candidate = configuration
        candidate.tlsProfiles.removeAll { $0.id == profileID }
        try await persist(candidate)

        do {
            try await credentialStore.removeCredentials(for: profileID)
        } catch {
            throw ApplicationModelError.credentialCleanupFailed(
                profileID,
                detail: error.localizedDescription
            )
        }
    }

    private func persist(_ candidate: ClientConfiguration) async throws {
        guard let registry else {
            throw ApplicationModelError.registryUnavailable
        }

        guard !isSavingConfiguration else {
            throw ApplicationModelError.saveInProgress
        }
        isSavingConfiguration = true
        defer { isSavingConfiguration = false }

        try candidate.validate()
        try await registry.save(candidate)
        configuration = candidate
    }
}

enum DeviceKeyStatus: Equatable {
    case missing
    case unencrypted
    case locked
    case unlocked

    var isLoaded: Bool { self == .unencrypted || self == .unlocked }
}

enum ApplicationLoadState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

enum ApplicationModelError: Error, Equatable, LocalizedError {
    case registryUnavailable
    case saveInProgress
    case unknownServer(ServerID)
    case unknownTLSProfile(TLSProfileID)
    case tlsProfileInUse(TLSProfileID, serverNames: [String])
    case credentialCleanupFailed(TLSProfileID, detail: String)

    var errorDescription: String? {
        switch self {
        case .registryUnavailable:
            "The configuration registry is unavailable."
        case .saveInProgress:
            "Another configuration change is being saved. Try again."
        case let .unknownServer(serverID):
            "Server '\(serverID.rawValue)' is not saved."
        case let .unknownTLSProfile(profileID):
            "TLS profile '\(profileID.rawValue)' is not saved."
        case let .tlsProfileInUse(profileID, serverNames):
            "TLS profile '\(profileID.rawValue)' is used by: \(serverNames.joined(separator: ", "))."
        case let .credentialCleanupFailed(profileID, detail):
            "TLS profile '\(profileID.rawValue)' was removed, but its credential files could not be deleted: \(detail)"
        }
    }
}
