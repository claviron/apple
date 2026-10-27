import ClavironControlPlane
import Foundation
import Testing
@testable import Claviron

@MainActor
struct ManagementModelTests {
    @Test
    func managementBecomesAvailableOnlyAfterConnectionAdmissionFinishes() async {
        let client = ManagedTestClient(pages: [], holdServices: true)
        let application = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let connection = ConnectionModel(applicationModel: application) { _ in client }
        let server = TestConfiguration.primaryServerID
        let connecting = Task { await connection.connect(to: server) }
        await client.waitForServicesRequest()
        #expect(connection.managementSessionID(for: server) == nil)
        await client.releaseServices()
        await connecting.value
        #expect(connection.managementSessionID(for: server) != nil)
        await connection.disconnect(server)
        #expect(connection.managementSessionID(for: server) == nil)
    }

    private static func page(_ name: String, next: String? = nil) -> ManagementPage {
        ManagementPage(records: [ManagedRecord(key: ManagedRecordKey(resource: .user, reference: name), revision: "v1", values: ["username": .string(name)])], nextCursor: next)
    }

    @Test
    func paginationFailureKeepsTheExistingPageAndCursor() async {
        let first = Self.page("first", next: "cursor-2")
        let second = Self.page("second")
        let client = ManagedTestClient(pages: [.success(first), .failure(ManagementClientError("Unavailable")), .success(second)])
        let application = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let connection = ConnectionModel(applicationModel: application) { _ in client }
        let server = TestConfiguration.primaryServerID
        await connection.connect(to: server)
        let model = ManagementModel(resource: .user, serverID: server, connection: connection)
        await model.reload()
        await model.next()
        #expect(model.page == first)
        #expect(model.currentCursor == nil)
        #expect(model.failure != nil)
        await model.next()
        #expect(model.page == second)
        #expect(model.currentCursor == "cursor-2")
        #expect(model.canGoBack)
        await connection.disconnect(server)
        #expect(!model.isCurrent)
    }

    @Test
    func aResponseFromAnOldTLSConnectionCannotReplaceTheNewActorsRecords() async {
        let oldClient = ManagedTestClient(pages: [], holdPage: true)
        let newPage = Self.page("new-actor-record")
        let newClient = ManagedTestClient(pages: [.success(newPage)])
        let application = ApplicationModel.preview(configuration: TestConfiguration.valid)
        var creations = 0
        let connection = ConnectionModel(applicationModel: application) { _ in
            creations += 1
            return creations == 1 ? oldClient : newClient
        }
        let server = TestConfiguration.primaryServerID
        await connection.connect(to: server)
        let model = ManagementModel(resource: .user, serverID: server, connection: connection)
        let oldLoad = Task { await model.reload() }
        await oldClient.waitForPageRequest()
        let oldSession = connection.managementSessionID(for: server)
        await connection.disconnect(server)
        await connection.connect(to: server)
        #expect(connection.managementSessionID(for: server) != oldSession)
        await model.reload()
        await oldClient.release(Self.page("old-actor-record"))
        await oldLoad.value
        #expect(model.page == newPage)
        #expect(model.isCurrent)
        await connection.disconnect(server)
    }
}

private actor ManagedTestClient: ClavironClient {
    var pages: [Result<ManagementPage, ManagementClientError>]
    var holdPage: Bool
    var holdServices: Bool
    private var pending: CheckedContinuation<ManagementPage, any Error>?
    private var waiting: CheckedContinuation<Void, Never>?
    private var servicesPending: CheckedContinuation<Void, Never>?
    private var servicesWaiting: CheckedContinuation<Void, Never>?

    init(pages: [Result<ManagementPage, ManagementClientError>], holdPage: Bool = false, holdServices: Bool = false) {
        self.pages = pages
        self.holdPage = holdPage
        self.holdServices = holdServices
    }

    func loadManagementSchema(_ resource: ManagementResource) async throws -> ManagementSchema {
        ManagementSchema(resource: resource, revision: "schema", recordSchema: [:], create: nil, update: nil, operations: [.list, .read])
    }

    func loadManagedRecords(_ query: ManagementQuery) async throws -> ManagementPage {
        if holdPage {
            return try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                waiting?.resume()
                waiting = nil
            }
        }
        guard !pages.isEmpty else { throw ManagementClientError("Unexpected page request") }
        return try pages.removeFirst().get()
    }

    func waitForPageRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { waiting = $0 }
    }

    func release(_ page: ManagementPage) {
        pending?.resume(returning: page)
        pending = nil
    }

    func loadServices() async throws -> ServiceFleetSnapshot {
        if holdServices {
            await withCheckedContinuation { continuation in
                servicesPending = continuation
                servicesWaiting?.resume()
                servicesWaiting = nil
            }
        }
        return ServiceFleetSnapshot(capturedAt: nil, membersExpected: 0, membersReporting: 0, services: [])
    }
    func waitForServicesRequest() async {
        if servicesPending != nil { return }
        await withCheckedContinuation { servicesWaiting = $0 }
    }
    func releaseServices() {
        holdServices = false
        servicesPending?.resume()
        servicesPending = nil
    }
    func loadWorkers() async throws -> WorkerFleetSnapshot { throw ManagementClientError("Not used") }
    func loadApplications() async throws -> ApplicationFleetSnapshot { throw ManagementClientError("Not used") }
    func loadTasks() async throws -> TaskFleetSnapshot { throw ManagementClientError("Not used") }
    func loadHosting() async throws -> HostingInventorySnapshot { throw ManagementClientError("Not used") }
    func loadCertificates() async throws -> CertificateInventorySnapshot { throw ManagementClientError("Not used") }
    func disconnect() async {}
}
