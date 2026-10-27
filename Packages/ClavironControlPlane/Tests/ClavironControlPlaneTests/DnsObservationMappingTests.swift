import Testing
@testable import ClavironControlPlane

@Suite("DNS observation mapping")
struct DnsObservationMappingTests {
    @Test("Zone and SOA facts are preserved")
    func zoneFactsArePreserved() {
        var generated = Claviron_Dns_ZoneInfo()
        generated.id = 4
        generated.serial = 2026100301
        generated.config.domain = "example.test"
        generated.config.enabled = true
        generated.config.soa.mname = "ns1.example.test"
        generated.config.soa.rname = "hostmaster.example.test"
        generated.config.soa.refresh = 7_200
        generated.config.soa.retry = 3_600
        generated.config.soa.expire = 1_209_600
        generated.config.soa.minimum = 300

        let zone = DirectClavironClient.dnsZoneObservation(generated)

        #expect(zone == DnsZoneObservation(
            id: 4,
            configuration: DnsZoneConfiguration(
                domain: "example.test",
                soa: DnsSOAConfiguration(
                    mname: "ns1.example.test",
                    rname: "hostmaster.example.test",
                    refresh: 7_200,
                    retry: 3_600,
                    expire: 1_209_600,
                    minimum: 300
                ),
                enabled: true
            ),
            serial: 2026100301
        ))
    }

    @Test("Absent zone configuration and SOA remain absent")
    func absentZonePartsRemainAbsent() {
        var withoutConfig = Claviron_Dns_ZoneInfo()
        withoutConfig.id = 1
        #expect(DirectClavironClient.dnsZoneObservation(withoutConfig).configuration == nil)

        var withoutSOA = Claviron_Dns_ZoneInfo()
        withoutSOA.config.domain = "example.test"
        #expect(DirectClavironClient.dnsZoneObservation(withoutSOA).configuration?.soa == nil)
    }

    @Test("SRV weight zero stays distinct from an absent weight")
    func optionalRecordFieldsKeepPresence() {
        var generated = Claviron_Dns_RecordInfo()
        generated.id = 9
        generated.zone = "example.test"
        generated.config.name = "_sip._tcp"
        generated.config.type = "SRV"
        generated.config.value = "sip.example.test"
        generated.config.ttl = 300
        generated.config.priority = 10
        generated.config.weight = 0
        generated.config.enabled = true

        let record = DirectClavironClient.dnsRecordObservation(generated)

        #expect(record.configuration?.weight == 0)
        #expect(record.configuration?.priority == 10)
        #expect(record.configuration?.port == nil)
    }

    @Test("Record writes send only the optional fields that are present")
    func recordMessageKeepsPresence() {
        let message = DirectClavironClient.dnsRecordConfigMessage(DnsRecordConfiguration(
            name: "_sip._tcp",
            type: "SRV",
            value: "sip.example.test",
            ttl: 300,
            priority: 10,
            weight: 0,
            port: nil,
            enabled: false
        ))

        #expect(message.hasPriority && message.priority == 10)
        #expect(message.hasWeight && message.weight == 0)
        #expect(!message.hasPort)
        #expect(!message.enabled)
    }

    @Test("A zone write without SOA is refused before transport")
    func zoneWriteRequiresSOA() {
        #expect(throws: ClavironClientFailure.self) {
            try DirectClavironClient.dnsZoneConfigMessage(DnsZoneConfiguration(
                domain: "example.test",
                soa: nil,
                enabled: true
            ))
        }
    }

    @Test("A removed zone reports no serial, a removed record reports one")
    func removalSerialPresence() {
        var zoneRemoved = Claviron_Dns_MutationResponse()
        zoneRemoved.zone = "example.test"
        #expect(DirectClavironClient.dnsRemovalReceipt(zoneRemoved) == .removed(
            zone: "example.test",
            zoneSerial: nil
        ))

        var recordRemoved = Claviron_Dns_MutationResponse()
        recordRemoved.zone = "example.test"
        recordRemoved.zoneSerial = 7
        #expect(DirectClavironClient.dnsRemovalReceipt(recordRemoved) == .removed(
            zone: "example.test",
            zoneSerial: 7
        ))
    }
}
