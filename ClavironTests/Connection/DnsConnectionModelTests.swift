import ClavironControlPlane
import Foundation
import Testing
@testable import Claviron

@MainActor
struct DnsConnectionModelTests {
    private let serviceSnapshot = ServiceFleetSnapshot(
        capturedAt: Date(timeIntervalSince1970: 100),
        membersExpected: 1,
        membersReporting: 1,
        services: []
    )

    private static let zone = DnsZoneObservation(
        id: 1,
        configuration: DnsZoneConfiguration(
            domain: "example.com",
            soa: DnsSOAConfiguration(
                mname: "ns1.example.com",
                rname: "hostmaster.example.com",
                refresh: 7_200,
                retry: 3_600,
                expire: 1_209_600,
                minimum: 300
            ),
            enabled: true
        ),
        serial: 1
    )

    private static let record = DnsRecordObservation(
        id: 5,
        zone: "example.com",
        configuration: DnsRecordConfiguration(
            name: "@", type: "A", value: "192.0.2.1", ttl: 300,
            priority: nil, weight: nil, port: nil, enabled: true
        )
    )

    @Test
    func recordWriteRefreshesZonesAndThatZonesRecords() async throws {
        let model = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let afterWrite = DnsInventorySnapshot(zones: [
            DnsZoneObservation(id: 1, configuration: Self.zone.configuration, serial: 2),
        ])
        let client = MockClavironClient(
            results: [.success(serviceSnapshot)],
            dnsZoneResults: [.success(DnsInventorySnapshot(zones: [Self.zone])), .success(afterWrite)],
            dnsRecordResults: [.success(DnsRecordsSnapshot(zone: "example.com", records: [Self.record]))],
            dnsActionResults: [.success(.record(Self.record, zoneSerial: 2))]
        )
        let connections = ConnectionModel(applicationModel: model) { _ in client }
        let serverID = TestConfiguration.primaryServerID

        await connections.loadDnsZones(for: serverID)
        let receipt = try await connections.performDnsAction(
            .addRecord(zone: "example.com", Self.record.configuration!),
            for: serverID
        )

        #expect(receipt == .record(Self.record, zoneSerial: 2))
        #expect(connections.dnsZoneObservationState(for: serverID) == .loaded(afterWrite))
        #expect(await client.dnsRecordZones == ["example.com"])
        #expect(connections.dnsRecordObservationState(for: serverID, zone: "example.com")
            == .loaded(DnsRecordsSnapshot(zone: "example.com", records: [Self.record])))
    }

    @Test
    func rejectedWriteIsThrownAndLeavesObservationsUntouched() async {
        let model = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let rejection = ClavironClientFailure(
            kind: .serverRejected,
            diagnosticDetail: "DNS entry already exists"
        )
        let inventory = DnsInventorySnapshot(zones: [Self.zone])
        let client = MockClavironClient(
            results: [.success(serviceSnapshot)],
            dnsZoneResults: [.success(inventory)],
            dnsActionResults: [.failure(rejection)]
        )
        let connections = ConnectionModel(applicationModel: model) { _ in client }
        let serverID = TestConfiguration.primaryServerID

        await connections.loadDnsZones(for: serverID)
        await #expect(throws: rejection) {
            try await connections.performDnsAction(
                .addZone(Self.zone.configuration!),
                for: serverID
            )
        }

        #expect(connections.dnsZoneObservationState(for: serverID) == .loaded(inventory))
        #expect(await client.dnsZoneRequestCount == 1)
    }

    @Test
    func removingAZoneForgetsItsRecords() async throws {
        let model = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let client = MockClavironClient(
            results: [.success(serviceSnapshot)],
            dnsZoneResults: [
                .success(DnsInventorySnapshot(zones: [Self.zone])),
                .success(DnsInventorySnapshot(zones: [])),
            ],
            dnsRecordResults: [.success(DnsRecordsSnapshot(zone: "example.com", records: [Self.record]))],
            dnsActionResults: [.success(.removed(zone: "example.com", zoneSerial: nil))]
        )
        let connections = ConnectionModel(applicationModel: model) { _ in client }
        let serverID = TestConfiguration.primaryServerID

        await connections.loadDnsZones(for: serverID)
        await connections.loadDnsRecords(for: serverID, zone: "example.com")
        _ = try await connections.performDnsAction(.removeZone(id: 1, cascade: true), for: serverID)

        #expect(connections.dnsZoneObservationState(for: serverID)
            == .empty(DnsInventorySnapshot(zones: [])))
        #expect(connections.dnsRecordObservationState(for: serverID, zone: "example.com")
            == .disconnected)
    }
}
