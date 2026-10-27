import ClavironControlPlane
import Foundation
import Testing
@testable import Claviron

@Suite("Certificate transfer presentation")
struct CertificateTransferTests {
    private func certificate(_ kind: ReportedLocalCertificateKind) -> CertificateObservation {
        CertificateObservation(id: 1, commonName: "Not a hostname CA", aliases: [],
                               issuedAt: nil, expiresAt: nil, updatedAt: nil,
                               enabled: true, kind: kind)
    }

    @Test("Tabs use server-reported kind, never CN or server assignment")
    func groups() {
        #expect(CertificateGroup.ca.contains(certificate(.kind(.ca))))
        #expect(!CertificateGroup.server.contains(certificate(.kind(.ca))))
        #expect(CertificateGroup.client.contains(certificate(.kind(.client))))
        #expect(CertificateGroup.server.contains(certificate(.kind(.server))))
        // An unreported or unrecognized kind belongs to no typed tab; only All shows it.
        #expect(!CertificateGroup.ca.contains(certificate(.unrecognized(99))))
        #expect(!CertificateGroup.server.contains(nil))
        #expect(CertificateGroup.all.contains(nil))
    }

    @Test("PEM export preserves exact UTF-8 bytes")
    func document() {
        let pem = "-----BEGIN CERTIFICATE-----\nYWJj\n-----END CERTIFICATE-----\n"
        #expect(CertificatePEMDocument(pem: pem).data == Data(pem.utf8))
    }
}
