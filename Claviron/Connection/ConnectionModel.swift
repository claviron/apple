import ClavironControlPlane
import Foundation
import Observation

@MainActor
@Observable
final class ConnectionModel {
    typealias ClientFactory = @MainActor (ClavironEndpoint) throws -> any ClavironClient

    private let applicationModel: ApplicationModel
    @ObservationIgnored private let clientFactory: ClientFactory
    @ObservationIgnored private var clients: [ServerID: any ClavironClient] = [:]
    @ObservationIgnored private var clientEndpoints: [ServerID: ClavironEndpoint] = [:]
    @ObservationIgnored private var serverInfoOperationIDs: [ServerID: UUID] = [:]
    @ObservationIgnored private var operationIDs: [ServerID: UUID] = [:]
    @ObservationIgnored private var workerOperationIDs: [ServerID: UUID] = [:]
    @ObservationIgnored private var applicationOperationIDs: [ServerID: UUID] = [:]
    @ObservationIgnored private var taskOperationIDs: [ServerID: UUID] = [:]
    @ObservationIgnored private var hostingOperationIDs: [ServerID: UUID] = [:]
    @ObservationIgnored private var certificateOperationIDs: [ServerID: UUID] = [:]
    @ObservationIgnored private var dnsZoneOperationIDs: [ServerID: UUID] = [:]
    @ObservationIgnored private var dnsRecordOperationIDs: [DnsZoneKey: UUID] = [:]
    private var states: [ServerID: ServerConnectionState] = [:]
    private var managementSessionIDs: [ServerID: UUID] = [:]
    private var serverInfos: [ServerID: ServerInfoSnapshot] = [:]
    private var serverInfoFailures: [ServerID: ClavironClientFailure] = [:]
    private var workerStates: [ServerID: WorkerObservationState] = [:]
    private var memoryStates: [ServerID: RuntimeMemoryObservationState] = [:]
    @ObservationIgnored private var memoryOperationIDs: [ServerID: UUID] = [:]
    private var applicationStates: [ServerID: ApplicationObservationState] = [:]
    /// Present only while the server implements the linked-application API.
    private var linkedApplications: [ServerID: LinkedApplicationSnapshot] = [:]
    private var linkedApplicationFailures: [ServerID: ClavironClientFailure] = [:]
    @ObservationIgnored private var linkedApplicationOperationIDs: [ServerID: UUID] = [:]
    private var taskStates: [ServerID: TaskObservationState] = [:]
    private var hostingStates: [ServerID: HostingObservationState] = [:]
    private var certificateStates: [ServerID: CertificateObservationState] = [:]
    private var dnsZoneStates: [ServerID: DnsZoneObservationState] = [:]
    @ObservationIgnored private var domainOperationIDs: [ServerID: UUID] = [:]
    private var domainStates: [ServerID: DomainObservationState] = [:]
    private var dnsRecordStates: [DnsZoneKey: DnsRecordObservationState] = [:]

    init(
        applicationModel: ApplicationModel,
        clientFactory: @escaping ClientFactory = { endpoint in
            try DirectClavironClient(endpoint: endpoint)
        }
    ) {
        self.applicationModel = applicationModel
        self.clientFactory = clientFactory
    }

    func state(for serverID: ServerID) -> ServerConnectionState {
        states[serverID] ?? .disconnected
    }

    func serverInfo(for serverID: ServerID) -> ServerInfoSnapshot? {
        serverInfos[serverID]
    }

    func serverInfoFailure(for serverID: ServerID) -> ClavironClientFailure? {
        serverInfoFailures[serverID]
    }

    private func loadServerInfo(
        using client: any ClavironClient,
        for serverID: ServerID
    ) async {
        let operationID = UUID()
        serverInfoOperationIDs[serverID] = operationID
        do {
            let info = try await client.loadServerInfo()
            guard serverInfoOperationIDs[serverID] == operationID else { return }
            serverInfos[serverID] = info
            serverInfoFailures[serverID] = nil
        } catch {
            guard serverInfoOperationIDs[serverID] == operationID else { return }
            serverInfoFailures[serverID] = Self.failure(from: error)
        }
    }

    func refreshServerInfo(for serverID: ServerID) async {
        guard let client = clients[serverID] else { return }
        await loadServerInfo(using: client, for: serverID)
    }

    func loadServices(for serverID: ServerID) async {
        await refresh(serverID, includingServerInfo: false)
    }

