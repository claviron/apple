import Foundation
import Testing
@testable import Claviron

struct ConfigurationRegistryTests {
    @Test
    func firstLaunchLoadsEmptyConfiguration() async throws {
        try await withTemporaryRegistry { registry, _ in
            let configuration = try await registry.load()

            #expect(configuration == .empty)
        }
    }

    @Test
    func configurationRoundTripsThroughPropertyList() async throws {
        try await withTemporaryRegistry { registry, fileURL in
            let expected = TestConfiguration.valid

            try await registry.save(expected)
            let loaded = try await registry.load()

            #expect(loaded == expected)
            #expect(FileManager.default.fileExists(atPath: fileURL.path))
        }
    }

    @Test
    func corruptDataProducesExplicitError() async throws {
        try await withTemporaryRegistry { registry, fileURL in
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("not a property list".utf8).write(to: fileURL)

            do {
                _ = try await registry.load()
                Issue.record("Expected corrupt registry data to fail")
            } catch let error as ConfigurationRegistryError {
                guard case .corruptData = error else {
                    Issue.record("Expected corruptData, received \(error)")
                    return
                }
            }
        }
    }

    @Test
    func unsupportedSchemaVersionProducesExplicitError() async throws {
        try await withTemporaryRegistry { registry, fileURL in
            var configuration = TestConfiguration.valid
            configuration.schemaVersion = ClientConfiguration.currentSchemaVersion + 1

            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = PropertyListEncoder()
            try encoder.encode(configuration).write(to: fileURL)

            await #expect(throws: ConfigurationRegistryError.unsupportedSchemaVersion(
                found: ClientConfiguration.currentSchemaVersion + 1,
                supported: ClientConfiguration.currentSchemaVersion
            )) {
                try await registry.load()
            }
        }
    }

    @Test
    func invalidConfigurationIsNotSaved() async throws {
        try await withTemporaryRegistry { registry, fileURL in
            var configuration = TestConfiguration.valid
            configuration.servers[0].tlsProfileID = TLSProfileID(rawValue: "missing")

            await #expect(throws: ConfigurationRegistryError.invalidConfiguration(
                .missingTLSProfile(
                    serverID: TestConfiguration.primaryServerID,
                    tlsProfileID: TLSProfileID(rawValue: "missing")
                )
            )) {
                try await registry.save(configuration)
            }
            #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        }
    }

    private func withTemporaryRegistry(
        _ operation: (ConfigurationRegistry, URL) async throws -> Void
    ) async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClavironRegistryTests-\(UUID())", isDirectory: true)
        let fileURL = directoryURL
            .appendingPathComponent("configuration.plist", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        try await operation(ConfigurationRegistry(fileURL: fileURL), fileURL)
    }
}
