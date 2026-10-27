import ClavironControlPlane
import Foundation
import Testing
@testable import Claviron

@MainActor
struct ConnectionModelTests {
    @Test
    func explicitRefreshUpdatesWorkerObservationsAndPreservesFailures() async {
        let model = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let initial = WorkerFleetSnapshot.preview
        let updated = WorkerFleetSnapshot(
            capturedAt: .now, workersExpected: 16,
            master: MasterIdentityObservation(
                process: ProcessIdentityObservation(pid: 1234, startedAt: 42), generation: 2
            ),
            workers: initial.workers
        )
        let failure = ClavironClientFailure(kind: .unavailable, diagnosticDetail: "workers unavailable")
        let client = MockClavironClient(
            results: [.success(productionSnapshot), .success(productionSnapshot), .success(productionSnapshot)],
            workerResults: [.success(initial), .success(updated), .failure(failure)]
        )
        let connections = ConnectionModel(applicationModel: model) { _ in client }
        let id = TestConfiguration.primaryServerID
        await connections.connect(to: id)
        await connections.loadWorkers(for: id)
        await connections.loadWorkers(for: id)
        #expect(connections.workerObservationState(for: id) == .loaded(updated))
        await connections.loadWorkers(for: id)
        #expect(connections.workerObservationState(for: id) == .stale(updated, failure: failure))
        await connections.disconnect(id)
    }

    @Test
    func explicitRefreshUpdatesTheLinkedInventory() async {
        let model = ApplicationModel.preview(configuration: TestConfiguration.valid)
        func linked(_ link: LinkReachabilityObservation) -> LinkedApplicationSnapshot {
            LinkedApplicationSnapshot(capturedAt: .now, applications: [
                LinkedApplicationObservation(
                    id: LinkedApplicationIDObservation(fleetName: "example", name: "demo"),
                    runtime: "asgi", link: link, connectedLanes: link == .connected ? 2 : 0,
                    lanes: [], hosted: nil
                ),
            ])
        }
        let connected = linked(.connected)
        let disconnected = linked(.disconnected)
        let client = MockClavironClient(
            results: [.success(productionSnapshot), .success(productionSnapshot)],
            linkedApplicationResults: [.success(connected), .success(disconnected)]
        )
        let connections = ConnectionModel(applicationModel: model) { _ in client }
        let id = TestConfiguration.primaryServerID
        await connections.connect(to: id)
        await connections.loadLinkedApplications(for: id)
        #expect(connections.linkedApplicationSnapshot(for: id) == connected)
        await connections.loadLinkedApplications(for: id)
        #expect(connections.linkedApplicationSnapshot(for: id) == disconnected)
        await connections.disconnect(id)
    }

    @Test
    func firstConnectionLoadsInfoAndRefreshFailurePreservesIt() async {
        let model = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let info = ServerInfoSnapshot(name: "example", environment: "production",
            hostname: "example.test", clavironVersion: "1.0",
            uptime: ProtobufDurationObservation(seconds: 20, nanoseconds: 0))
        let updated = ServerInfoSnapshot(name: "example", environment: "production",
            hostname: "example.test", clavironVersion: "1.0",
            uptime: ProtobufDurationObservation(seconds: 30, nanoseconds: 0))
        let failure = ClavironClientFailure(kind: .unavailable, diagnosticDetail: "info unavailable")
        let client = MockClavironClient(
            results: [.success(productionSnapshot), .success(productionSnapshot), .success(productionSnapshot)],
            serverInfoResults: [.success(info), .success(updated), .failure(failure)]
        )
        let connections = ConnectionModel(applicationModel: model) { _ in client }
        let id = TestConfiguration.primaryServerID
        await connections.connect(to: id)
        #expect(connections.serverInfo(for: id) == info)
        #expect(await client.serverInfoRequestCount == 1)
        #expect(await client.requestCount == 1)
        await connections.loadServices(for: id)
        #expect(await client.serverInfoRequestCount == 1)
        #expect(await client.requestCount == 2)
        await connections.refreshServerInfo(for: id)
        #expect(await client.requestCount == 2)
        #expect(connections.serverInfo(for: id) == updated)
        #expect(await client.serverInfoRequestCount == 2)
        await connections.refresh(id)
        #expect(connections.serverInfo(for: id) == updated)
        #expect(connections.serverInfoFailure(for: id) == failure)
        #expect(connections.state(for: id) == .connected(productionSnapshot))
        await connections.disconnect(id)
        #expect(connections.serverInfo(for: id) == nil)
    }