    func serviceObservationState(for serverID: ServerID) -> ServiceObservationState {
        switch state(for: serverID) {
        case .disconnected:
            .disconnected
        case .connecting:
            .loading(previous: nil)
        case let .connected(snapshot)
            where snapshot.services.isEmpty && snapshot.coverage == .complete:
            .empty(snapshot)
        case let .connected(snapshot):
            .loaded(snapshot)
        case let .refreshing(snapshot):
            .loading(previous: snapshot)
        case let .failed(failure, lastSnapshot: .some(snapshot)):
            .stale(snapshot, failure: failure)
        case let .failed(failure, lastSnapshot: nil):
            .failed(failure)
        }
    }

    func workerObservationState(for serverID: ServerID) -> WorkerObservationState {
        workerStates[serverID] ?? .disconnected
    }

    func runtimeMemoryState(for serverID: ServerID) -> RuntimeMemoryObservationState {
        memoryStates[serverID] ?? .disconnected
    }

    func loadRuntimeMemory(for serverID: ServerID) async {
        guard let client = clients[serverID], state(for: serverID).canLoadResources,
              serverInfos[serverID]?.capabilities.contains("metrics") == true else { return }
        if case .loading = memoryStates[serverID] { return }
        let previous = memoryStates[serverID]?.snapshot
        let operationID = UUID()
        memoryOperationIDs[serverID] = operationID
        memoryStates[serverID] = .loading(previous: previous)
        do {
            let snapshot = try await client.loadRuntimeMemory()
            guard memoryOperationIDs[serverID] == operationID else { return }
            memoryStates[serverID] = snapshot.processes.isEmpty ? .empty(snapshot) : .loaded(snapshot)
        } catch {
            guard memoryOperationIDs[serverID] == operationID else { return }
            let failure = Self.failure(from: error)
            memoryStates[serverID] = previous.map { .stale($0, failure: failure) } ?? .failed(failure)
        }
    }

    func applicationObservationState(for serverID: ServerID) -> ApplicationObservationState {
        applicationStates[serverID] ?? .disconnected
    }

    /// Nil while the server has not reported linked applications, or does not
    /// implement the API at all.
    func linkedApplicationSnapshot(for serverID: ServerID) -> LinkedApplicationSnapshot? {
        linkedApplications[serverID]
    }

    /// The last failure to read linked applications; a previous snapshot, if
    /// any, is kept beside it rather than cleared.
    func linkedApplicationFailure(for serverID: ServerID) -> ClavironClientFailure? {
        linkedApplicationFailures[serverID]
    }

    func taskObservationState(for serverID: ServerID) -> TaskObservationState {
        taskStates[serverID] ?? .disconnected
    }

    func hostingObservationState(for serverID: ServerID) -> HostingObservationState {
        hostingStates[serverID] ?? .disconnected
    }

    func certificateObservationState(for serverID: ServerID) -> CertificateObservationState {
        certificateStates[serverID] ?? .disconnected
    }

    func dnsZoneObservationState(for serverID: ServerID) -> DnsZoneObservationState {
        dnsZoneStates[serverID] ?? .disconnected
    }

    func domainObservationState(for serverID: ServerID) -> DomainObservationState {
        domainStates[serverID] ?? .disconnected
    }

    func dnsRecordObservationState(
        for serverID: ServerID,
        zone: String
    ) -> DnsRecordObservationState {
        dnsRecordStates[DnsZoneKey(serverID: serverID, zone: zone)] ?? .disconnected
    }

    func loadRuntimeResources(for serverID: ServerID) async {
        guard clients[serverID] != nil else {
            return
        }

        async let workers: Void = loadWorkers(for: serverID)
        async let applications: Void = loadApplications(for: serverID)
        async let tasks: Void = loadTasks(for: serverID)
        _ = await (workers, applications, tasks)
    }

    func connect(to serverID: ServerID) async {
        let previousSnapshot = state(for: serverID).lastSnapshot
        let operationID = beginOperation(
            for: serverID,
            state: clients[serverID] == nil
                ? .connecting
                : .refreshing(previousSnapshot)
        )
        var newClient: (any ClavironClient)?

        do {
            let endpoint = try await applicationModel.endpoint(for: serverID)
            guard isCurrent(operationID, for: serverID) else {
                return
            }

            if let currentClient = clients[serverID],
               clientEndpoints[serverID] == endpoint {
                let snapshot = try await currentClient.loadServices()
                guard isCurrent(operationID, for: serverID) else {
                    return
                }
                states[serverID] = .connected(snapshot)
                await loadServerInfo(using: currentClient, for: serverID)
                return
            }

            let replacedClient = clients.removeValue(forKey: serverID)
            managementSessionIDs[serverID] = nil
            clientEndpoints[serverID] = nil
            if let replacedClient {
                resetResourceObservations(for: serverID)
                await replacedClient.disconnect()
                guard isCurrent(operationID, for: serverID) else {
                    return
                }
            }

            let client = try clientFactory(endpoint)
            newClient = client
            clients[serverID] = client
            managementSessionIDs[serverID] = UUID()
            clientEndpoints[serverID] = endpoint
            let snapshot = try await client.loadServices()

            guard isCurrent(operationID, for: serverID) else {
                await client.disconnect()
                return
            }
            states[serverID] = .connected(snapshot)
            await loadServerInfo(using: client, for: serverID)
        } catch {
            guard isCurrent(operationID, for: serverID) else {
                if let newClient {
                    await newClient.disconnect()
                }
                return
            }

            states[serverID] = .failed(
                Self.failure(from: error),
                lastSnapshot: previousSnapshot
            )
            if let newClient {
                clients[serverID] = nil
                managementSessionIDs[serverID] = nil
                clientEndpoints[serverID] = nil
                await newClient.disconnect()
            }
        }
    }

