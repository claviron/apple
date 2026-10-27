import Testing
@testable import ClavironControlPlane

@Suite("Certificate observation mapping")
struct CertificateObservationMappingTests {
    @Test("PEM transfer preserves inputs and private key export is explicit")
    func transfers() {
        let request = DirectClavironClient.importMessage(chain: "chain\n", privateKey: "key\n", issuer: nil)
        #expect(request.certificateChainPem == "chain\n")
        #expect(request.privateKeyPem == "key\n")
        #expect(!request.hasIssuer)
        #expect(DirectClavironClient.importMessage(chain: "c", privateKey: "k", issuer: "Example CA").issuer == "Example CA")
        #expect(!DirectClavironClient.exportMessage(commonName: "Example CA", includePrivateKey: false).includePrivateKey)
        #expect(DirectClavironClient.exportMessage(commonName: "Example CA", includePrivateKey: true).includePrivateKey)
        var response = Claviron_Certificates_ExportCertificateResponse()
        response.certificateChainPem = "chain"
        #expect(DirectClavironClient.exportReceipt(response, includePrivateKey: true) == .exported(chain: "chain", privateKey: nil))
        response.privateKeyPem = "key"
        #expect(DirectClavironClient.exportReceipt(response, includePrivateKey: false) == .exported(chain: "chain", privateKey: nil))
        #expect(DirectClavironClient.exportReceipt(response, includePrivateKey: true) == .exported(chain: "chain", privateKey: "key"))
    }

    @Test("Inventory usage roles preserve unknown and missing values")
    func inventoryRoles() {
        #expect(DirectClavironClient.inventoryKind(.ca) == .kind(.ca))
        #expect(DirectClavironClient.inventoryKind(.server) == .kind(.server))
        #expect(DirectClavironClient.inventoryKind(.client) == .kind(.client))
        #expect(DirectClavironClient.inventoryKind(.unspecified) == .unspecified)
        #expect(DirectClavironClient.inventoryKind(.UNRECOGNIZED(99)) == .unrecognized(99))
        var generated = Claviron_Acme_CertificateInventoryInfo()
        generated.certificate.kind = .client
        #expect(DirectClavironClient.hostedCertificateObservation(generated).certificate?.kind == .kind(.client))
    }

