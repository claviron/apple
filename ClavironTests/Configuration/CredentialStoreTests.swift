import CryptoKit
import Foundation
import Testing
@testable import Claviron

struct CredentialStoreTests {
    @Test
    func credentialsAreCopiedIntoPrivateApplicationStorage() async throws {
        try await withTemporaryStore { store, rootDirectoryURL in
            let profileID = TLSProfileID(rawValue: "operator")
            _ = try await store.createDeviceKey(password: nil)
            let paths = try await store.install(.valid, for: profileID)

            #expect(paths.caCertificatePath == "Credentials/operator/ca.pem")
            #expect(paths.clientCertificatePath == "Credentials/operator/client.pem")
            #expect(paths.clientPrivateKeyPath == CredentialStore.deviceKeyPath)

            for (role, expected) in expectedCredentialData {
                let relativePath = "Credentials/operator/\(role.storedFileName)"
                let fileURL = try await store.fileURL(for: relativePath)
                #expect(fileURL.path.hasPrefix(rootDirectoryURL.path))
                #expect(try Data(contentsOf: fileURL) == expected)

                let attributes = try FileManager.default.attributesOfItem(
                    atPath: fileURL.path
                )
                #expect(attributes[.posixPermissions] as? Int == 0o600)
            }
        }
    }

    @Test
    func profilesShareTheSameDeviceKeyAcrossStoreInstances() async throws {
        try await withTemporaryStore { store, rootDirectoryURL in
            let key = try await store.createDeviceKey(password: nil)
            let first = TLSProfileID(rawValue: "first")
            let firstPaths = try await store.install(.valid, for: first)
            let reopened = CredentialStore(rootDirectoryURL: rootDirectoryURL)
            guard case let .unencrypted(reusedKey)? = try await reopened.loadDeviceKey() else {
                Issue.record("Expected the saved device key")
                return
            }
            let secondPaths = try await reopened.install(.valid, for: TLSProfileID(rawValue: "second"))
            #expect(key.publicKey.derRepresentation == reusedKey.publicKey.derRepresentation)
            #expect(firstPaths.clientPrivateKeyPath == secondPaths.clientPrivateKeyPath)
            #expect(firstPaths.clientCertificatePath != secondPaths.clientCertificatePath)
            #expect(firstPaths.caCertificatePath != secondPaths.caCertificatePath)

            try await reopened.removeCredentials(for: first)
            guard case let .unencrypted(retainedKey)? = try await reopened.loadDeviceKey() else {
                Issue.record("Deleting a TLS profile removed its shared device key")
                return
            }
            #expect(key.publicKey.derRepresentation == retainedKey.publicKey.derRepresentation)
            let url = try await reopened.fileURL(for: secondPaths.clientPrivateKeyPath)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            #expect(attributes[.posixPermissions] as? Int == 0o600)

            try FileManager.default.removeItem(at: url)
            #expect(try await reopened.loadDeviceKey() == nil)
        }
    }

    @Test
    func existingProfileIsNeverOverwritten() async throws {
        try await withTemporaryStore { store, _ in
            let profileID = TLSProfileID(rawValue: "operator")
            _ = try await store.createDeviceKey(password: nil)
            _ = try await store.install(.valid, for: profileID)

            await #expect(throws: CredentialStoreError.profileAlreadyExists(profileID)) {
                try await store.install(.valid, for: profileID)
            }
        }
    }

    @Test
    func resolvedCredentialPathCannotEscapeApplicationStorage() async throws {
        try await withTemporaryStore { store, _ in
            await #expect(throws: CredentialStoreError.unsafeRelativePath("../secret")) {
                try await store.fileURL(for: "../secret")
            }
        }
    }

    @Test
    func profileIDCannotEscapeCredentialStorage() async throws {
        try await withTemporaryStore { store, _ in
            let profileID = TLSProfileID(rawValue: "../outside")
            _ = try await store.createDeviceKey(password: nil)

            await #expect(throws: CredentialStoreError.unsafeProfileID(profileID)) {
                try await store.install(.valid, for: profileID)
            }
        }
    }

    private var expectedCredentialData: [(TLSCredentialRole, Data)] {
        [
            (.certificateAuthority, Data("ca".utf8)),
            (.clientCertificate, Data("certificate".utf8)),
        ]
    }

    private func withTemporaryStore(
        _ operation: (CredentialStore, URL) async throws -> Void
    ) async throws {
        let rootDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClavironCredentialTests-\(UUID())", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootDirectoryURL)
        }

        try await operation(
            CredentialStore(rootDirectoryURL: rootDirectoryURL),
            rootDirectoryURL
        )
    }
}
