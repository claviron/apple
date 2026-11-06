import CommonCrypto
import CryptoKit
import Foundation
import Security

nonisolated enum PrivateKeyProtection {
    private static let header = "-----BEGIN ENCRYPTED PRIVATE KEY-----"
    private static let footer = "-----END ENCRYPTED PRIVATE KEY-----"
    private static let rounds: UInt32 = 600_000
    private static let saltSize = 16
    private static let ivSize = kCCBlockSizeAES128
    private static let pbes2 = Data([0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x05, 0x0d])
    private static let pbkdf2 = Data([0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x05, 0x0c])
    private static let hmacSHA256 = Data([0x06, 0x08, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x02, 0x09])
    private static let aes256CBC = Data([0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x01, 0x2a])

    static func isEncrypted(_ pem: String) -> Bool {
        pem.hasPrefix(header)
    }

    static func encrypt(_ key: P256.Signing.PrivateKey, password: String) throws -> Data {
        let salt = try randomBytes(count: saltSize)
        let iv = try randomBytes(count: ivSize)
        let encryptionKey = try derive(password, salt: salt)
        let ciphertext = try crypt(CCOperation(kCCEncrypt), key.derRepresentation, key: encryptionKey, iv: iv)
        let wrapped = DER.encode(0x30, algorithm(salt: salt, iv: iv) + DER.encode(0x04, ciphertext))
        let body = wrapped.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return Data("\(header)\n\(body)\n\(footer)\n".utf8)
    }

    static func decrypt(_ pem: String, password: String) throws -> P256.Signing.PrivateKey {
        guard pem.hasPrefix(header),
              let end = pem.range(of: footer, options: .backwards),
              pem[end.upperBound...].allSatisfy(\.isWhitespace),
              let wrapped = Data(base64Encoded: pem[..<end.lowerBound].dropFirst(header.count).filter { !$0.isWhitespace }) else {
            throw DeviceKeyError.invalidProtection
        }

        var envelope = DER.Reader(wrapped)
        var contents = DER.Reader(try envelope.read(0x30))
        let encodedAlgorithm = try contents.read(0x30)
        let ciphertext = try contents.read(0x04)
        guard envelope.isEmpty, contents.isEmpty, !ciphertext.isEmpty,
              ciphertext.count.isMultiple(of: ivSize) else {
            throw DeviceKeyError.invalidProtection
        }

        var identifier = DER.Reader(encodedAlgorithm)
        _ = try identifier.read(0x06)
        var scheme = DER.Reader(try identifier.read(0x30))
        var kdf = DER.Reader(try scheme.read(0x30))
        var cipher = DER.Reader(try scheme.read(0x30))
        _ = try kdf.read(0x06)
        _ = try cipher.read(0x06)
        var kdfParameters = DER.Reader(try kdf.read(0x30))
        let salt = try kdfParameters.read(0x04)
        let iv = try cipher.read(0x04)
        // Accept only the PBES2 profile emitted by this app, including its work factor.
        guard salt.count == saltSize, iv.count == ivSize,
              DER.encode(0x30, encodedAlgorithm) == algorithm(salt: salt, iv: iv) else {
            throw DeviceKeyError.invalidProtection
        }

        let encryptionKey = try derive(password, salt: salt)
        do {
            let der = try crypt(CCOperation(kCCDecrypt), ciphertext, key: encryptionKey, iv: iv)
            return try P256.Signing.PrivateKey(derRepresentation: der)
        } catch {
            throw DeviceKeyError.incorrectPassword
        }
    }

    private static func algorithm(salt: Data, iv: Data) -> Data {
        let count = Data([UInt8(truncatingIfNeeded: rounds >> 16), UInt8(truncatingIfNeeded: rounds >> 8), UInt8(truncatingIfNeeded: rounds)])
        let prf = DER.encode(0x30, hmacSHA256 + Data([0x05, 0x00]))
        let kdf = DER.encode(0x30, pbkdf2 + DER.encode(0x30, DER.encode(0x04, salt) + DER.encode(0x02, count) + prf))
        let cipher = DER.encode(0x30, aes256CBC + DER.encode(0x04, iv))
        return DER.encode(0x30, pbes2 + DER.encode(0x30, kdf + cipher))
    }

    private static func randomBytes(count: Int) throws -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw DeviceKeyError.protectionFailed }
        return bytes
    }

    private static func derive(_ password: String, salt: Data) throws -> Data {
        guard !password.isEmpty else { throw DeviceKeyError.incorrectPassword }
        let passwordBytes = Data(password.utf8)
        var key = Data(count: kCCKeySizeAES256)
        let status = key.withUnsafeMutableBytes { output in
            passwordBytes.withUnsafeBytes { input in
                salt.withUnsafeBytes { salt in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        input.bindMemory(to: CChar.self).baseAddress, input.count,
                        salt.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                        output.bindMemory(to: UInt8.self).baseAddress, output.count
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw DeviceKeyError.protectionFailed }
        return key
    }

    private static func crypt(_ operation: CCOperation, _ data: Data, key: Data, iv: Data) throws -> Data {
        var output = Data(count: data.count + ivSize)
        var written = 0
        let status = output.withUnsafeMutableBytes { output in
            data.withUnsafeBytes { input in
                key.withUnsafeBytes { key in
                    iv.withUnsafeBytes { iv in
                        CCCrypt(
                            operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            key.baseAddress, key.count, iv.baseAddress, input.baseAddress, input.count,
                            output.baseAddress, output.count, &written
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw DeviceKeyError.protectionFailed }
        output.removeSubrange(written..<output.count)
        return output
    }
}

nonisolated enum DER {
    static func encode(_ tag: UInt8, _ payload: Data) -> Data {
        var length = payload.count
        if length < 128 {
            return Data([tag, UInt8(length)]) + payload
        }
        var lengthBytes: [UInt8] = []
        while length > 0 {
            lengthBytes.append(UInt8(truncatingIfNeeded: length))
            length >>= 8
        }
        return Data([tag, 0x80 | UInt8(lengthBytes.count)]) + Data(lengthBytes.reversed()) + payload
    }

    struct Reader {
        private var bytes: Data

        init(_ bytes: Data) {
            self.bytes = bytes
        }

        var isEmpty: Bool { bytes.isEmpty }

        mutating func read(_ tag: UInt8) throws -> Data {
            guard bytes.popFirst() == tag, let initialLength = bytes.popFirst() else {
                throw DeviceKeyError.invalidProtection
            }
            var length = Int(initialLength)
            if initialLength >= 128 {
                let lengthCount = Int(initialLength & 0x7f)
                guard (1...2).contains(lengthCount), lengthCount <= bytes.count else {
                    throw DeviceKeyError.invalidProtection
                }
                length = 0
                for _ in 0..<lengthCount {
                    length = (length << 8) | Int(bytes.removeFirst())
                }
            }
            guard length <= bytes.count else { throw DeviceKeyError.invalidProtection }
            let value = bytes.prefix(length)
            bytes = bytes.dropFirst(length)
            return value
        }
    }
}

nonisolated enum DeviceKeyError: Equatable, LocalizedError {
    case alreadyExists
    case locked
    case incorrectPassword
    case invalidProtection
    case protectionFailed

    var errorDescription: String? {
        switch self {
        case .alreadyExists: "A device key already exists."
        case .locked: "Unlock the device key in Settings before connecting."
        case .incorrectPassword: "The private key password is incorrect."
        case .invalidProtection: "The encrypted private key has an unsupported format."
        case .protectionFailed: "The private key could not be protected."
        }
    }
}
