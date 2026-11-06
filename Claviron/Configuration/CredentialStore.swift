import CryptoKit
import Foundation

nonisolated struct ImportedCredential: Equatable, Sendable {
    static let maximumByteCount = 10 * 1_024 * 1_024

    let fileName: String
    let data: Data

    static func read(from url: URL) throws -> ImportedCredential {
        let accessedSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let resourceValues: URLResourceValues
        do {
            resourceValues = try url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            )
        } catch {
            throw CredentialStoreError.readFailed(
                fileName: url.lastPathComponent,
                detail: error.localizedDescription
            )
        }

        guard resourceValues.isRegularFile == true else {
            throw CredentialStoreError.notARegularFile(url.lastPathComponent)
        }

        if let fileSize = resourceValues.fileSize,
           fileSize > maximumByteCount {
            throw CredentialStoreError.fileTooLarge(url.lastPathComponent)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw CredentialStoreError.readFailed(
                fileName: url.lastPathComponent,
                detail: error.localizedDescription
            )
        }

        guard !data.isEmpty else {
            throw CredentialStoreError.emptyFile(url.lastPathComponent)
        }
        guard data.count <= maximumByteCount else {
            throw CredentialStoreError.fileTooLarge(url.lastPathComponent)
        }

        return ImportedCredential(fileName: url.lastPathComponent, data: data)
    }
}

nonisolated struct TLSCredentialPaths: Equatable, Sendable {
    let caCertificatePath: String?
    let clientCertificatePath: String
    let clientPrivateKeyPath: String

    static let validationPlaceholder = TLSCredentialPaths(
        caCertificatePath: "Credentials/validation/ca.pem",
        clientCertificatePath: "Credentials/validation/client.pem",
        clientPrivateKeyPath: "Credentials/validation/client-key.pem"
    )
}

nonisolated enum TLSCredentialRole: String, CaseIterable, Sendable {
    case certificateAuthority
    case clientCertificate

    var storedFileName: String {
        switch self {
        case .certificateAuthority:
            "ca.pem"
        case .clientCertificate:
            "client.pem"
        }
    }
}

nonisolated enum StoredDeviceKey: Sendable {
    case unencrypted(P256.Signing.PrivateKey)
    case encrypted(String)
}

