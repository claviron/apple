import Foundation
import Security

/// One certificate of a PEM chain, as the system decodes it: who it names,
/// who signed it, and until when. Shown so an operator sees the issuer by
/// name and that an intermediate-signed chain carries its intermediate.
nonisolated struct DecodedCertificate: Equatable, Sendable {
    var subject: String
    var issuer: String
    var notAfter: Date?
    var selfSigned: Bool
}

nonisolated enum CertificateChainDecoder {
    /// Every `CERTIFICATE` block of the PEM, in order; a block the system
    /// cannot parse is reported as such rather than dropped.
    static func decode(pem: String) -> [DecodedCertificate] {
        blocks(in: pem).map { der -> DecodedCertificate in
            guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
                return DecodedCertificate(subject: "Unreadable certificate", issuer: "Unknown", notAfter: nil, selfSigned: false)
            }
            let subject = (SecCertificateCopySubjectSummary(certificate) as String?) ?? "Unnamed"
            let (issuer, notAfter) = details(of: certificate)
            return DecodedCertificate(
                subject: subject,
                issuer: issuer ?? "Unknown",
                notAfter: notAfter,
                selfSigned: issuer == subject
            )
        }
    }

    private static func blocks(in pem: String) -> [Data] {
        var blocks: [Data] = []
        var current: [Substring]?
        for line in pem.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("-----BEGIN CERTIFICATE") {
                current = []
            } else if line.hasPrefix("-----END CERTIFICATE") {
                if let body = current, let der = Data(base64Encoded: body.joined()) {
                    blocks.append(der)
                }
                current = nil
            } else {
                current?.append(line)
            }
        }
        return blocks
    }

    /// Issuer common name and expiry. The field reader is macOS's; elsewhere
    /// the subject is all the system offers.
    private static func details(of certificate: SecCertificate) -> (String?, Date?) {
        #if os(macOS)
        let keys = [kSecOIDX509V1IssuerName, kSecOIDX509V1ValidityNotAfter] as CFArray
        guard let values = SecCertificateCopyValues(certificate, keys, nil) as? [String: Any] else {
            return (nil, nil)
        }
        var issuer: String?
        if let field = values[kSecOIDX509V1IssuerName as String] as? [String: Any],
           let parts = field[kSecPropertyKeyValue as String] as? [[String: Any]] {
            let named = parts.first { ($0[kSecPropertyKeyLabel as String] as? String) == (kSecOIDCommonName as String) }
                ?? parts.last
            issuer = named?[kSecPropertyKeyValue as String] as? String
        }
        var notAfter: Date?
        if let field = values[kSecOIDX509V1ValidityNotAfter as String] as? [String: Any],
           let seconds = field[kSecPropertyKeyValue as String] as? Double {
            notAfter = Date(timeIntervalSinceReferenceDate: seconds)
        }
        return (issuer, notAfter)
        #else
        return (nil, nil)
        #endif
    }
}