    func refresh(_ serverID: ServerID, includingServerInfo: Bool = true) async {
        guard let client = clients[serverID] else {
            await connect(to: serverID)
            return
        }

        let previousSnapshot = state(for: serverID).lastSnapshot
        let operationID = beginOperation(
            for: serverID,
            state: .refreshing(previousSnapshot)
        )

        do {
            let snapshot = try await client.loadServices()
            guard isCurrent(operationID, for: serverID) else {
                return
            }
            states[serverID] = .connected(snapshot)
            if includingServerInfo {
                await loadServerInfo(using: client, for: serverID)
            }
        } catch {
            guard isCurrent(operationID, for: serverID) else {
                return
            }
            states[serverID] = .failed(
                Self.failure(from: error),
                lastSnapshot: previousSnapshot
            )
        }
    }

    func performServiceAction(
        _ action: ServiceManagementAction,
        for serverID: ServerID
    ) async throws -> ServiceManagementReceipt {
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            if case let .failed(failure, _) = state(for: serverID) {
                throw failure
            }
            throw ClavironClientFailure(
                kind: .unavailable,
                diagnosticDetail: "No active Claviron client is available for service management."
            )
        }
        return try await client.performServiceAction(action)
    }

    func refreshServiceForAction(
        named name: String,
        for serverID: ServerID
    ) async throws -> ServiceFleetSnapshot {
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            if case let .failed(failure, _) = state(for: serverID) {
                throw failure
            }
            throw ClavironClientFailure(
                kind: .unavailable,
                diagnosticDetail: "No active Claviron client is available for service observation."
            )
        }
        return try await client.loadServiceStatus(named: name)
    }

    func reconnect(_ serverID: ServerID) async {
        await disconnect(serverID)
        await connect(to: serverID)
    }

    func loadWorkers(for serverID: ServerID) async {
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            if case let .failed(failure, _) = state(for: serverID) {
                workerStates[serverID] = .failed(failure)
            } else {
                workerStates[serverID] = .disconnected
            }
            return
        }

        let previousSnapshot = workerObservationState(for: serverID).snapshot
        let operationID = UUID()
        workerOperationIDs[serverID] = operationID
        workerStates[serverID] = .loading(previous: previousSnapshot)

        do {
            let snapshot = try await client.loadWorkers()
            guard workerOperationIDs[serverID] == operationID else {
                return
            }
            workerStates[serverID] = snapshot.workers.isEmpty
                && snapshot.coverage == .complete
                ? .empty(snapshot)
                : .loaded(snapshot)
        } catch {
            guard workerOperationIDs[serverID] == operationID else {
                return
            }
            let failure = Self.failure(from: error)
            workerStates[serverID] = previousSnapshot.map {
                .stale($0, failure: failure)
            } ?? .failed(failure)
        }
    }

    func performWorkerAction(
        _ action: WorkerManagementAction,
        for serverID: ServerID
    ) async throws -> WorkerManagementReceipt {
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            if case let .failed(failure, _) = state(for: serverID) {
                throw failure
            }
            throw ClavironClientFailure(
                kind: .unavailable,
                diagnosticDetail: "No active Claviron client is available for worker management."
            )
        }
        return try await client.performWorkerAction(action)
    }

    func refreshWorkersForAction(
        for serverID: ServerID
    ) async throws -> WorkerFleetSnapshot {
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            throw ClavironClientFailure(
                kind: .unavailable,
                diagnosticDetail: "The Claviron client disconnected before worker completion could be observed."
            )
        }

        let operationID = UUID()
        workerOperationIDs[serverID] = operationID
        let snapshot: WorkerFleetSnapshot
        do {
            snapshot = try await client.loadWorkers()
        } catch {
            throw Self.failure(from: error)
        }
        guard workerOperationIDs[serverID] == operationID else {
            throw ClavironClientFailure(
                kind: .cancelled,
                diagnosticDetail: "The worker observation was superseded before it completed."
            )
        }
        workerStates[serverID] = snapshot.workers.isEmpty
            && snapshot.coverage == .complete
            ? .empty(snapshot)
            : .loaded(snapshot)
        return snapshot
    }

    /// Native applications, then the applications this edge reaches over Orbit
    /// Link. Each keeps its own state: one failing leaves the other intact.
    func loadApplications(for serverID: ServerID) async {
        await loadNativeApplications(for: serverID)
        await loadLinkedApplications(for: serverID)
    }

    func loadLinkedApplications(for serverID: ServerID) async {
        guard let client = clients[serverID] else {
            return
        }
        let operationID = UUID()
        linkedApplicationOperationIDs[serverID] = operationID
        do {
            let snapshot = try await client.loadLinkedApplications()
            guard linkedApplicationOperationIDs[serverID] == operationID else {
                return
            }
            linkedApplications[serverID] = snapshot
            linkedApplicationFailures[serverID] = nil
        } catch {
            guard linkedApplicationOperationIDs[serverID] == operationID else {
                return
            }
            linkedApplicationFailures[serverID] = Self.failure(from: error)
        }
    }

    /// Accepted, not completed. The linked applications are read again at
    /// once; the process change itself shows up in a later read.
    func performLinkedApplicationAction(
        _ action: LinkedApplicationAction,
        for serverID: ServerID
    ) async throws -> LinkedApplicationReceipt {
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            if case let .failed(failure, _) = state(for: serverID) {
                throw failure
            }
            throw ClavironClientFailure(
                kind: .unavailable,
                diagnosticDetail: "No active Claviron client is available for linked application management."
            )
        }
        let receipt = try await client.performLinkedApplicationAction(action)
        await loadLinkedApplications(for: serverID)
        return receipt
    }

    private func loadNativeApplications(for serverID: ServerID) async {
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            if case let .failed(failure, _) = state(for: serverID) {
                applicationStates[serverID] = .failed(failure)
            } else {
                applicationStates[serverID] = .disconnected
            }
            return
        }

        let previousSnapshot = applicationObservationState(for: serverID).snapshot
        let operationID = UUID()
        applicationOperationIDs[serverID] = operationID
        applicationStates[serverID] = .loading(previous: previousSnapshot)

        do {
            let snapshot = try await client.loadApplications()
            guard applicationOperationIDs[serverID] == operationID else {
                return
            }
            applicationStates[serverID] = snapshot.applications.isEmpty
                && snapshot.coverage == .complete
                ? .empty(snapshot)
                : .loaded(snapshot)
        } catch {
            guard applicationOperationIDs[serverID] == operationID else {
                return
            }
            let failure = Self.failure(from: error)
            applicationStates[serverID] = previousSnapshot.map {
                .stale($0, failure: failure)
            } ?? .failed(failure)
        }
    }

    func performApplicationAction(
        _ action: ApplicationManagementAction,
        for serverID: ServerID
    ) async throws -> ApplicationManagementReceipt {
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            if case let .failed(failure, _) = state(for: serverID) {
                throw failure
            }
            throw ClavironClientFailure(
                kind: .unavailable,
                diagnosticDetail: "No active Claviron client is available for application management."
            )
        }
        return try await client.performApplicationAction(action)
    }

    func refreshApplicationsForAction(
        for serverID: ServerID
    ) async throws -> ApplicationFleetSnapshot {
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            throw ClavironClientFailure(
                kind: .unavailable,
                diagnosticDetail: "The Claviron client disconnected before application completion could be observed."
            )
        }

        let operationID = UUID()
        applicationOperationIDs[serverID] = operationID
        let snapshot: ApplicationFleetSnapshot
        do {
            snapshot = try await client.loadApplications()
        } catch {
            throw Self.failure(from: error)
        }
        guard applicationOperationIDs[serverID] == operationID else {
            throw ClavironClientFailure(
                kind: .cancelled,
                diagnosticDetail: "The application observation was superseded before it completed."
            )
        }
        applicationStates[serverID] = snapshot.applications.isEmpty
            && snapshot.coverage == .complete
            ? .empty(snapshot)
            : .loaded(snapshot)
        return snapshot
    }

    func loadTasks(for serverID: ServerID) async {
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            if case let .failed(failure, _) = state(for: serverID) {
                taskStates[serverID] = .failed(failure)
            } else {
                taskStates[serverID] = .disconnected
            }
            return
        }

        let previousSnapshot = taskObservationState(for: serverID).snapshot
        let operationID = UUID()
        taskOperationIDs[serverID] = operationID
        taskStates[serverID] = .loading(previous: previousSnapshot)

        do {
            let snapshot = try await client.loadTasks()
            guard taskOperationIDs[serverID] == operationID else {
                return
            }
            taskStates[serverID] = snapshot.tasks.isEmpty
                && snapshot.coverage == .complete
                ? .empty(snapshot)
                : .loaded(snapshot)
        } catch {
            guard taskOperationIDs[serverID] == operationID else {
                return
            }
            let failure = Self.failure(from: error)
            taskStates[serverID] = previousSnapshot.map {
                .stale($0, failure: failure)
            } ?? .failed(failure)
        }
    }

    func performTaskAction(
        _ action: TaskManagementAction,
        for serverID: ServerID,
        runExecutionTimeout: ProtobufDurationObservation?
    ) async throws -> TaskManagementReceipt {
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            if case let .failed(failure, _) = state(for: serverID) {
                throw failure
            }
            throw ClavironClientFailure(
                kind: .unavailable,
                diagnosticDetail: "No active Claviron client is available for task management."
            )
        }
        return try await client.performTaskAction(
            action,
            runExecutionTimeout: runExecutionTimeout
        )
    }

    func refreshTasksForAction(
        for serverID: ServerID
    ) async throws -> TaskFleetSnapshot {
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            throw ClavironClientFailure(
                kind: .unavailable,
                diagnosticDetail: "The Claviron client disconnected before task completion could be observed."
            )
        }

        let operationID = UUID()
        taskOperationIDs[serverID] = operationID
        let snapshot: TaskFleetSnapshot
        do {
            snapshot = try await client.loadTasks()
        } catch {
            let failure = Self.failure(from: error)
            if !Task.isCancelled, taskOperationIDs[serverID] == operationID {
                taskStates[serverID] = taskStates[serverID]?.snapshot.map {
                    .stale($0, failure: failure)
                } ?? .failed(failure)
            }
            throw failure
        }
        try Task.checkCancellation()
        guard taskOperationIDs[serverID] == operationID else {
            throw ClavironClientFailure(
                kind: .cancelled,
                diagnosticDetail: "The task observation was superseded before it completed."
            )
        }
        taskStates[serverID] = snapshot.tasks.isEmpty
            && snapshot.coverage == .complete
            ? .empty(snapshot)
            : .loaded(snapshot)
        return snapshot
    }

    func loadHosting(for serverID: ServerID) async {
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            if case let .failed(failure, _) = state(for: serverID) {
                hostingStates[serverID] = .failed(failure)
            } else {
                hostingStates[serverID] = .disconnected
            }
            return
        }

        let previousSnapshot = hostingObservationState(for: serverID).snapshot
        let operationID = UUID()
        hostingOperationIDs[serverID] = operationID
        hostingStates[serverID] = .loading(previous: previousSnapshot)

        do {
            let snapshot = try await client.loadHosting()
            guard hostingOperationIDs[serverID] == operationID else {
                return
            }
            hostingStates[serverID] = snapshot.vhosts.isEmpty
                ? .empty(snapshot)
                : .loaded(snapshot)
        } catch {
            guard hostingOperationIDs[serverID] == operationID else {
                return
            }
            let failure = Self.failure(from: error)
            hostingStates[serverID] = previousSnapshot.map {
                .stale($0, failure: failure)
            } ?? .failed(failure)
        }
    }

    func loadDnsZones(for serverID: ServerID) async {
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            if case let .failed(failure, _) = state(for: serverID) {
                dnsZoneStates[serverID] = .failed(failure)
            } else {
                dnsZoneStates[serverID] = .disconnected
            }
            return
        }

        let previousSnapshot = dnsZoneObservationState(for: serverID).snapshot
        let operationID = UUID()
        dnsZoneOperationIDs[serverID] = operationID
        dnsZoneStates[serverID] = .loading(previous: previousSnapshot)

        do {
            let snapshot = try await client.loadDnsZones()
            guard dnsZoneOperationIDs[serverID] == operationID else {
                return
            }
            dnsZoneStates[serverID] = snapshot.zones.isEmpty
                ? .empty(snapshot)
                : .loaded(snapshot)
        } catch {
            guard dnsZoneOperationIDs[serverID] == operationID else {
                return
            }
            let failure = Self.failure(from: error)
            dnsZoneStates[serverID] = previousSnapshot.map {
                .stale($0, failure: failure)
            } ?? .failed(failure)
        }
    }

    func loadDnsRecords(for serverID: ServerID, zone: String) async {
        let key = DnsZoneKey(serverID: serverID, zone: zone)
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            if case let .failed(failure, _) = state(for: serverID) {
                dnsRecordStates[key] = .failed(failure)
            } else {
                dnsRecordStates[key] = .disconnected
            }
            return
        }

        let previousSnapshot = dnsRecordStates[key]?.snapshot
        let operationID = UUID()
        dnsRecordOperationIDs[key] = operationID
        dnsRecordStates[key] = .loading(previous: previousSnapshot)

        do {
            let snapshot = try await client.loadDnsRecords(zone: zone)
            guard dnsRecordOperationIDs[key] == operationID else {
                return
            }
            dnsRecordStates[key] = snapshot.records.isEmpty
                ? .empty(snapshot)
                : .loaded(snapshot)
        } catch {
            guard dnsRecordOperationIDs[key] == operationID else {
                return
            }
            let failure = Self.failure(from: error)
            dnsRecordStates[key] = previousSnapshot.map {
                .stale($0, failure: failure)
            } ?? .failed(failure)
        }
    }

    /// Sends one DNS store mutation, then re-reads what it changed: the zone
    /// list for every action, and the affected zone's records for a record
    /// write. The receipt is returned as the server sent it; the refreshed
    /// observations, not the receipt, are what the views show.
    func loadDomains(for serverID: ServerID) async {
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            if case let .failed(failure, _) = state(for: serverID) {
                domainStates[serverID] = .failed(failure)
            } else {
                domainStates[serverID] = .disconnected
            }
            return
        }

        let previousSnapshot = domainObservationState(for: serverID).snapshot
        let operationID = UUID()
        domainOperationIDs[serverID] = operationID
        domainStates[serverID] = .loading(previous: previousSnapshot)

        do {
            let snapshot = try await client.loadDomains()
            guard domainOperationIDs[serverID] == operationID else {
                return
            }
            domainStates[serverID] = snapshot.domains.isEmpty
                ? .empty(snapshot)
                : .loaded(snapshot)
        } catch {
            guard domainOperationIDs[serverID] == operationID else {
                return
            }
            let failure = Self.failure(from: error)
            domainStates[serverID] = previousSnapshot.map {
                .stale($0, failure: failure)
            } ?? .failed(failure)
        }
    }

    /// A live registrar read; nothing is cached, the view owns the result.
    func loadDomainRegistrarInfo(
        for serverID: ServerID,
        registrar: String,
        name: String
    ) async throws -> DomainRegistrarInfo {
        let client = try await connectedClient(for: serverID, purpose: "domain management")
        do {
            return try await client.loadDomainRegistrarInfo(registrar: registrar, name: name)
        } catch {
            throw Self.failure(from: error)
        }
    }

    func loadDomainNameservers(
        for serverID: ServerID,
        registrar: String,
        name: String
    ) async throws -> DomainNameserversSnapshot {
        let client = try await connectedClient(for: serverID, purpose: "domain management")
        do {
            return try await client.loadDomainNameservers(registrar: registrar, name: name)
        } catch {
            throw Self.failure(from: error)
        }
    }

    func loadDomainTemplates(for serverID: ServerID) async throws -> [DomainTemplateObservation] {
        let client = try await connectedClient(for: serverID, purpose: "domain management")
        do {
            return try await client.loadDomainTemplates()
        } catch {
            throw Self.failure(from: error)
        }
    }

    /// Sends one domain write, then re-reads the store.
    func performDomainAction(
        _ action: DomainManagementAction,
        for serverID: ServerID
    ) async throws -> DomainManagementReceipt {
        let client = try await connectedClient(for: serverID, purpose: "domain management")
        let receipt: DomainManagementReceipt
        do {
            receipt = try await client.performDomainAction(action)
        } catch {
            throw Self.failure(from: error)
        }
        await loadDomains(for: serverID)
        return receipt
    }

    private func connectedClient(
        for serverID: ServerID,
        purpose: String
    ) async throws -> any ClavironClient {
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            if case let .failed(failure, _) = state(for: serverID) {
                throw failure
            }
            throw ClavironClientFailure(
                kind: .unavailable,
                diagnosticDetail: "No Claviron connection for \(purpose)."
            )
        }
        return client
    }

    func performDnsAction(
        _ action: DnsManagementAction,
        for serverID: ServerID
    ) async throws -> DnsManagementReceipt {
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            if case let .failed(failure, _) = state(for: serverID) {
                throw failure
            }
            throw ClavironClientFailure(
                kind: .unavailable,
                diagnosticDetail: "No Claviron connection for DNS management."
            )
        }

        let receipt: DnsManagementReceipt
        do {
            receipt = try await client.performDnsAction(action)
        } catch {
            throw Self.failure(from: error)
        }

        await loadDnsZones(for: serverID)
        if let zone = Self.recordZone(of: action, receipt: receipt) {
            await loadDnsRecords(for: serverID, zone: zone)
        }
        if case .removeZone = action, case let .removed(zone, _) = receipt {
            let key = DnsZoneKey(serverID: serverID, zone: zone)
            dnsRecordOperationIDs[key] = UUID()
            dnsRecordStates[key] = nil
        }
        return receipt
    }

    nonisolated static func recordZone(
        of action: DnsManagementAction,
        receipt: DnsManagementReceipt
    ) -> String? {
        switch (action, receipt) {
        case let (.addRecord(zone, _), _):
            zone
        case let (.updateRecord, .record(record, _)):
            record.zone
        case let (.removeRecord, .removed(zone, _)):
            zone
        case (.addZone, _), (.updateZone, _), (.removeZone, _), (.reload, _),
             (.updateRecord, _), (.removeRecord, _):
            nil
        }
    }

    /// Sends one alias write, then re-reads the hosting inventory. The
    /// receipt is the server's; the refreshed inventory is what views show.
    func performHostingAction(
        _ action: HostingManagementAction,
        for serverID: ServerID
    ) async throws -> HostingManagementReceipt {
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            if case let .failed(failure, _) = state(for: serverID) {
                throw failure
            }
            throw ClavironClientFailure(
                kind: .unavailable,
                diagnosticDetail: "No Claviron connection for hosting management."
            )
        }

        let receipt: HostingManagementReceipt
        do {
            receipt = try await client.performHostingAction(action)
        } catch {
            throw Self.failure(from: error)
        }
        await loadHosting(for: serverID)
        return receipt
    }

    /// Writes refresh inventory; read-only PEM exports leave it untouched.
    func performCertificateAction(
        _ action: CertificateManagementAction,
        for serverID: ServerID
    ) async throws -> CertificateManagementReceipt {
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            if case let .failed(failure, _) = state(for: serverID) {
                throw failure
            }
            throw ClavironClientFailure(
                kind: .unavailable,
                diagnosticDetail: "No Claviron connection for certificate management."
            )
        }

        let receipt: CertificateManagementReceipt
        do {
            receipt = try await client.performCertificateAction(action)
        } catch {
            throw Self.failure(from: error)
        }
        if case .exportPEM = action {
            // Read-only transfer must not reshuffle the selected inventory.
        } else {
            await loadCertificates(for: serverID)
        }
        return receipt
    }

    func loadCertificates(for serverID: ServerID) async {
        if clients[serverID] == nil {
            await connect(to: serverID)
        }
        guard let client = clients[serverID] else {
            if case let .failed(failure, _) = state(for: serverID) {
                certificateStates[serverID] = .failed(failure)
            } else {
                certificateStates[serverID] = .disconnected
            }
            return
        }

        let previousSnapshot = certificateObservationState(for: serverID).snapshot
        let operationID = UUID()
        certificateOperationIDs[serverID] = operationID
        certificateStates[serverID] = .loading(previous: previousSnapshot)

        do {
            let snapshot = try await client.loadCertificates()
            guard certificateOperationIDs[serverID] == operationID else {
                return
            }
            certificateStates[serverID] = snapshot.certificates.isEmpty
                ? .empty(snapshot)
                : .loaded(snapshot)
        } catch {
            guard certificateOperationIDs[serverID] == operationID else {
                return
            }
            let failure = Self.failure(from: error)
            certificateStates[serverID] = previousSnapshot.map {
                .stale($0, failure: failure)
            } ?? .failed(failure)
        }
    }

    func disconnect(_ serverID: ServerID) async {
        operationIDs[serverID] = UUID()
        let client = clients.removeValue(forKey: serverID)
        managementSessionIDs[serverID] = nil
        clientEndpoints[serverID] = nil
        states[serverID] = .disconnected
        resetResourceObservations(for: serverID)
        await client?.disconnect()
    }

    func managementSessionID(for serverID: ServerID) -> UUID? {
        guard state(for: serverID).canLoadResources else { return nil }
        return managementSessionIDs[serverID]
    }

    /// Schemas, cursors and pending edits belong to this admitted connection.
    /// A form must not silently submit using a replacement TLS identity.
    func managementSession(for serverID: ServerID) throws -> ManagementSession {
        guard let id = managementSessionIDs[serverID], let client = clients[serverID],
              state(for: serverID).canLoadResources else {
            throw ManagementClientError("Connect to the server before managing users.")
        }
        return ManagementSession(id: id, client: client)
    }

    private func beginOperation(
        for serverID: ServerID,
        state: ServerConnectionState
    ) -> UUID {
        let operationID = UUID()
        operationIDs[serverID] = operationID
        states[serverID] = state
        return operationID
    }

    private func isCurrent(_ operationID: UUID, for serverID: ServerID) -> Bool {
        operationIDs[serverID] == operationID
    }

    private func resetResourceObservations(for serverID: ServerID) {
        serverInfoOperationIDs[serverID] = UUID()
        serverInfos[serverID] = nil
        serverInfoFailures[serverID] = nil
        workerOperationIDs[serverID] = UUID()
        workerStates[serverID] = .disconnected
        memoryOperationIDs[serverID] = UUID()
        memoryStates[serverID] = .disconnected
        applicationOperationIDs[serverID] = UUID()
        applicationStates[serverID] = .disconnected
        linkedApplicationOperationIDs[serverID] = UUID()
        linkedApplications[serverID] = nil
        linkedApplicationFailures[serverID] = nil
        taskOperationIDs[serverID] = UUID()
        taskStates[serverID] = .disconnected
        hostingOperationIDs[serverID] = UUID()
        hostingStates[serverID] = .disconnected
        certificateOperationIDs[serverID] = UUID()
        certificateStates[serverID] = .disconnected
        dnsZoneOperationIDs[serverID] = UUID()
        dnsZoneStates[serverID] = .disconnected
        for key in dnsRecordStates.keys where key.serverID == serverID {
            dnsRecordOperationIDs[key] = UUID()
            dnsRecordStates[key] = nil
        }
    }

    private static func failure(from error: any Error) -> ClavironClientFailure {
        if let failure = error as? ClavironClientFailure {
            return failure
        }
        if error is CancellationError {
            return ClavironClientFailure(
                kind: .cancelled,
                diagnosticDetail: String(describing: error)
            )
        }
        return ClavironClientFailure(
            kind: .invalidConfiguration,
            diagnosticDetail: String(describing: error)
        )
    }
}