    private let productionSnapshot = ServiceFleetSnapshot(
        capturedAt: Date(timeIntervalSince1970: 100),
        membersExpected: 3,
        membersReporting: 3,
        services: [
            ServiceObservation(name: "HttpsServer", placements: []),
        ]
    )

    @Test
    func connectionsAndObservationsRemainKeyedByServerID() async throws {
        let model = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let productionClient = MockClavironClient(
            results: [.success(productionSnapshot)]
        )
        let stagingSnapshot = ServiceFleetSnapshot(
            capturedAt: Date(timeIntervalSince1970: 200),
            membersExpected: 2,
            membersReporting: 1,
            services: []
        )
        let stagingClient = MockClavironClient(results: [.success(stagingSnapshot)])
        let connections = ConnectionModel(applicationModel: model) { endpoint in
            switch endpoint.host {
            case "control.example.com":
                productionClient
            case "staging.example.com":
                stagingClient
            default:
                throw TestConnectionError.unexpectedHost(endpoint.host)
            }
        }

        await connections.connect(to: TestConfiguration.primaryServerID)
        try await model.selectActiveServer(ServerID(rawValue: "staging"))

        #expect(connections.state(for: TestConfiguration.primaryServerID) == .connected(
            productionSnapshot
        ))
        #expect(connections.serviceObservationState(
            for: TestConfiguration.primaryServerID
        ) == .loaded(productionSnapshot))
        #expect(connections.state(for: ServerID(rawValue: "staging")) == .disconnected)

        await connections.connect(to: ServerID(rawValue: "staging"))

        #expect(connections.state(for: TestConfiguration.primaryServerID) == .connected(
            productionSnapshot
        ))
        #expect(connections.state(for: ServerID(rawValue: "staging")) == .connected(
            stagingSnapshot
        ))
        #expect(connections.state(for: ServerID(rawValue: "staging")).title == "Connected · Partial")
        #expect(connections.serviceObservationState(
            for: ServerID(rawValue: "staging")
        ) == .loaded(stagingSnapshot))
    }

    @Test
    func refreshFailureRetainsLastRawSnapshotAndDiagnostic() async {
        let model = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let failure = ClavironClientFailure(
            kind: .unavailable,
            diagnosticDetail: "connection refused by test transport"
        )
        let client = MockClavironClient(
            results: [
                .success(productionSnapshot),
                .failure(failure),
                .success(productionSnapshot),
            ]
        )
        let connections = ConnectionModel(applicationModel: model) { _ in client }

        await connections.connect(to: TestConfiguration.primaryServerID)
        await connections.refresh(TestConfiguration.primaryServerID)

        #expect(connections.state(for: TestConfiguration.primaryServerID) == .failed(
            failure,
            lastSnapshot: productionSnapshot
        ))
        #expect(connections.serviceObservationState(
            for: TestConfiguration.primaryServerID
        ) == .stale(productionSnapshot, failure: failure))

        await connections.refresh(TestConfiguration.primaryServerID)

        #expect(connections.state(for: TestConfiguration.primaryServerID) == .connected(
            productionSnapshot
        ))
    }

    @Test
    func explicitRefreshTracksServerAvailabilityAndRecovery() async {
        let model = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let failure = ClavironClientFailure(
            kind: .unavailable,
            diagnosticDetail: "server stopped"
        )
        let client = MockClavironClient(
            results: [
                .success(productionSnapshot),
                .failure(failure),
                .success(productionSnapshot),
            ]
        )
        let connections = ConnectionModel(
            applicationModel: model
        ) { _ in client }

        await connections.connect(to: TestConfiguration.primaryServerID)
        await connections.refresh(TestConfiguration.primaryServerID)
        #expect(connections.state(for: TestConfiguration.primaryServerID) == .failed(
            failure,
            lastSnapshot: productionSnapshot
        ))

        await connections.refresh(TestConfiguration.primaryServerID)
        #expect(connections.state(for: TestConfiguration.primaryServerID) == .connected(
            productionSnapshot
        ))
        await connections.disconnect(TestConfiguration.primaryServerID)
    }

    @Test
    func unavailableInitialConnectionRecoversWithANewClient() async {
        let model = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let failure = ClavironClientFailure(
            kind: .unavailable,
            diagnosticDetail: "connection refused by test transport"
        )
        let unavailableClient = MockClavironClient(results: [.failure(failure)])
        let recoveredClient = MockClavironClient(results: [.success(productionSnapshot)])
        var clientCreationCount = 0
        let connections = ConnectionModel(applicationModel: model) { _ in
            defer { clientCreationCount += 1 }
            return clientCreationCount == 0 ? unavailableClient : recoveredClient
        }

        await connections.connect(to: TestConfiguration.primaryServerID)

        #expect(connections.state(for: TestConfiguration.primaryServerID) == .failed(
            failure,
            lastSnapshot: nil
        ))
        #expect(await unavailableClient.isDisconnected)

        await connections.reconnect(TestConfiguration.primaryServerID)

        #expect(connections.state(for: TestConfiguration.primaryServerID) == .connected(
            productionSnapshot
        ))
        #expect(clientCreationCount == 2)
        #expect(await recoveredClient.requestCount == 1)
    }

    @Test
    func changedEndpointReplacesRatherThanReusesTheClient() async throws {
        let model = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let originalClient = MockClavironClient(results: [.success(productionSnapshot)])
        let replacementSnapshot = ServiceFleetSnapshot(
            capturedAt: Date(timeIntervalSince1970: 300),
            membersExpected: 1,
            membersReporting: 1,
            services: []
        )
        let replacementClient = MockClavironClient(results: [.success(replacementSnapshot)])
        let connections = ConnectionModel(applicationModel: model) { endpoint in
            endpoint.host == "replacement.example.com" ? replacementClient : originalClient
        }

        await connections.connect(to: TestConfiguration.primaryServerID)
        try await model.updateServer(
            TestConfiguration.primaryServerID,
            name: "Production",
            address: "https://replacement.example.com:7443",
            tlsProfileID: TestConfiguration.sharedTLSProfileID
        )
        await connections.connect(to: TestConfiguration.primaryServerID)

        #expect(await originalClient.isDisconnected)
        #expect(connections.state(for: TestConfiguration.primaryServerID) == .connected(
            replacementSnapshot
        ))
        #expect(connections.serviceObservationState(
            for: TestConfiguration.primaryServerID
        ) == .empty(replacementSnapshot))
        #expect(await originalClient.requestCount == 1)
        #expect(await replacementClient.requestCount == 1)
    }

    @Test
    func workerObservationHasIndependentLoadedAndStaleStates() async {
        let model = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let workerSnapshot = WorkerFleetSnapshot(
            capturedAt: Date(timeIntervalSince1970: 400),
            workersExpected: 1,
            workers: [
                WorkerObservation(
                    workerID: 1,
                    lifecycle: .running,
                    ownership: .spawned,
                    process: ProcessIdentityObservation(pid: 123, startedAt: 1),
                    uptime: ProtobufDurationObservation(seconds: 20, nanoseconds: 0),
                    recoveryAttempts: 0,
                    reloadRevision: 2,
                    incarnation: 3
                ),
            ]
        )
        let failure = ClavironClientFailure(
            kind: .timedOut,
            diagnosticDetail: "worker request timeout"
        )
        let client = MockClavironClient(
            results: [.success(productionSnapshot)],
            workerResults: [.success(workerSnapshot), .failure(failure)]
        )
        let connections = ConnectionModel(applicationModel: model) { _ in client }

        await connections.connect(to: TestConfiguration.primaryServerID)
        await connections.loadWorkers(for: TestConfiguration.primaryServerID)
        #expect(connections.workerObservationState(
            for: TestConfiguration.primaryServerID
        ) == .loaded(workerSnapshot))

        await connections.loadWorkers(for: TestConfiguration.primaryServerID)
        #expect(connections.workerObservationState(
            for: TestConfiguration.primaryServerID
        ) == .stale(workerSnapshot, failure: failure))

        await connections.disconnect(TestConfiguration.primaryServerID)
        #expect(connections.workerObservationState(
            for: TestConfiguration.primaryServerID
        ) == .disconnected)
    }

    @Test
    func applicationObservationHasIndependentLoadedAndStaleStates() async {
        let model = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let applicationSnapshot = ApplicationFleetSnapshot(
            capturedAt: Date(timeIntervalSince1970: 500),
            membersExpected: 1,
            membersReporting: 1,
            applications: [
                ApplicationObservation(
                    applicationID: ApplicationIDObservation(runtime: "php", name: "storefront"),
                    placements: []
                ),
            ]
        )
        let failure = ClavironClientFailure(
            kind: .unavailable,
            diagnosticDetail: "application request unavailable"
        )
        let client = MockClavironClient(
            results: [.success(productionSnapshot)],
            applicationResults: [.success(applicationSnapshot), .failure(failure)]
        )
        let connections = ConnectionModel(applicationModel: model) { _ in client }

        await connections.connect(to: TestConfiguration.primaryServerID)
        await connections.loadApplications(for: TestConfiguration.primaryServerID)
        #expect(connections.applicationObservationState(
            for: TestConfiguration.primaryServerID
        ) == .loaded(applicationSnapshot))

        await connections.loadApplications(for: TestConfiguration.primaryServerID)
        #expect(connections.applicationObservationState(
            for: TestConfiguration.primaryServerID
        ) == .stale(applicationSnapshot, failure: failure))

        await connections.disconnect(TestConfiguration.primaryServerID)
        #expect(connections.applicationObservationState(
            for: TestConfiguration.primaryServerID
        ) == .disconnected)
    }

    @Test
    func taskObservationHasIndependentLoadedAndStaleStates() async {
        let model = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let taskSnapshot = TaskFleetSnapshot(
            capturedAt: Date(timeIntervalSince1970: 700),
            membersExpected: 1,
            membersReporting: 1,
            tasks: [
                TaskObservation(
                    name: "wallet-reconciliation",
                    kind: .builtin,
                    scope: .workers,
                    dispatch: .one,
                    timing: .manual(executionTimeout: nil),
                    concurrency: 1,
                    placements: []
                ),
            ]
        )
        let failure = ClavironClientFailure(
            kind: .unavailable,
            diagnosticDetail: "task request unavailable"
        )
        let client = MockClavironClient(
            results: [.success(productionSnapshot)],
            taskResults: [.success(taskSnapshot), .failure(failure), .failure(failure)]
        )
        let connections = ConnectionModel(applicationModel: model) { _ in client }

        await connections.connect(to: TestConfiguration.primaryServerID)
        await connections.loadTasks(for: TestConfiguration.primaryServerID)
        #expect(connections.taskObservationState(
            for: TestConfiguration.primaryServerID
        ) == .loaded(taskSnapshot))

        do {
            _ = try await connections.refreshTasksForAction(for: TestConfiguration.primaryServerID)
            Issue.record("Failed action refresh should retain the diagnostic and throw.")
        } catch {
            #expect(error as? ClavironClientFailure == failure)
        }
        #expect(connections.taskObservationState(
            for: TestConfiguration.primaryServerID
        ) == .stale(taskSnapshot, failure: failure))

        await connections.loadTasks(for: TestConfiguration.primaryServerID)
        #expect(connections.taskObservationState(
            for: TestConfiguration.primaryServerID
        ) == .stale(taskSnapshot, failure: failure))

        await connections.disconnect(TestConfiguration.primaryServerID)
        #expect(connections.taskObservationState(
            for: TestConfiguration.primaryServerID
        ) == .disconnected)
    }

    @Test
    func hostingObservationHasIndependentLoadedAndStaleStates() async {
        let model = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let hostingSnapshot = HostingInventorySnapshot(
            vhosts: [
                HostedVhostObservation(
                    vhost: VhostObservation(id: 1, name: "example.net", enabled: true),
                    aliases: [],
                    servers: []
                ),
            ]
        )
        let failure = ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "hosting inventory unavailable"
        )
        let client = MockClavironClient(
            results: [.success(productionSnapshot)],
            hostingResults: [.success(hostingSnapshot), .failure(failure)]
        )
        let connections = ConnectionModel(applicationModel: model) { _ in client }

        await connections.connect(to: TestConfiguration.primaryServerID)
        await connections.loadHosting(for: TestConfiguration.primaryServerID)
        #expect(connections.hostingObservationState(
            for: TestConfiguration.primaryServerID
        ) == .loaded(hostingSnapshot))

        await connections.loadHosting(for: TestConfiguration.primaryServerID)
        #expect(connections.hostingObservationState(
            for: TestConfiguration.primaryServerID
        ) == .stale(hostingSnapshot, failure: failure))

        await connections.disconnect(TestConfiguration.primaryServerID)
        #expect(connections.hostingObservationState(
            for: TestConfiguration.primaryServerID
        ) == .disconnected)
    }

    @Test
    func certificateObservationHasIndependentLoadedAndStaleStates() async {
        let model = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let certificateSnapshot = CertificateInventorySnapshot(
            certificates: [
                HostedCertificateObservation(
                    certificate: CertificateObservation(
                        id: 1,
                        commonName: "example.com",
                        aliases: [],
                        issuedAt: nil,
                        expiresAt: nil,
                        updatedAt: nil,
                        enabled: true
                    ),
                    servers: []
                ),
            ]
        )
        let failure = ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "certificate inventory unavailable"
        )
        let client = MockClavironClient(
            results: [.success(productionSnapshot)],
            certificateResults: [.success(certificateSnapshot), .failure(failure)]
        )
        let connections = ConnectionModel(applicationModel: model) { _ in client }

        await connections.connect(to: TestConfiguration.primaryServerID)
        await connections.loadCertificates(for: TestConfiguration.primaryServerID)
        #expect(connections.certificateObservationState(
            for: TestConfiguration.primaryServerID
        ) == .loaded(certificateSnapshot))

        await connections.loadCertificates(for: TestConfiguration.primaryServerID)
        #expect(connections.certificateObservationState(
            for: TestConfiguration.primaryServerID
        ) == .stale(certificateSnapshot, failure: failure))

        await connections.disconnect(TestConfiguration.primaryServerID)
        #expect(connections.certificateObservationState(
            for: TestConfiguration.primaryServerID
        ) == .disconnected)
    }

    @Test
    func disconnectInvalidatesAnInFlightConnectionAttempt() async {
        let model = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let client = BlockingClavironClient()
        let connections = ConnectionModel(applicationModel: model) { _ in client }
        let connectTask = Task {
            await connections.connect(to: TestConfiguration.primaryServerID)
        }

        while !(await client.probeStarted) {
            await Task.yield()
        }
        #expect(connections.serviceObservationState(
            for: TestConfiguration.primaryServerID
        ) == .loading(previous: nil))
        await connections.disconnect(TestConfiguration.primaryServerID)
        await connectTask.value

        #expect(connections.state(for: TestConfiguration.primaryServerID) == .disconnected)
        #expect(await client.isDisconnected)
    }

    @Test
    func serviceActionObservationDoesNotPutTheSharedConnectionIntoRefreshingState() async throws {
        let model = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let client = BlockingServiceStatusClient(initialSnapshot: productionSnapshot)
        let connections = ConnectionModel(
            applicationModel: model
        ) { _ in client }

        await connections.connect(to: TestConfiguration.primaryServerID)
        let observationTask = Task {
            try await connections.refreshServiceForAction(
                named: "HttpWatchdogProvider",
                for: TestConfiguration.primaryServerID
            )
        }

        while !(await client.statusRequestStarted) {
            await Task.yield()
        }
        #expect(connections.state(for: TestConfiguration.primaryServerID) == .connected(
            productionSnapshot
        ))

        await client.completeStatusRequest(with: productionSnapshot)
        #expect(try await observationTask.value == productionSnapshot)
        #expect(await client.statusNames == ["HttpWatchdogProvider"])
        await connections.disconnect(TestConfiguration.primaryServerID)
    }
}