    @Test("Certificate dates, aliases, state, and server attachment are preserved")
    func certificateFactsArePreserved() {
        var generated = Claviron_Acme_CertificateInventoryInfo()
        generated.certificate.id = 7
        generated.certificate.cname = "example.test"
        generated.certificate.aliases = ["example.test", "www.example.test"]
        generated.certificate.issuedAt.seconds = 100
        generated.certificate.issuedAt.nanos = 123
        generated.certificate.expiresAt.seconds = 200
        generated.certificate.updatedAt.seconds = 150
        generated.certificate.revokedAt.seconds = 175
        generated.certificate.enabled = false

        var server = Claviron_Acme_ServerInfo()
        server.id = 9
        server.name = "edge"
        server.enabled = true
        generated.servers = [server]

        let hosted = DirectClavironClient.hostedCertificateObservation(generated)

        #expect(hosted.certificate == CertificateObservation(
            id: 7,
            commonName: "example.test",
            aliases: ["example.test", "www.example.test"],
            issuedAt: ProtobufTimestampObservation(seconds: 100, nanoseconds: 123),
            expiresAt: ProtobufTimestampObservation(seconds: 200, nanoseconds: 0),
            updatedAt: ProtobufTimestampObservation(seconds: 150, nanoseconds: 0),
            enabled: false,
            revokedAt: ProtobufTimestampObservation(seconds: 175, nanoseconds: 0)
        ))
        #expect(hosted.servers == [
            CertificateServerObservation(id: 9, name: "edge", enabled: true),
        ])
    }

    @Test("Missing certificate and missing dates remain absent")
    func absenceRemainsExplicit() {
        var generated = Claviron_Acme_CertificateInventoryInfo()
        var certificate = Claviron_Acme_CertificateResponse()
        certificate.cname = "undated.test"

        let missingCertificate = DirectClavironClient.hostedCertificateObservation(generated)
        generated.certificate = certificate
        let undatedCertificate = DirectClavironClient.hostedCertificateObservation(generated)

        #expect(missingCertificate.certificate == nil)
        #expect(undatedCertificate.certificate?.issuedAt == nil)
        #expect(undatedCertificate.certificate?.expiresAt == nil)
        #expect(undatedCertificate.certificate?.updatedAt == nil)
        #expect(undatedCertificate.certificate?.revokedAt == nil)
    }

    @Test("Invalid nanoseconds remain inspectable instead of becoming a date")
    func invalidTimestampRemainsRaw() {
        let timestamp = ProtobufTimestampObservation(seconds: 100, nanoseconds: -1)
        let outOfRange = ProtobufTimestampObservation(
            seconds: 253_402_300_800,
            nanoseconds: 0
        )

        #expect(timestamp.date == nil)
        #expect(timestamp.seconds == 100)
        #expect(timestamp.nanoseconds == -1)
        #expect(outOfRange.date == nil)
    }

    @Test("Certificate removal keeps the server's outcome sentence")
    func removalReceiptIsPreserved() {
        var removed = Claviron_Acme_OperationResponse()
        removed.success = true
        removed.message = "Certificate 'example.test' permanently deleted"

        #expect(DirectClavironClient.certificateOperationReceipt(removed) == .operation(
            success: true,
            message: "Certificate 'example.test' permanently deleted"
        ))
        #expect(DirectClavironClient.certificateOperationReceipt(Claviron_Acme_OperationResponse())
            == .operation(success: false, message: nil))
    }

    @Test("Local CA requests send only the optional fields that are present")
    func localRequestsKeepPresence() {
        let renewal = DirectClavironClient.renewalMessage(commonName: "Example CA", validityDays: 42)
        #expect(renewal.commonName == "Example CA")
        #expect(renewal.validityDays == 42)
        let client = DirectClavironClient.localCertificateMessage(LocalCertificateRequest(
            commonName: "operator",
            aliases: [],
            validityDays: 365,
            kind: .client,
            caPathLength: nil,
            issuer: nil
        ))
        #expect(client.kind == .client)
        #expect(client.validityDays == 365)
        #expect(!client.hasCaPathLen)
        #expect(!client.hasIssuer)

        let intermediate = DirectClavironClient.localCertificateMessage(LocalCertificateRequest(
            commonName: "Ops CA",
            aliases: [],
            validityDays: 1_825,
            kind: .ca,
            caPathLength: 0,
            issuer: "root"
        ))
        #expect(intermediate.kind == .ca)
        #expect(intermediate.hasCaPathLen && intermediate.caPathLen == 0)
        #expect(intermediate.issuer == "root")

        let root = DirectClavironClient.rootCAMessage(LocalRootCARequest(
            commonName: "Claviron Root",
            validityDays: 3_650,
            organization: nil,
            country: "TR"
        ))
        #expect(!root.hasOrganization)
        #expect(root.country == "TR")
    }

    @Test("A self-signed root reports no issuer, an issued certificate does")
    func localObservationKeepsIssuerPresence() {
        var root = Claviron_Mtls_CertificateInfo()
        root.id = 1
        root.commonName = "Claviron Root"
        root.kind = .ca
        #expect(DirectClavironClient.localCertificateObservation(root).issuerID == nil)
        #expect(DirectClavironClient.localCertificateObservation(root).kind == .kind(.ca))

        var issued = Claviron_Mtls_CertificateInfo()
        issued.id = 2
        issued.kind = .server
        issued.issuerID = 1
        issued.aliases = ["api.example.test"]
        let observed = DirectClavironClient.localCertificateObservation(issued)
        #expect(observed.issuerID == 1)
        #expect(observed.kind == .kind(.server))
        #expect(observed.aliases == ["api.example.test"])
    }
}
