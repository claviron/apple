public actor MockClavironClient: ClavironClient {
    public enum LinkedApplicationResult: Equatable, Sendable {
        case success(LinkedApplicationSnapshot?)
        case failure(ClavironClientFailure)
    }

    public enum LinkedApplicationActionResult: Equatable, Sendable {
        case success(LinkedApplicationReceipt)
        case failure(ClavironClientFailure)
    }

    public enum ServerInfoResult: Equatable, Sendable {
        case success(ServerInfoSnapshot?)
        case failure(ClavironClientFailure)
    }
    public enum Result: Equatable, Sendable {
        case success(ServiceFleetSnapshot)
        case failure(ClavironClientFailure)
    }

    public enum ServiceActionResult: Equatable, Sendable {
        case success(ServiceManagementReceipt)
        case failure(ClavironClientFailure)
    }

    public enum WorkerResult: Equatable, Sendable {
        case success(WorkerFleetSnapshot)
        case failure(ClavironClientFailure)
    }

    public enum WorkerActionResult: Equatable, Sendable {
        case success(WorkerManagementReceipt)
        case failure(ClavironClientFailure)
    }

    public enum ApplicationResult: Equatable, Sendable {
        case success(ApplicationFleetSnapshot)
        case failure(ClavironClientFailure)
    }

    public enum ApplicationActionResult: Equatable, Sendable {
        case success(ApplicationManagementReceipt)
        case failure(ClavironClientFailure)
    }

    public enum TaskResult: Equatable, Sendable {
        case success(TaskFleetSnapshot)
        case failure(ClavironClientFailure)
    }

    public enum TaskActionResult: Equatable, Sendable {
        case success(TaskManagementReceipt)
        case failure(ClavironClientFailure)
    }

    public enum HostingResult: Equatable, Sendable {
        case success(HostingInventorySnapshot)
        case failure(ClavironClientFailure)
    }

    public enum CertificateResult: Equatable, Sendable {
        case success(CertificateInventorySnapshot)
        case failure(ClavironClientFailure)
    }

    public enum CertificateActionResult: Equatable, Sendable {
        case success(CertificateManagementReceipt)
        case failure(ClavironClientFailure)
    }

    public enum HostingActionResult: Equatable, Sendable {
        case success(HostingManagementReceipt)
        case failure(ClavironClientFailure)
    }

    public enum DnsZoneResult: Equatable, Sendable {
        case success(DnsInventorySnapshot)
        case failure(ClavironClientFailure)
    }

    public enum DnsRecordResult: Equatable, Sendable {
        case success(DnsRecordsSnapshot)
        case failure(ClavironClientFailure)
    }

    public enum DnsActionResult: Equatable, Sendable {
        case success(DnsManagementReceipt)
        case failure(ClavironClientFailure)
    }

    private var results: [Result]
    private var serverInfoResults: [ServerInfoResult]
    public private(set) var serverInfoRequestCount = 0
    private var linkedApplicationResults: [LinkedApplicationResult]
    private var linkedApplicationActionResults: [LinkedApplicationActionResult]
    public private(set) var linkedApplicationActions: [LinkedApplicationAction] = []
    private var serviceActionResults: [ServiceActionResult]
    private var workerResults: [WorkerResult]
    private var workerActionResults: [WorkerActionResult]
    private var applicationResults: [ApplicationResult]
    private var applicationActionResults: [ApplicationActionResult]
    private var taskResults: [TaskResult]
    private var taskActionResults: [TaskActionResult]
    private var hostingResults: [HostingResult]
    private var certificateResults: [CertificateResult]
    private var dnsZoneResults: [DnsZoneResult]
    private var hostingActionResults: [HostingActionResult]
    private var certificateActionResults: [CertificateActionResult]
    private var dnsRecordResults: [DnsRecordResult]
    private var dnsActionResults: [DnsActionResult]
    public private(set) var requestCount = 0
    public private(set) var serviceStatusNames: [String] = []
    public private(set) var serviceActions: [ServiceManagementAction] = []
    public private(set) var workerRequestCount = 0
    public private(set) var workerActions: [WorkerManagementAction] = []
    public private(set) var applicationRequestCount = 0
    public private(set) var applicationActions: [ApplicationManagementAction] = []
    public private(set) var taskRequestCount = 0
    public private(set) var taskActions: [TaskManagementAction] = []
    public private(set) var taskActionRunExecutionTimeouts: [ProtobufDurationObservation?] = []
    public private(set) var hostingRequestCount = 0
    public private(set) var certificateRequestCount = 0
    public private(set) var dnsZoneRequestCount = 0
    public private(set) var hostingActions: [HostingManagementAction] = []
    public private(set) var certificateActions: [CertificateManagementAction] = []
    public private(set) var dnsRecordZones: [String] = []
    public private(set) var dnsActions: [DnsManagementAction] = []
    public private(set) var isDisconnected = false

    public init(
        results: [Result],
        serviceActionResults: [ServiceActionResult] = [],
        workerResults: [WorkerResult] = [],
        workerActionResults: [WorkerActionResult] = [],
        applicationResults: [ApplicationResult] = [],
        applicationActionResults: [ApplicationActionResult] = [],
        taskResults: [TaskResult] = [],
        taskActionResults: [TaskActionResult] = [],
        hostingResults: [HostingResult] = [],
        certificateResults: [CertificateResult] = [],
        dnsZoneResults: [DnsZoneResult] = [],
        dnsRecordResults: [DnsRecordResult] = [],
        dnsActionResults: [DnsActionResult] = [],
        hostingActionResults: [HostingActionResult] = [],
        certificateActionResults: [CertificateActionResult] = [],
        serverInfoResults: [ServerInfoResult] = [],
        linkedApplicationResults: [LinkedApplicationResult] = [],
        linkedApplicationActionResults: [LinkedApplicationActionResult] = []
    ) {
        self.results = results
        self.serverInfoResults = serverInfoResults
        self.linkedApplicationResults = linkedApplicationResults
        self.linkedApplicationActionResults = linkedApplicationActionResults
        self.serviceActionResults = serviceActionResults
        self.workerResults = workerResults
        self.workerActionResults = workerActionResults
        self.applicationResults = applicationResults
        self.applicationActionResults = applicationActionResults
        self.taskResults = taskResults
        self.taskActionResults = taskActionResults
        self.hostingResults = hostingResults
        self.certificateResults = certificateResults
        self.dnsZoneResults = dnsZoneResults
        self.dnsRecordResults = dnsRecordResults
        self.dnsActionResults = dnsActionResults
        self.hostingActionResults = hostingActionResults
        self.certificateActionResults = certificateActionResults
    }

    public func performCertificateAction(
        _ action: CertificateManagementAction
    ) async throws -> CertificateManagementReceipt {
        certificateActions.append(action)

        guard !certificateActionResults.isEmpty else {
            throw ClavironClientFailure(
                kind: .unknown,
                diagnosticDetail: "The deterministic mock has no result for certificate action \(certificateActions.count)."
            )
        }

        switch certificateActionResults.removeFirst() {
        case let .success(receipt):
            return receipt
        case let .failure(failure):
            throw failure
        }
    }

    public func performHostingAction(
        _ action: HostingManagementAction
    ) async throws -> HostingManagementReceipt {
        hostingActions.append(action)

        guard !hostingActionResults.isEmpty else {
            throw ClavironClientFailure(
                kind: .unknown,
                diagnosticDetail: "The deterministic mock has no result for hosting action \(hostingActions.count)."
            )
        }

        switch hostingActionResults.removeFirst() {
        case let .success(receipt):
            return receipt
        case let .failure(failure):
            throw failure
        }
    }

    public func loadDnsZones() async throws -> DnsInventorySnapshot {
        dnsZoneRequestCount += 1

        guard !dnsZoneResults.isEmpty else {
            throw ClavironClientFailure(
                kind: .unknown,
                diagnosticDetail: "The deterministic mock has no result for DNS zone request \(dnsZoneRequestCount)."
            )
        }

        switch dnsZoneResults.removeFirst() {
        case let .success(snapshot):
            return snapshot
        case let .failure(failure):
            throw failure
        }
    }

    public func loadDnsRecords(zone: String) async throws -> DnsRecordsSnapshot {
        dnsRecordZones.append(zone)

        guard !dnsRecordResults.isEmpty else {
            throw ClavironClientFailure(
                kind: .unknown,
                diagnosticDetail: "The deterministic mock has no result for DNS record request \(dnsRecordZones.count)."
            )
        }

        switch dnsRecordResults.removeFirst() {
        case let .success(snapshot):
            return snapshot
        case let .failure(failure):
            throw failure
        }
    }

    public func performDnsAction(
        _ action: DnsManagementAction
    ) async throws -> DnsManagementReceipt {
        dnsActions.append(action)

        guard !dnsActionResults.isEmpty else {
            throw ClavironClientFailure(
                kind: .unknown,
                diagnosticDetail: "The deterministic mock has no result for DNS action \(dnsActions.count)."
            )
        }

        switch dnsActionResults.removeFirst() {
        case let .success(receipt):
            return receipt
        case let .failure(failure):
            throw failure
        }
    }

    public func loadCertificates() async throws -> CertificateInventorySnapshot {
        certificateRequestCount += 1

        guard !certificateResults.isEmpty else {
            throw ClavironClientFailure(
                kind: .unknown,
                diagnosticDetail: "The deterministic mock has no result for certificate request \(certificateRequestCount)."
            )
        }

        switch certificateResults.removeFirst() {
        case let .success(snapshot):
            return snapshot
        case let .failure(failure):
            throw failure
        }
    }

    public func loadHosting() async throws -> HostingInventorySnapshot {
        hostingRequestCount += 1

        guard !hostingResults.isEmpty else {
            throw ClavironClientFailure(
                kind: .unknown,
                diagnosticDetail: "The deterministic mock has no result for hosting request \(hostingRequestCount)."
            )
        }

        switch hostingResults.removeFirst() {
        case let .success(snapshot):
            return snapshot
        case let .failure(failure):
            throw failure
        }
    }

    public func loadTasks() async throws -> TaskFleetSnapshot {
        taskRequestCount += 1

        guard !taskResults.isEmpty else {
            throw ClavironClientFailure(
                kind: .unknown,
                diagnosticDetail: "The deterministic mock has no result for task request \(taskRequestCount)."
            )
        }

        switch taskResults.removeFirst() {
        case let .success(snapshot):
            return snapshot
        case let .failure(failure):
            throw failure
        }
    }

    public func performTaskAction(
        _ action: TaskManagementAction,
        runExecutionTimeout: ProtobufDurationObservation?
    ) async throws -> TaskManagementReceipt {
        taskActions.append(action)
        taskActionRunExecutionTimeouts.append(runExecutionTimeout)

        guard !taskActionResults.isEmpty else {
            throw ClavironClientFailure(
                kind: .unknown,
                diagnosticDetail: "The deterministic mock has no result for task action request \(taskActions.count)."
            )
        }

        switch taskActionResults.removeFirst() {
        case let .success(receipt):
            return receipt
        case let .failure(failure):
            throw failure
        }
    }

    public func loadApplications() async throws -> ApplicationFleetSnapshot {
        applicationRequestCount += 1

        guard !applicationResults.isEmpty else {
            throw ClavironClientFailure(
                kind: .unknown,
                diagnosticDetail: "The deterministic mock has no result for application request \(applicationRequestCount)."
            )
        }

        switch applicationResults.removeFirst() {
        case let .success(snapshot):
            return snapshot
        case let .failure(failure):
            throw failure
        }
    }

    public func performApplicationAction(
        _ action: ApplicationManagementAction
    ) async throws -> ApplicationManagementReceipt {
        applicationActions.append(action)

        guard !applicationActionResults.isEmpty else {
            throw ClavironClientFailure(
                kind: .unknown,
                diagnosticDetail: "The deterministic mock has no result for application action request \(applicationActions.count)."
            )
        }

        switch applicationActionResults.removeFirst() {
        case let .success(receipt):
            return receipt
        case let .failure(failure):
            throw failure
        }
    }

    public func loadWorkers() async throws -> WorkerFleetSnapshot {
        workerRequestCount += 1

        guard !workerResults.isEmpty else {
            throw ClavironClientFailure(
                kind: .unknown,
                diagnosticDetail: "The deterministic mock has no result for worker request \(workerRequestCount)."
            )
        }

        switch workerResults.removeFirst() {
        case let .success(snapshot):
            return snapshot
        case let .failure(failure):
            throw failure
        }
    }

    public func performWorkerAction(
        _ action: WorkerManagementAction
    ) async throws -> WorkerManagementReceipt {
        workerActions.append(action)

        guard !workerActionResults.isEmpty else {
            throw ClavironClientFailure(
                kind: .unknown,
                diagnosticDetail: "The deterministic mock has no result for worker action request \(workerActions.count)."
            )
        }

        switch workerActionResults.removeFirst() {
        case let .success(receipt):
            return receipt
        case let .failure(failure):
            throw failure
        }
    }

    public func loadServerInfo() async throws -> ServerInfoSnapshot? {
        serverInfoRequestCount += 1
        guard !serverInfoResults.isEmpty else { return nil }
        switch serverInfoResults.removeFirst() {
        case let .success(snapshot): return snapshot
        case let .failure(failure): throw failure
        }
    }

    public func loadLinkedApplications() async throws -> LinkedApplicationSnapshot? {
        guard !linkedApplicationResults.isEmpty else { return nil }
        switch linkedApplicationResults.removeFirst() {
        case let .success(snapshot): return snapshot
        case let .failure(failure): throw failure
        }
    }

    public func performLinkedApplicationAction(
        _ action: LinkedApplicationAction
    ) async throws -> LinkedApplicationReceipt {
        linkedApplicationActions.append(action)
        guard !linkedApplicationActionResults.isEmpty else {
            throw ClavironClientFailure(
                kind: .protocolMismatch,
                diagnosticDetail: "No linked application action result is queued."
            )
        }
        switch linkedApplicationActionResults.removeFirst() {
        case let .success(receipt): return receipt
        case let .failure(failure): throw failure
        }
    }

    public func loadServices() async throws -> ServiceFleetSnapshot {
        try nextServiceResult()
    }

    public func loadServiceStatus(named name: String) async throws -> ServiceFleetSnapshot {
        serviceStatusNames.append(name)
        return try nextServiceResult()
    }

    private func nextServiceResult() throws -> ServiceFleetSnapshot {
        requestCount += 1

        guard !results.isEmpty else {
            throw ClavironClientFailure(
                kind: .unknown,
                diagnosticDetail: "The deterministic mock has no result for request \(requestCount)."
            )
        }

        switch results.removeFirst() {
        case let .success(snapshot):
            return snapshot
        case let .failure(failure):
            throw failure
        }
    }

    public func performServiceAction(
        _ action: ServiceManagementAction
    ) async throws -> ServiceManagementReceipt {
        serviceActions.append(action)

        guard !serviceActionResults.isEmpty else {
            throw ClavironClientFailure(
                kind: .unknown,
                diagnosticDetail: "The deterministic mock has no result for service action request \(serviceActions.count)."
            )
        }

        switch serviceActionResults.removeFirst() {
        case let .success(receipt):
            return receipt
        case let .failure(failure):
            throw failure
        }
    }

    public func disconnect() async {
        isDisconnected = true
    }
}
