import Foundation

actor ConfigurationRegistry {
    nonisolated let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static func applicationFileURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ConfigurationRegistryError.applicationSupportUnavailable
        }

        return applicationSupport
            .appendingPathComponent("Claviron", isDirectory: true)
            .appendingPathComponent("configuration.plist", isDirectory: false)
    }

    func load() throws -> ClientConfiguration {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ConfigurationRegistryError.readFailed(error.localizedDescription)
        }

        let decoder = PropertyListDecoder()
        let header: SchemaHeader
        do {
            header = try decoder.decode(SchemaHeader.self, from: data)
        } catch {
            throw ConfigurationRegistryError.corruptData(error.localizedDescription)
        }

        guard header.schemaVersion == ClientConfiguration.currentSchemaVersion else {
            throw ConfigurationRegistryError.unsupportedSchemaVersion(
                found: header.schemaVersion,
                supported: ClientConfiguration.currentSchemaVersion
            )
        }

        let configuration: ClientConfiguration
        do {
            configuration = try decoder.decode(ClientConfiguration.self, from: data)
        } catch {
            throw ConfigurationRegistryError.corruptData(error.localizedDescription)
        }

        do {
            try configuration.validate()
        } catch let error as ConfigurationValidationError {
            throw ConfigurationRegistryError.invalidConfiguration(error)
        }

        return configuration
    }

    func save(_ configuration: ClientConfiguration) throws {
        do {
            try configuration.validate()
        } catch let error as ConfigurationValidationError {
            switch error {
            case let .unsupportedSchemaVersion(found, supported):
                throw ConfigurationRegistryError.unsupportedSchemaVersion(
                    found: found,
                    supported: supported
                )
            default:
                throw ConfigurationRegistryError.invalidConfiguration(error)
            }
        }

        let fileManager = FileManager.default
        let directoryURL = fileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw ConfigurationRegistryError.writeFailed(error.localizedDescription)
        }

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml

        let data: Data
        do {
            data = try encoder.encode(configuration)
        } catch {
            throw ConfigurationRegistryError.writeFailed(error.localizedDescription)
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw ConfigurationRegistryError.writeFailed(error.localizedDescription)
        }
    }
}

nonisolated enum ConfigurationRegistryError: Error, Equatable, LocalizedError, Sendable {
    case applicationSupportUnavailable
    case readFailed(String)
    case corruptData(String)
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case invalidConfiguration(ConfigurationValidationError)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            "The Application Support directory is unavailable."
        case let .readFailed(detail):
            "The configuration registry could not be read: \(detail)"
        case let .corruptData(detail):
            "The configuration registry is corrupt: \(detail)"
        case let .unsupportedSchemaVersion(found, supported):
            "Configuration schema version \(found) is unsupported; expected \(supported)."
        case let .invalidConfiguration(error):
            error.localizedDescription
        case let .writeFailed(detail):
            "The configuration registry could not be saved: \(detail)"
        }
    }
}

nonisolated private struct SchemaHeader: Decodable {
    let schemaVersion: Int
}
