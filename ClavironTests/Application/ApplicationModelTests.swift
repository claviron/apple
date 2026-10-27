import Foundation
import Testing
@testable import Claviron

@MainActor
struct ApplicationModelTests {
    @Test
    func firstLaunchInputIsSavedAndBecomesActive() async throws {
        try await withTemporaryModel { model, registry in
            await model.loadIfNeeded()
            #expect(model.needsInitialConfiguration)

            let serverID = ServerID(rawValue: "primary")
            let tlsProfileID = TLSProfileID(rawValue: "operator")
            try await model.saveInitialConfiguration(
                .valid,
                credentials: .valid,
                serverID: serverID,
                tlsProfileID: tlsProfileID
            )

            #expect(model.activeServer?.id == serverID)
            #expect(model.configuration.tlsProfiles.first?.id == tlsProfileID)
            #expect(try await registry.load() == model.configuration)

            let profile = try #require(model.configuration.tlsProfiles.first)
            let credentialURL = registry.fileURL
                .deletingLastPathComponent()
                .appendingPathComponent(profile.clientPrivateKeyPath)
            #expect(FileManager.default.fileExists(atPath: credentialURL.path))
        }
    }

    @Test
    func activeServerChangeIsPersisted() async throws {
        try await withTemporaryModel(configuration: TestConfiguration.valid) { model, registry in
            await model.loadIfNeeded()
            let stagingID = ServerID(rawValue: "staging")

            try await model.selectActiveServer(stagingID)

            #expect(model.activeServer?.id == stagingID)
            #expect(try await registry.load().activeServerID == stagingID)
        }
    }

    /// The wizard is reachable from Settings once the app is set up, so a
    /// later run must add to the configuration rather than replace it, and
    /// must leave the active selection where the user put it.
    @Test
    func wizardRunAfterSetupAppendsWithoutReplacing() async throws {
        try await withTemporaryModel(configuration: TestConfiguration.valid) { model, _ in
            await model.loadIfNeeded()

            let serverCount = model.configuration.servers.count
            let profileCount = model.configuration.tlsProfiles.count
            let activeBefore = model.configuration.activeServerID

            try await model.saveInitialConfiguration(.valid, credentials: .valid)

            #expect(model.configuration.servers.count == serverCount + 1)
            #expect(model.configuration.tlsProfiles.count == profileCount + 1)
            #expect(model.configuration.activeServerID == activeBefore)
        }
    }

    @Test
    func corruptRegistryProducesFailureState() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClavironModelTests-\(UUID())", isDirectory: true)
        let fileURL = directoryURL
            .appendingPathComponent("configuration.plist", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try Data("invalid".utf8).write(to: fileURL)

        let model = ApplicationModel(
            registry: ConfigurationRegistry(fileURL: fileURL)
        )
        await model.loadIfNeeded()

        guard case .failed = model.loadState else {
            Issue.record("Expected a failed application load state")
            return
        }
    }

    @Test
    func addingServerAndTLSProfileDoesNotChangeActiveServer() async throws {
        try await withTemporaryModel(configuration: TestConfiguration.valid) { model, _ in
            await model.loadIfNeeded()
            let activeServerID = try #require(model.configuration.activeServerID)
            let profileID = TLSProfileID(rawValue: "secondary-identity")

            try await model.addTLSProfile(
                name: "Secondary Identity",
                credentials: .valid,
                profileID: profileID
            )
            try await model.addServer(
                name: "Development",
                address: "https://development.example.com:7443",
                tlsProfileID: profileID,
                serverID: ServerID(rawValue: "development")
            )

            #expect(model.configuration.activeServerID == activeServerID)
            #expect(model.configuration.servers.last?.tlsProfileID == profileID)
        }
    }

    @Test
    func serverCanBeEditedAndOnlyNonActiveServerCanBeRemoved() async throws {
        try await withTemporaryModel(configuration: TestConfiguration.valid) { model, _ in
            await model.loadIfNeeded()
            let stagingID = ServerID(rawValue: "staging")

            try await model.updateServer(
                stagingID,
                name: "Pre-production",
                address: "https://preprod.example.com:7443",
                tlsProfileID: TestConfiguration.sharedTLSProfileID
            )
            #expect(model.configuration.servers.first {
                $0.id == stagingID
            }?.name == "Pre-production")

            try await model.removeServer(stagingID)
            #expect(!model.configuration.servers.contains { $0.id == stagingID })

            // Removing the last server is allowed; the selection follows it
            // out rather than blocking the removal.
            try await model.removeServer(TestConfiguration.primaryServerID)
            #expect(model.configuration.servers.isEmpty)
            #expect(model.configuration.activeServerID == nil)
        }
    }

    @Test
    func usedTLSProfileCannotBeRemoved() async throws {
        try await withTemporaryModel(configuration: TestConfiguration.valid) { model, _ in
            await model.loadIfNeeded()

            do {
                try await model.removeTLSProfile(TestConfiguration.sharedTLSProfileID)
                Issue.record("Expected an in-use TLS profile to be retained")
            } catch let error as ApplicationModelError {
                guard case let .tlsProfileInUse(profileID, serverNames) = error else {
                    Issue.record("Unexpected error: \(error)")
                    return
                }
                #expect(profileID == TestConfiguration.sharedTLSProfileID)
                #expect(serverNames == ["Production", "Staging"])
            }
        }
    }

    @Test
    func unusedTLSProfileCanBeRenamedAndRemovedWithCredentials() async throws {
        try await withTemporaryModel(configuration: TestConfiguration.valid) { model, registry in
            await model.loadIfNeeded()
            let profileID = TLSProfileID(rawValue: "temporary")
            try await model.addTLSProfile(
                name: "Temporary",
                credentials: .valid,
                profileID: profileID
            )
            try await model.updateTLSProfileName(profileID, name: "Renamed")
            #expect(model.configuration.tlsProfiles.first {
                $0.id == profileID
            }?.name == "Renamed")

            let credentialDirectoryURL = registry.fileURL
                .deletingLastPathComponent()
                .appendingPathComponent("Credentials/temporary", isDirectory: true)
            #expect(FileManager.default.fileExists(atPath: credentialDirectoryURL.path))

            try await model.removeTLSProfile(profileID)

            #expect(!model.configuration.tlsProfiles.contains { $0.id == profileID })
            #expect(!FileManager.default.fileExists(atPath: credentialDirectoryURL.path))
        }
    }

    private func withTemporaryModel(
        configuration: ClientConfiguration? = nil,
        _ operation: (ApplicationModel, ConfigurationRegistry) async throws -> Void
    ) async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClavironModelTests-\(UUID())", isDirectory: true)
        let fileURL = directoryURL
            .appendingPathComponent("configuration.plist", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let registry = ConfigurationRegistry(fileURL: fileURL)
        if let configuration {
            try await registry.save(configuration)
        }

        try await operation(ApplicationModel(registry: registry), registry)
    }
}

private extension InitialConfigurationInput {
    static let valid = InitialConfigurationInput(
        serverName: "Production",
        serverAddress: "https://control.example.com:7443",
        tlsProfileName: "Operator"
    )
}

extension TLSCredentialImport {
    static let valid = TLSCredentialImport(
        certificateAuthority: ImportedCredential(
            fileName: "ca.pem",
            data: Data("ca".utf8)
        ),
        clientCertificate: ImportedCredential(
            fileName: "client.pem",
            data: Data("certificate".utf8)
        ),
        clientPrivateKey: ImportedCredential(
            fileName: "client-key.pem",
            data: Data("private key".utf8)
        )
    )
}