nonisolated enum ResourceObservationState<Snapshot: Equatable & Sendable>: Equatable, Sendable {
    case disconnected
    case loading(previous: Snapshot?)
    case empty(Snapshot)
    case loaded(Snapshot)
    case stale(Snapshot, failure: ClavironClientFailure)
    case failed(ClavironClientFailure)

    var snapshot: Snapshot? {
        switch self {
        case .disconnected, .failed:
            nil
        case let .loading(previous):
            previous
        case let .empty(snapshot), let .loaded(snapshot), let .stale(snapshot, _):
            snapshot
        }
    }
}

typealias ServiceObservationState = ResourceObservationState<ServiceFleetSnapshot>
typealias WorkerObservationState = ResourceObservationState<WorkerFleetSnapshot>
typealias RuntimeMemoryObservationState = ResourceObservationState<RuntimeMemorySnapshot>
typealias ApplicationObservationState = ResourceObservationState<ApplicationFleetSnapshot>
typealias TaskObservationState = ResourceObservationState<TaskFleetSnapshot>
typealias HostingObservationState = ResourceObservationState<HostingInventorySnapshot>
typealias CertificateObservationState = ResourceObservationState<CertificateInventorySnapshot>
typealias DnsZoneObservationState = ResourceObservationState<DnsInventorySnapshot>
typealias DnsRecordObservationState = ResourceObservationState<DnsRecordsSnapshot>
typealias DomainObservationState = ResourceObservationState<DomainInventorySnapshot>

