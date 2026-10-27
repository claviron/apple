import Foundation
import ClavironControlPlane
import Testing
@testable import Claviron

struct CertificateDraftTests {
    @Test
    func hostnamesPutTheCommonNameFirstWithoutBlanksOrRepeats() {
        let draft = CertificateDraft(
            commonName: " example.com ",
            alternates: ["www.example.com", "", "EXAMPLE.com", "api.example.com"]
        )

        #expect(draft.hostnames == ["example.com", "www.example.com", "api.example.com"])
        #expect(draft.action == .add(hostnames: ["example.com", "www.example.com", "api.example.com"]))
    }

    @Test
    func pastedNamesBecomeOneRowEach() {
        var draft = CertificateDraft(
            commonName: "example.org, www.example.org",
            alternates: ["api.example.org cdn.example.org\nimg.example.org", "mail.example.org"]
        )

        draft.expandSeparatedNames()

        #expect(draft.commonName == "example.org")
        #expect(draft.alternates == [
            "www.example.org",
            "api.example.org",
            "cdn.example.org",
            "img.example.org",
            "mail.example.org",
        ])
    }

    @Test
    func aSingleNameIsLeftAsTyped() {
        var draft = CertificateDraft(commonName: "example.org ", alternates: ["www."])

        draft.expandSeparatedNames()

        #expect(draft.commonName == "example.org ")
        #expect(draft.alternates == ["www."])
    }

    @Test
    func furtherNamesDoNotStandInForAMissingCommonName() {
        #expect(CertificateDraft(commonName: " ", alternates: ["www.example.com"]).action == nil)
        #expect(CertificateDraft().action == nil)
    }

    @Test
    func attachingAnExistingCertificateIsNotReportedAsIssuance() {
        let attached = CertificateActionOutcome.succeeded(
            .add(hostnames: ["example.com"]),
            .added(id: 7, attachedExisting: true)
        )

        #expect(!attached.isFailure)
        #expect(attached.summary.contains("existing certificate"))
    }

    @Test
    func serverRefusalIsAFailure() {
        let refused = CertificateActionOutcome.succeeded(
            .remove(commonName: "example.com"),
            .operation(success: false, message: nil)
        )

        #expect(refused.isFailure)
    }
}

struct LocalCertificateDraftTests {
    @Test
    func validityIsRequiredAndNeverDefaulted() {
        var draft = LocalCertificateDraft()
        draft.names.commonName = "service.example.test"
        #expect(draft.action == nil)

        draft.validityDays = "0"
        #expect(draft.action == nil)

        draft.validityDays = "90"
        #expect(draft.request?.validityDays == 90)
    }

    @Test
    func furtherNamesBelongToServerCertificatesOnly() {
        var draft = LocalCertificateDraft()
        draft.names = CertificateDraft(commonName: "a.example.test", alternates: ["b.example.test"])
        draft.validityDays = "30"
        #expect(draft.request?.aliases == ["b.example.test"])

        draft.kind = .client
        #expect(draft.request?.aliases == [])
        #expect(draft.request?.kind == .client)
    }

    @Test
    func authorityNeedsAPathLength() {
        var draft = LocalCertificateDraft(kind: .ca)
        draft.names.commonName = "Example Issuing CA"
        draft.validityDays = "365"
        #expect(draft.action == nil)

        draft.caPathLength = "0"
        #expect(draft.request == LocalCertificateRequest(
            commonName: "Example Issuing CA",
            aliases: [],
            validityDays: 365,
            kind: .ca,
            caPathLength: 0,
            issuer: nil
        ))
    }

    @Test
    func blankIssuerMeansTheConfiguredAuthority() {
        var draft = LocalCertificateDraft(kind: .client)
        draft.names.commonName = "worker-01"
        draft.validityDays = "30"
        draft.issuer = "  "
        #expect(draft.request?.issuer == nil)

        draft.issuer = " ops-ca "
        #expect(draft.request?.issuer == "ops-ca")
    }

    @Test
    func rootKeepsOptionalSubjectFieldsAbsent() {
        var draft = RootCADraft(commonName: "Internal Root", validityDays: "3650")
        #expect(draft.action == .createRootCA(LocalRootCARequest(
            commonName: "Internal Root",
            validityDays: 3650,
            organization: nil,
            country: nil
        )))

        draft.country = "T"
        #expect(draft.action == nil)

        draft.country = "tr"
        draft.organization = "Liberum"
        #expect(draft.request?.country == "TR")
        #expect(draft.request?.organization == "Liberum")
    }

    @Test
    func expiryPreviewFollowsTheTypedDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = Date(timeIntervalSince1970: 0)

        #expect(ValidityPreview.expiry(days: "", from: start, calendar: calendar) == nil)
        #expect(ValidityPreview.expiry(days: "abc", from: start, calendar: calendar) == nil)
        #expect(ValidityPreview.expiry(days: "10", from: start, calendar: calendar)
            == Date(timeIntervalSince1970: 10 * 86_400))
    }

    @Test
    func localSummaryNamesKindSignerAndThatMaterialStays() {
        let certificate = LocalCertificateObservation(
            id: 7,
            commonName: "worker-01",
            aliases: [],
            issuedAt: nil,
            expiresAt: nil,
            enabled: true,
            kind: .kind(.client),
            issuerID: 3
        )
        #expect(CertificateActionOutcome.summary(local: certificate)
            == "Created a client certificate for worker-01 (certificate 7), signed by certificate 3. Certificate and key stay on the server.")
    }
}