private enum TestConnectionError: Error {
    case unexpectedHost(String)
}

private actor BlockingClavironClient: ClavironClient {
    private var continuation: CheckedContinuation<ServiceFleetSnapshot, any Error>?
    private(set) var probeStarted = false
    private(set) var isDisconnected = false

    func loadServices() async throws -> ServiceFleetSnapshot {
        probeStarted = true
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func loadWorkers() async throws -> WorkerFleetSnapshot {
        throw CancellationError()
    }

    func loadApplications() async throws -> ApplicationFleetSnapshot {
        throw CancellationError()
    }

    func loadTasks() async throws -> TaskFleetSnapshot {
        throw CancellationError()
    }

    func loadHosting() async throws -> HostingInventorySnapshot {
        throw CancellationError()
    }

    func loadCertificates() async throws -> CertificateInventorySnapshot {
        throw CancellationError()
    }

    func disconnect() async {
        isDisconnected = true
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

private actor BlockingServiceStatusClient: ClavironClient {
    private let initialSnapshot: ServiceFleetSnapshot
    private var continuation: CheckedContinuation<ServiceFleetSnapshot, any Error>?
    private(set) var statusRequestStarted = false
    private(set) var statusNames: [String] = []

    init(initialSnapshot: ServiceFleetSnapshot) {
        self.initialSnapshot = initialSnapshot
    }

    func loadServices() async throws -> ServiceFleetSnapshot {
        initialSnapshot
    }

    func loadServiceStatus(named name: String) async throws -> ServiceFleetSnapshot {
        statusNames.append(name)
        statusRequestStarted = true
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func completeStatusRequest(with snapshot: ServiceFleetSnapshot) {
        continuation?.resume(returning: snapshot)
        continuation = nil
    }

    func loadWorkers() async throws -> WorkerFleetSnapshot {
        throw CancellationError()
    }

    func loadApplications() async throws -> ApplicationFleetSnapshot {
        throw CancellationError()
    }

    func loadTasks() async throws -> TaskFleetSnapshot {
        throw CancellationError()
    }

    func loadHosting() async throws -> HostingInventorySnapshot {
        throw CancellationError()
    }

    func loadCertificates() async throws -> CertificateInventorySnapshot {
        throw CancellationError()
    }

    func disconnect() async {}
}
