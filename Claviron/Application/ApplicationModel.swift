import Foundation
import Observation
import ClavironControlPlane

@MainActor
@Observable
final class ApplicationModel {
    private let registry: ConfigurationRegistry?
    private let credentialStore: CredentialStore?
    private let startupError: String?

    private(set) var loadState: ApplicationLoadState = .idle
    private(set) var configuration: ClientConfiguration = .empty

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

        let credentials = try await ClavironTLSCredentials(
            certificateAuthorityFile: credentialStore.fileURL(
                for: tlsProfile.caCertificatePath
            ),
            clientCertificateFile: credentialStore.fileURL(
                for: tlsProfile.clientCertificatePath
            ),
            clientPrivateKeyFile: credentialStore.fileURL(
                for: tlsProfile.clientPrivateKeyPath
            )
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
            loadState = .ready
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func saveInitialConfiguration(
        _ input: InitialConfigurationInput,
        credentials: TLSCredentialImport,
        serverID: ServerID = ServerID(rawValue: UUID().uuidString.lowercased()),
        tlsProfileID: TLSProfileID = TLSProfileID(rawValue: UUID().uuidString.lowercased())
    ) async throws {
        guard let registry, let credentialStore else {
            throw ApplicationModelError.registryUnavailable
        }

        // The wizard runs both before there is any configuration and from
        // Settings afterwards. Same inputs either way: the first run writes
        // the whole configuration, a later run appends to it.
        let isFirstRun = configuration.servers.isEmpty
        let build = { (paths: TLSCredentialPaths) throws -> ClientConfiguration in
            isFirstRun
                ? try input.makeConfiguration(
                    serverID: serverID,
                    tlsProfileID: tlsProfileID,
                    credentialPaths: paths
                )
                : try input.addingTo(
                    self.configuration,
                    serverID: serverID,
                    tlsProfileID: tlsProfileID,
                    credentialPaths: paths
                )
        }

        _ = try build(.validationPlaceholder)
        try credentials.validate()

        let credentialPaths = try await credentialStore.install(
            credentials,
            for: tlsProfileID
        )
        let candidate = try build(credentialPaths)

        do {
            try await registry.save(candidate)
        } catch {
            try? await credentialStore.removeCredentials(for: tlsProfileID)
            throw error
        }
        configuration = candidate
        loadState = .ready
    }

    func selectActiveServer(_ serverID: ServerID) async throws {
        guard configuration.activeServerID != serverID else {
            return
        }
        guard configuration.servers.contains(where: { $0.id == serverID }) else {
            throw ApplicationModelError.unknownServer(serverID)
        }
        guard let registry else {
            throw ApplicationModelError.registryUnavailable
        }

        var candidate = configuration
        candidate.activeServerID = serverID
        try candidate.validate()
        try await registry.save(candidate)
        configuration = candidate
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

    func addTLSProfile(
        name: String,
        credentials: TLSCredentialImport,
        profileID: TLSProfileID = TLSProfileID(rawValue: UUID().uuidString.lowercased())
    ) async throws {
        guard let registry, let credentialStore else {
            throw ApplicationModelError.registryUnavailable
        }

        var candidate = configuration
        candidate.tlsProfiles.append(
            TLSProfile(
                id: profileID,
                name: name,
                caCertificatePath: TLSCredentialPaths.validationPlaceholder.caCertificatePath,
                clientCertificatePath: TLSCredentialPaths.validationPlaceholder.clientCertificatePath,
                clientPrivateKeyPath: TLSCredentialPaths.validationPlaceholder.clientPrivateKeyPath
            )
        )
        try candidate.validate()
        try credentials.validate()

        let paths = try await credentialStore.install(credentials, for: profileID)
        guard let index = candidate.tlsProfiles.firstIndex(
            where: { $0.id == profileID }
        ) else {
            try? await credentialStore.removeCredentials(for: profileID)
            throw ApplicationModelError.unknownTLSProfile(profileID)
        }
        candidate.tlsProfiles[index].caCertificatePath = paths.caCertificatePath
        candidate.tlsProfiles[index].clientCertificatePath = paths.clientCertificatePath
        candidate.tlsProfiles[index].clientPrivateKeyPath = paths.clientPrivateKeyPath

        do {
            try await registry.save(candidate)
        } catch {
            try? await credentialStore.removeCredentials(for: profileID)
            throw error
        }
        configuration = candidate
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

        try candidate.validate()
        try await registry.save(candidate)
        configuration = candidate
    }
}

enum ApplicationLoadState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

enum ApplicationModelError: Error, Equatable, LocalizedError {
    case registryUnavailable
    case unknownServer(ServerID)
    case unknownTLSProfile(TLSProfileID)
    case tlsProfileInUse(TLSProfileID, serverNames: [String])
    case credentialCleanupFailed(TLSProfileID, detail: String)

    var errorDescription: String? {
        switch self {
        case .registryUnavailable:
            "The configuration registry is unavailable."
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
