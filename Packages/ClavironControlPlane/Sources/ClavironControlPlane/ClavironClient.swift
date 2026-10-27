import Foundation

public protocol ClavironClient: Sendable {
    func loadManagementSchema(_ resource: ManagementResource) async throws -> ManagementSchema
    func loadManagedRecords(_ query: ManagementQuery) async throws -> ManagementPage
    func loadManagedRecord(_ key: ManagedRecordKey) async throws -> ManagedRecord
    func performManagementAction(_ action: ManagementAction) async throws -> ManagementMutation
    func loadAssignmentSchema(_ relation: ManagementRelation) async throws -> ManagementAssignmentSchema
    func loadAssignments(_ key: ManagementAssignmentKey) async throws -> ManagementAssignments
    func replaceAssignments(_ assignments: ManagementAssignments) async throws -> ManagementAssignmentMutation
    /// Loads server identity separately from service readiness. Nil means the
    /// endpoint does not implement GetInfo; it is not an empty server identity.
    func loadServerInfo() async throws -> ServerInfoSnapshot?
    /// Loads the typed service-fleet observation. A successful transport call
    /// is not treated as proof that every expected fleet member is reporting.
    func loadServices() async throws -> ServiceFleetSnapshot

    /// Loads one named service without refreshing the complete inventory.
    /// This is the observation path for an in-flight service command.
    func loadServiceStatus(named name: String) async throws -> ServiceFleetSnapshot

    /// Sends one typed fleet service command. Acceptance is distinct from the
    /// later placement convergence observed through `loadServices()`.
    func performServiceAction(
        _ action: ServiceManagementAction
    ) async throws -> ServiceManagementReceipt

    /// Loads the supervisor-owned worker-slot observation independently from
    /// service-fleet state.
    func loadWorkers() async throws -> WorkerFleetSnapshot

    /// Sends one typed worker-management command. A receipt reports only the
    /// server's acceptance; callers observe completion through `loadWorkers()`.
    func performWorkerAction(
        _ action: WorkerManagementAction
    ) async throws -> WorkerManagementReceipt

    /// Loads configured applications and their reported runtime placements.
    func loadApplications() async throws -> ApplicationFleetSnapshot

    /// Sends one typed application command. Acceptance is distinct from the
    /// later placement convergence observed through `loadApplications()`.
    func performApplicationAction(
        _ action: ApplicationManagementAction
    ) async throws -> ApplicationManagementReceipt
    /// Applications this edge reaches over Orbit Link. Nil means the endpoint
    /// does not implement the linked-application API; it is not an empty list.
    func loadLinkedApplications() async throws -> LinkedApplicationSnapshot?
    /// Accepted, not completed: read the linked applications again to see it.
    func performLinkedApplicationAction(
        _ action: LinkedApplicationAction
    ) async throws -> LinkedApplicationReceipt

    /// Loads configured tasks and their reported fleet placements.
    func loadTasks() async throws -> TaskFleetSnapshot

    /// Sends one typed task-management command. Start, stop, and restart
    /// acceptance is distinct from later fleet convergence; run completes in
    /// the RPC response itself. `runExecutionTimeout` is the server-observed
    /// task budget used only to keep the client transport deadline longer than
    /// that execution; it does not override the task's server-side policy.
    func performTaskAction(
        _ action: TaskManagementAction,
        runExecutionTimeout: ProtobufDurationObservation?
    ) async throws -> TaskManagementReceipt

    /// Loads the complete persisted vhost, alias, and server-link inventory.
    func loadHosting() async throws -> HostingInventorySnapshot

    /// Sends one alias write: add, remove, or move to another vhost.
    func performHostingAction(
        _ action: HostingManagementAction
    ) async throws -> HostingManagementReceipt

    /// Loads certificates, their dates and aliases, and attached servers.
    func loadCertificates() async throws -> CertificateInventorySnapshot
    /// Available permission records from the existing authorization manager.
    func loadCertificatePermissions() async throws -> CertificatePermissions

    /// Sends one certificate write. Adding runs the ACME issuance inside the
    /// call, so it carries no client deadline: the server's ACME policy
    /// bounds it.
    func performCertificateAction(
        _ action: CertificateManagementAction
    ) async throws -> CertificateManagementReceipt

    /// Loads every authoritative DNS zone the store holds.
    func loadDnsZones() async throws -> DnsInventorySnapshot

    /// Loads one zone's records, enabled and disabled alike.
    func loadDnsRecords(zone: String) async throws -> DnsRecordsSnapshot

    /// Sends one DNS store mutation or a reload request. A write receipt
    /// proves the store committed, not that serving snapshots reloaded.
    func performDnsAction(
        _ action: DnsManagementAction
    ) async throws -> DnsManagementReceipt

    /// Loads the registrars the server knows and the domains its store holds.
    func loadDomains() async throws -> DomainInventorySnapshot

    /// Asks the registrar for its current record of one domain.
    func loadDomainRegistrarInfo(registrar: String, name: String) async throws -> DomainRegistrarInfo

    /// Asks the registrar for the domain's delegation set.
    func loadDomainNameservers(registrar: String, name: String) async throws -> DomainNameserversSnapshot

    /// Loads the registration templates the store holds.
    func loadDomainTemplates() async throws -> [DomainTemplateObservation]

