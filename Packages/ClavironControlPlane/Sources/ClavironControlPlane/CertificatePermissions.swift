import Foundation
import NIOSSL

/// Exact permission names declared by a certificate, separate from user grants.
public struct CertificatePermissions: Equatable, Sendable {
    public let names: [String]

    public init(names: [String]) throws {
        guard names.allSatisfy(Self.isValidName) else {
            throw ManagementClientError("Permission names must match [A-Za-z0-9][A-Za-z0-9._-]*.")
        }
        self.names = Array(Set(names)).sorted()
    }

    /// Read only the leaf's signed URI SAN. Absence differs from an empty scope.
    public static func read(pem: String) throws -> Self? {
        guard let certificate = try NIOSSLCertificate.fromPEMBytes(Array(pem.utf8)).first else {
            throw ManagementClientError("The certificate could not be read.")
        }
        let namespace = "urn:claviron:permissions:"
        let prefix = namespace + "v1:"
        let declarations = certificate._subjectAlternativeNames().compactMap { name -> String? in
            guard name.nameType == .uri else { return nil }
            let uri = String(decoding: name.contents, as: UTF8.self)
            return uri.hasPrefix(namespace) ? uri : nil
        }
        guard !declarations.isEmpty else { return nil }
        guard declarations.count == 1, let uri = declarations.first, uri.hasPrefix(prefix) else {
            throw ManagementClientError("The certificate has an unsupported or duplicate permission declaration.")
        }
        let payload = uri.dropFirst(prefix.count)
        return try Self(names: payload.isEmpty ? [] : payload.split(separator: ",", omittingEmptySubsequences: false).map(String.init))
    }

    private static func isValidName(_ name: String) -> Bool {
        func alphanumeric(_ byte: UInt8) -> Bool {
            (65 ... 90).contains(byte) || (97 ... 122).contains(byte) || (48 ... 57).contains(byte)
        }
        guard let first = name.utf8.first, alphanumeric(first) else { return false }
        return name.utf8.allSatisfy { alphanumeric($0) || $0 == 46 || $0 == 95 || $0 == 45 }
    }
}
