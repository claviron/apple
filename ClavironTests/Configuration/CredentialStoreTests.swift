import Foundation
import Testing
@testable import Claviron

struct CredentialStoreTests {
    @Test
    func credentialsAreCopiedIntoPrivateApplicationStorage() async throws {
        try await withTemporaryStore { store, rootDirectoryURL in
            let profileID = TLSProfileID(rawValue: "operator")
            let paths = try await store.install(.valid, for: profileID)

            #expect(paths.caCertificatePath == "Credentials/operator/ca.pem")
            #expect(paths.clientCertificatePath == "Credentials/operator/client.pem")
            #expect(paths.clientPrivateKeyPath == "Credentials/operator/client-key.pem")

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
    func incompleteImportDoesNotCreateProfileDirectory() async throws {
        try await withTemporaryStore { store, rootDirectoryURL in
            let profileID = TLSProfileID(rawValue: "incomplete")
            var credentials = TLSCredentialImport.valid
            credentials.clientPrivateKey = nil

            await #expect(throws: CredentialStoreError.missingCredential(
                .clientPrivateKey
            )) {
                try await store.install(credentials, for: profileID)
            }

            let profileURL = rootDirectoryURL
                .appendingPathComponent("Credentials/incomplete", isDirectory: true)
            #expect(!FileManager.default.fileExists(atPath: profileURL.path))
        }
    }

    @Test
    func existingProfileIsNeverOverwritten() async throws {
        try await withTemporaryStore { store, _ in
            let profileID = TLSProfileID(rawValue: "operator")
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

            await #expect(throws: CredentialStoreError.unsafeProfileID(profileID)) {
                try await store.install(.valid, for: profileID)
            }
        }
    }

    private var expectedCredentialData: [(TLSCredentialRole, Data)] {
        [
            (.certificateAuthority, Data("ca".utf8)),
            (.clientCertificate, Data("certificate".utf8)),
            (.clientPrivateKey, Data("private key".utf8)),
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