    /// Sends one domain write: a store insert from registrar data, a
    /// delegation change at the registrar, a template write, or a
    /// synchronization run.
    func performDomainAction(
        _ action: DomainManagementAction
    ) async throws -> DomainManagementReceipt

    /// Stops this client transport. A disconnected client is not reusable.
    func disconnect() async
}

public extension ClavironClient {
    func loadCertificatePermissions() async throws -> CertificatePermissions {
        throw ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "This client does not provide permission selection."
        )
    }
    func loadServerInfo() async throws -> ServerInfoSnapshot? { nil }
    func loadLinkedApplications() async throws -> LinkedApplicationSnapshot? { nil }
    func performLinkedApplicationAction(
        _ action: LinkedApplicationAction
    ) async throws -> LinkedApplicationReceipt {
        throw ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "This Claviron client does not implement linked application management."
        )
    }
    func performTaskAction(
        _ action: TaskManagementAction
    ) async throws -> TaskManagementReceipt {
        try await performTaskAction(action, runExecutionTimeout: nil)
    }

    func loadServiceStatus(named name: String) async throws -> ServiceFleetSnapshot {
        try await loadServices()
    }

    func performServiceAction(
        _ action: ServiceManagementAction
    ) async throws -> ServiceManagementReceipt {
        throw ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "This Claviron client does not implement service management actions."
        )
    }

    func performWorkerAction(
        _ action: WorkerManagementAction
    ) async throws -> WorkerManagementReceipt {
        throw ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "This Claviron client does not implement worker management actions."
        )
    }

    func performTaskAction(
        _ action: TaskManagementAction,
        runExecutionTimeout: ProtobufDurationObservation?
    ) async throws -> TaskManagementReceipt {
        throw ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "This Claviron client does not implement task management actions."
        )
    }

    func performApplicationAction(
        _ action: ApplicationManagementAction
    ) async throws -> ApplicationManagementReceipt {
        throw ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "This Claviron client does not implement application management actions."
        )
    }

    func performHostingAction(
        _ action: HostingManagementAction
    ) async throws -> HostingManagementReceipt {
        throw ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "This Claviron client does not implement hosting management actions."
        )
    }

    func performCertificateAction(
        _ action: CertificateManagementAction
    ) async throws -> CertificateManagementReceipt {
        throw ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "This Claviron client does not implement certificate management actions."
        )
    }

    func loadDnsZones() async throws -> DnsInventorySnapshot {
        throw ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "This Claviron client does not implement DNS management."
        )
    }

    func loadDnsRecords(zone: String) async throws -> DnsRecordsSnapshot {
        throw ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "This Claviron client does not implement DNS management."
        )
    }

    func performDnsAction(
        _ action: DnsManagementAction
    ) async throws -> DnsManagementReceipt {
        throw ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "This Claviron client does not implement DNS management."
        )
    }

    func loadDomains() async throws -> DomainInventorySnapshot {
        throw ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "This Claviron client does not implement domain management."
        )
    }

    func loadDomainRegistrarInfo(registrar: String, name: String) async throws -> DomainRegistrarInfo {
        throw ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "This Claviron client does not implement domain management."
        )
    }

    func loadDomainNameservers(registrar: String, name: String) async throws -> DomainNameserversSnapshot {
        throw ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "This Claviron client does not implement domain management."
        )
    }

    func loadDomainTemplates() async throws -> [DomainTemplateObservation] {
        throw ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "This Claviron client does not implement domain management."
        )
    }

    func performDomainAction(
        _ action: DomainManagementAction
    ) async throws -> DomainManagementReceipt {
        throw ClavironClientFailure(
            kind: .protocolMismatch,
            diagnosticDetail: "This Claviron client does not implement domain management."
        )
    }
}

public struct ClavironClientFailure: Error, Equatable, LocalizedError, Sendable {
    public enum Kind: Equatable, Sendable {
        case authenticationRejected
        case tlsHandshakeFailed
        case unavailable
        case timedOut
        case cancelled
        case protocolMismatch
        case invalidConfiguration
        case serverRejected
        case operationFailed
        case certificateIdentityUnconfirmed
        case unknown
    }

    public let kind: Kind
    public let diagnosticDetail: String

    public init(kind: Kind, diagnosticDetail: String) {
        self.kind = kind
        self.diagnosticDetail = diagnosticDetail
    }

    public var errorDescription: String? {
        switch kind {
        case .authenticationRejected:
            "The server rejected this TLS identity."
        case .tlsHandshakeFailed:
            "The secure TLS connection could not be established."
        case .unavailable:
            "The Claviron server is unavailable."
        case .timedOut:
            "The Claviron server did not respond in time."
        case .cancelled:
            "The connection attempt was cancelled."
        case .protocolMismatch:
            "This server does not support the expected Claviron management API."
        case .invalidConfiguration:
            "The saved connection or TLS configuration is invalid."
        case .serverRejected:
            "The Claviron server rejected the request."
        case .operationFailed:
            "The requested runtime change did not complete."
        case .certificateIdentityUnconfirmed:
            "The server did not confirm the requested certificate identity. Inspect the issued certificate before creating another one."
        case .unknown:
            "The Claviron connection failed."
        }
    }
}