/// Records are observed per zone, and zones per server.
nonisolated struct DnsZoneKey: Hashable, Sendable {
    let serverID: ServerID
    let zone: String
}

nonisolated enum ServerConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected(ServiceFleetSnapshot)
    case refreshing(ServiceFleetSnapshot?)
    case failed(ClavironClientFailure, lastSnapshot: ServiceFleetSnapshot?)

    var lastSnapshot: ServiceFleetSnapshot? {
        switch self {
        case .disconnected, .connecting:
            nil
        case let .connected(snapshot):
            snapshot
        case let .refreshing(snapshot):
            snapshot
        case let .failed(_, snapshot):
            snapshot
        }
    }

    var title: String {
        switch self {
        case .disconnected:
            "Disconnected"
        case .connecting:
            "Connecting"
        case let .connected(snapshot) where snapshot.coverage == .partial:
            "Connected · Partial"
        case let .connected(snapshot) where snapshot.coverage == .noReports:
            "Connected · No Reports"
        case .connected:
            "Connected"
        case .refreshing:
            "Refreshing"
        case let .failed(failure, _):
            failure.localizedDescription
        }
    }

    var systemImage: String {
        switch self {
        case .disconnected:
            "network.slash"
        case .connecting, .refreshing:
            "arrow.trianglehead.2.clockwise.rotate.90"
        case let .connected(snapshot) where snapshot.coverage != .complete:
            "exclamationmark.triangle"
        case .connected:
            "checkmark.circle"
        case .failed:
            "xmark.circle"
        }
    }

    var isBusy: Bool {
        switch self {
        case .connecting, .refreshing:
            true
        case .disconnected, .connected, .failed:
            false
        }
    }
}

extension ServerConnectionState {
    var canLoadResources: Bool {
        switch self {
        case .connected, .refreshing, .failed(_, lastSnapshot: .some):
            true
        case .disconnected, .connecting, .failed(_, lastSnapshot: nil):
            false
        }
    }
}