actor CredentialStore {
    nonisolated static let deviceKeyPath = "Identity/client-key.pem"
    nonisolated let rootDirectoryURL: URL

    init(rootDirectoryURL: URL) {
        self.rootDirectoryURL = rootDirectoryURL
    }

    func loadDeviceKey() throws -> StoredDeviceKey? {
        let url = try fileURL(for: Self.deviceKeyPath)
        let pem: String
        do {
            pem = try String(contentsOf: url, encoding: .utf8)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
        if PrivateKeyProtection.isEncrypted(pem) {
            return .encrypted(pem)
        }
        return .unencrypted(try P256.Signing.PrivateKey(pemRepresentation: pem))
    }

    func unlockDeviceKey(password: String) throws -> P256.Signing.PrivateKey {
        guard case let .encrypted(pem)? = try loadDeviceKey() else {
            throw DeviceKeyError.invalidProtection
        }
        return try PrivateKeyProtection.decrypt(pem, password: password)
    }

    func createDeviceKey(password: String?) throws -> P256.Signing.PrivateKey {
        guard try loadDeviceKey() == nil else { throw DeviceKeyError.alreadyExists }
        let url = try fileURL(for: Self.deviceKeyPath)
        let directory = url.deletingLastPathComponent()
        let fileManager = FileManager.default
        try createPrivateDirectory(directory, fileManager: fileManager)
        try excludeFromBackup(directory)
        let staged = directory.appendingPathComponent(".key-\(UUID())")
        defer { try? fileManager.removeItem(at: staged) }

        let key = P256.Signing.PrivateKey()
        let data = try password.map { try PrivateKeyProtection.encrypt(key, password: $0) }
            ?? Data(key.pemRepresentation.utf8)
        try data.write(to: staged, options: .withoutOverwriting)
        try protectFile(at: staged, fileManager: fileManager)
        try fileManager.moveItem(at: staged, to: url)
        return key
    }

    func install(
        _ certificates: EnrollmentCertificates,
        for profileID: TLSProfileID
    ) throws -> TLSCredentialPaths {
        guard try loadDeviceKey() != nil else { throw CredentialStoreError.missingDeviceKey }
        guard profileID.rawValue.isSafeIdentifier else {
            throw CredentialStoreError.unsafeProfileID(profileID)
        }

        let fileManager = FileManager.default
        let credentialsRootURL = rootDirectoryURL
            .appendingPathComponent("Credentials", isDirectory: true)
        let finalDirectoryURL = credentialsRootURL
            .appendingPathComponent(profileID.rawValue, isDirectory: true)
        guard !fileManager.fileExists(atPath: finalDirectoryURL.path) else {
            throw CredentialStoreError.profileAlreadyExists(profileID)
        }

        let stagingDirectoryURL = credentialsRootURL
            .appendingPathComponent(".staging-\(UUID())", isDirectory: true)

        do {
            try createPrivateDirectory(credentialsRootURL, fileManager: fileManager)
            try createPrivateDirectory(stagingDirectoryURL, fileManager: fileManager)

            for role in TLSCredentialRole.allCases {
                let data = switch role {
                case .certificateAuthority: certificates.authorityPEM
                case .clientCertificate: certificates.clientChainPEM
                }
                guard !data.isEmpty else {
                    throw CredentialStoreError.emptyFile(role.storedFileName)
                }

                let destinationURL = stagingDirectoryURL
                    .appendingPathComponent(role.storedFileName, isDirectory: false)
                try data.write(to: destinationURL, options: .atomic)
                try protectFile(at: destinationURL, fileManager: fileManager)
            }

            try excludeFromBackup(stagingDirectoryURL)
            try fileManager.moveItem(
                at: stagingDirectoryURL,
                to: finalDirectoryURL
            )
        } catch let error as CredentialStoreError {
            try? fileManager.removeItem(at: stagingDirectoryURL)
            throw error
        } catch {
            try? fileManager.removeItem(at: stagingDirectoryURL)
            throw CredentialStoreError.writeFailed(error.localizedDescription)
        }

        let relativeDirectory = "Credentials/\(profileID.rawValue)"
        return TLSCredentialPaths(
            caCertificatePath: "\(relativeDirectory)/\(TLSCredentialRole.certificateAuthority.storedFileName)",
            clientCertificatePath: "\(relativeDirectory)/\(TLSCredentialRole.clientCertificate.storedFileName)",
            clientPrivateKeyPath: Self.deviceKeyPath
        )
    }

    func removeCredentials(for profileID: TLSProfileID) throws {
        let directoryURL = rootDirectoryURL
            .appendingPathComponent("Credentials", isDirectory: true)
            .appendingPathComponent(profileID.rawValue, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: directoryURL)
        } catch {
            throw CredentialStoreError.removeFailed(error.localizedDescription)
        }
    }

    func fileURL(for relativePath: String) throws -> URL {
        let resolvedURL = rootDirectoryURL
            .appendingPathComponent(relativePath, isDirectory: false)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = rootDirectoryURL.standardizedFileURL
            .resolvingSymlinksInPath().path + "/"

        guard resolvedURL.path.hasPrefix(rootPath) else {
            throw CredentialStoreError.unsafeRelativePath(relativePath)
        }

        return resolvedURL
    }

    private func createPrivateDirectory(
        _ url: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
    }

    private func protectFile(
        at url: URL,
        fileManager: FileManager
    ) throws {
        var attributes: [FileAttributeKey: Any] = [
            .posixPermissions: 0o600,
        ]
#if os(iOS)
        attributes[.protectionKey] = FileProtectionType.complete
#endif
        try fileManager.setAttributes(attributes, ofItemAtPath: url.path)
    }

    private func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try mutableURL.setResourceValues(resourceValues)
    }
}

nonisolated enum CredentialStoreError: Error, Equatable, LocalizedError, Sendable {
    case missingDeviceKey
    case notARegularFile(String)
    case emptyFile(String)
    case fileTooLarge(String)
    case readFailed(fileName: String, detail: String)
    case profileAlreadyExists(TLSProfileID)
    case unsafeProfileID(TLSProfileID)
    case unsafeRelativePath(String)
    case writeFailed(String)
    case removeFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingDeviceKey:
            "The saved device private key is missing."
        case let .notARegularFile(fileName):
            "'\(fileName)' is not a regular file."
        case let .emptyFile(fileName):
            "'\(fileName)' is empty."
        case let .fileTooLarge(fileName):
            "'\(fileName)' exceeds the 10 MB credential-file limit."
        case let .readFailed(fileName, detail):
            "'\(fileName)' could not be read: \(detail)"
        case let .profileAlreadyExists(profileID):
            "Credentials for TLS profile '\(profileID.rawValue)' already exist."
        case let .unsafeProfileID(profileID):
            "TLS profile ID '\(profileID.rawValue)' cannot be used for credential storage."
        case let .unsafeRelativePath(path):
            "Credential path '\(path)' leaves the application directory."
        case let .writeFailed(detail):
            "Credentials could not be saved: \(detail)"
        case let .removeFailed(detail):
            "Credentials could not be removed: \(detail)"
        }
    }
}
