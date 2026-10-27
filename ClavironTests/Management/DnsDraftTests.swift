import ClavironControlPlane
import Testing
@testable import Claviron

struct DnsDraftTests {
    @Test
    func newZoneDoesNotInventTimers() {
        var draft = DnsZoneDraft()
        draft.domain = "example.com"
        draft.mname = "ns1.example.com"
        draft.rname = "hostmaster.example.com"

        #expect(draft.configuration == nil)
        #expect(draft.issue == "Refresh is required.")
    }

    @Test
    func zoneDraftRoundTripsAStoredZone() {
        let stored = DnsZoneConfiguration(
            domain: "example.com",
            soa: DnsSOAConfiguration(
                mname: "ns1.example.com",
                rname: "hostmaster.example.com",
                refresh: 7_200,
                retry: 3_600,
                expire: 1_209_600,
                minimum: 300
            ),
            enabled: false
        )

        #expect(DnsZoneDraft(stored).configuration == stored)
    }

    @Test
    func zoneDraftTrimsAndRejectsNonNumbers() {
        var draft = DnsZoneDraft()
        draft.domain = "  example.com "
        draft.mname = "ns1.example.com"
        draft.rname = "hostmaster.example.com"
        draft.refresh = "1h"
        draft.retry = "60"
        draft.expire = "60"
        draft.minimum = "60"

        #expect(draft.issue == "Refresh must be a whole number.")

        draft.refresh = " 600 "
        #expect(draft.configuration?.domain == "example.com")
        #expect(draft.configuration?.soa?.refresh == 600)
    }

    @Test
    func recordDraftKeepsZeroDistinctFromEmpty() {
        var draft = DnsRecordDraft()
        draft.name = "_sip._tcp"
        draft.type = "srv"
        draft.value = "sip.example.com"
        draft.ttl = "300"
        draft.priority = "10"
        draft.weight = "0"

        let configuration = draft.configuration
        #expect(configuration?.type == "SRV")
        #expect(configuration?.weight == 0)
        #expect(configuration?.port == nil)
    }

    @Test
    func recordDraftRequiresTTL() {
        var draft = DnsRecordDraft()
        draft.name = "@"
        draft.value = "192.0.2.1"

        #expect(draft.issue == "TTL is required.")
    }

    @Test
    func recordDraftOffersAStoredUnknownType() {
        let draft = DnsRecordDraft(DnsRecordConfiguration(
            name: "@", type: "SSHFP", value: "1 1 abcd", ttl: 300,
            priority: nil, weight: nil, port: nil, enabled: true
        ))

        #expect(draft.typeChoices.last == "SSHFP")
        #expect(draft.configuration?.type == "SSHFP")
    }

    @Test
    func outcomeSummariesDoNotAskForAManualReload() {
        let zone = DnsZoneObservation(id: 1, configuration: nil, serial: 3)

        #expect(!DnsActionOutcome.summary(.zone(zone)).contains("Reload DNS"))
        #expect(DnsActionOutcome.summary(.zone(zone)).contains("serial 3"))
        #expect(DnsActionOutcome.isAccepted(.reload(accepted: false)) == false)
    }
}
