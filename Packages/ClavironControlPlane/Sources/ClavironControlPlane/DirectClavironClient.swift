import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2Posix
import NIOSSL
import SwiftProtobuf

public actor DirectClavironClient: ClavironClient {
    let grpcClient: GRPCClient<HTTP2ClientTransport.Posix>
    private let probeTimeout: Duration
    private var connectionTask: Task<Void, any Error>?

    public init(
        endpoint: ClavironEndpoint,
        probeTimeout: Duration = .seconds(5)
    ) throws {
        let certificateAuthority: TLSConfig.CertificateSource = .file(
            path: endpoint.credentials.certificateAuthorityFile.path,
            format: .pem
        )
        let clientCertificate: TLSConfig.CertificateSource = .file(
            path: endpoint.credentials.clientCertificateFile.path,
            format: .pem
        )
        let clientPrivateKey: TLSConfig.PrivateKeySource = .file(
            path: endpoint.credentials.clientPrivateKeyFile.path,
            format: .pem
        )

        let transportSecurity = HTTP2ClientTransport.Posix.TransportSecurity.mTLS(
            certificateChain: [clientCertificate],
            privateKey: clientPrivateKey
        ) { configuration in
            configuration.serverCertificateVerification = .fullVerification
            configuration.trustRoots = .certificates([certificateAuthority])
        }

        do {
            let transport = try HTTP2ClientTransport.Posix(
                target: .dns(host: endpoint.host, port: endpoint.port),
                transportSecurity: transportSecurity
            )
            let grpcClient = GRPCClient(transport: transport)
            self.grpcClient = grpcClient
            self.probeTimeout = probeTimeout
            self.connectionTask = Task {
                try await grpcClient.runConnections()
            }
        } catch {
            throw Self.map(error, defaultKind: .invalidConfiguration)
        }
    }

    deinit {
        grpcClient.beginGracefulShutdown()
        connectionTask?.cancel()
    }

    public func loadServerInfo() async throws -> ServerInfoSnapshot? {
        do {
            let client = Claviron_Server_ServerManager.Client(wrapping: grpcClient)
            let response = try await client.getInfo(
                request: ClientRequest(message: Claviron_Server_InfoRequest()),
                options: callOptions
            )
            return ServerInfoSnapshot(response)
        } catch let error as RPCError where error.code == .unimplemented {
            return nil
        } catch {
            throw Self.map(error)
        }
    }

    public func loadLinkedApplications() async throws -> LinkedApplicationSnapshot? {
        do {
            let client = Claviron_LinkedApplications_LinkedApplicationManager.Client(
                wrapping: grpcClient
            )
            let response = try await client.listLinkedApplications(
                request: ClientRequest(
                    message: Claviron_LinkedApplications_ListLinkedApplicationsRequest()
                ),
                options: callOptions
            )
            return LinkedApplicationSnapshot(response)
        } catch let error as RPCError where error.code == .unimplemented {
            return nil
        } catch {
            throw Self.map(error)
        }
    }

    public func performLinkedApplicationAction(
        _ action: LinkedApplicationAction
    ) async throws -> LinkedApplicationReceipt {
        do {
            let client = Claviron_LinkedApplications_LinkedApplicationManager.Client(
                wrapping: grpcClient
            )
            var message = Claviron_LinkedApplications_LinkedApplicationCommandRequest()
            message.id = action.link.message
            if let application = action.application {
                var id = Claviron_Applications_ApplicationId()
                id.runtime = application.runtime
                id.name = application.name
                message.application = id
            }
            if case let .command(_, name, payload) = action {
                message.command = name
                message.payload = payload
            }
            let request = ClientRequest(message: message)
            let response: Claviron_LinkedApplications_LinkedApplicationCommandResponse
            switch action {
            case .start:
                response = try await client.startLinkedApplication(request: request, options: callOptions)
            case .stop:
                response = try await client.stopLinkedApplication(request: request, options: callOptions)
            case .restart:
                response = try await client.restartLinkedApplication(request: request, options: callOptions)
            case .command:
                response = try await client.sendLinkedCommand(request: request, options: callOptions)
            }
            return LinkedApplicationReceipt(
                action: action,
                accepted: response.accepted,
                acknowledgedLink: response.hasID ? LinkedApplicationIDObservation(response.id) : nil
            )
        } catch {
            throw Self.map(error)
        }
    }

    public func loadServices() async throws -> ServiceFleetSnapshot {
        do {
            let serviceClient = Claviron_Services_ServiceManager.Client(
                wrapping: grpcClient
            )
            let response = try await serviceClient.listServices(
                request: ClientRequest(
                    message: Claviron_Services_ListServicesRequest()
                ),
                options: callOptions
            )

            return ServiceFleetSnapshot(
                capturedAt: response.hasCapturedAt ? response.capturedAt.date : nil,
                membersExpected: response.membersExpected,
                membersReporting: response.membersReporting,
                services: response.services.map(Self.serviceObservation)
            )
        } catch {
            throw Self.map(error)
        }
    }

    public func loadServiceStatus(named name: String) async throws -> ServiceFleetSnapshot {
        do {
            let serviceClient = Claviron_Services_ServiceManager.Client(
                wrapping: grpcClient
            )
            var message = Claviron_Services_ServiceStatusRequest()
            message.name = name
            let response = try await serviceClient.getServiceStatus(
                request: ClientRequest(message: message),
                options: callOptions
            )
            guard response.hasService else {
                throw ClavironClientFailure(
                    kind: .protocolMismatch,
                    diagnosticDetail: "The service status response for '\(name)' did not contain a service."
                )
            }

            return ServiceFleetSnapshot(
                capturedAt: response.hasCapturedAt ? response.capturedAt.date : nil,
                membersExpected: response.membersExpected,
                membersReporting: response.membersReporting,
                services: [Self.serviceObservation(response.service)]
            )
        } catch {
            throw Self.map(error)
        }
    }

    public func performServiceAction(
        _ action: ServiceManagementAction
    ) async throws -> ServiceManagementReceipt {
        do {
            let serviceClient = Claviron_Services_ServiceManager.Client(
                wrapping: grpcClient
            )
            var message = Claviron_Services_ServiceCommandRequest()
            message.name = action.serviceName
            let request = ClientRequest(message: message)
            let response: Claviron_Services_ServiceCommandResponse
            switch action {
            case .start:
                response = try await serviceClient.startService(
                    request: request,
                    options: callOptions
                )
            case .stop:
                response = try await serviceClient.stopService(
                    request: request,
                    options: callOptions
                )
            case .reload:
                response = try await serviceClient.reloadService(
                    request: request,
                    options: callOptions
                )
            case .restart:
                response = try await serviceClient.restartService(
                    request: request,
                    options: callOptions
                )
            }
            return try Self.serviceReceipt(action: action, response: response)
        } catch {
            throw Self.map(error)
        }
    }

    nonisolated static func serviceReceipt(
        action: ServiceManagementAction,
        response: Claviron_Services_ServiceCommandResponse
    ) throws -> ServiceManagementReceipt {
        guard response.name == action.serviceName else {
            throw ClavironClientFailure(
                kind: .protocolMismatch,
                diagnosticDetail: "The service command targeted '\(action.serviceName)', but the server acknowledged '\(response.name)'."
            )
        }
        return ServiceManagementReceipt(
            action: action,
            accepted: response.accepted,
            acknowledgedServiceName: response.name
        )
    }

    public func loadWorkers() async throws -> WorkerFleetSnapshot {
        do {
            let workerClient = Claviron_Workers_WorkerManager.Client(
                wrapping: grpcClient
            )
            let response = try await workerClient.listWorkers(
                request: ClientRequest(
                    message: Claviron_Workers_ListWorkersRequest()
                ),
                options: callOptions
            )

            return Self.workerFleetSnapshot(response)
        } catch {
            throw Self.map(error)
        }
    }

    public func performWorkerAction(
        _ action: WorkerManagementAction
    ) async throws -> WorkerManagementReceipt {
        do {
            let workerClient = Claviron_Workers_WorkerManager.Client(
                wrapping: grpcClient
            )

            switch action {
            case let .start(workerID):
                var message = Claviron_Workers_WorkerCommandRequest()
                message.workerID = workerID
                let response = try await workerClient.startWorker(
                    request: ClientRequest(message: message),
                    options: callOptions
                )
                return try Self.workerReceipt(
                    action: action,
                    workerID: workerID,
                    response: response
                )
            case let .stop(workerID):
                var message = Claviron_Workers_WorkerCommandRequest()
                message.workerID = workerID
                let response = try await workerClient.stopWorker(
                    request: ClientRequest(message: message),
                    options: callOptions
                )
                return try Self.workerReceipt(
                    action: action,
                    workerID: workerID,
                    response: response
                )
            case let .reload(workerID):
                var message = Claviron_Workers_WorkerCommandRequest()
                message.workerID = workerID
                let response = try await workerClient.reloadWorker(
                    request: ClientRequest(message: message),
                    options: callOptions
                )
                return try Self.workerReceipt(
                    action: action,
                    workerID: workerID,
                    response: response
                )
            case let .restart(workerID):
                var message = Claviron_Workers_WorkerCommandRequest()
                message.workerID = workerID
                let response = try await workerClient.restartWorker(
                    request: ClientRequest(message: message),
                    options: callOptions
                )
                return try Self.workerReceipt(
                    action: action,
                    workerID: workerID,
                    response: response
                )
            case .reloadAll:
                let response = try await workerClient.reloadWorkers(
                    request: ClientRequest(
                        message: Claviron_Workers_ReloadWorkersRequest()
                    ),
                    options: callOptions
                )
                return WorkerManagementReceipt(
                    action: action,
                    accepted: response.accepted,
                    submissionKey: response.submissionKey
                )
            case .restartAll:
                let response = try await workerClient.restartWorkers(
                    request: ClientRequest(
                        message: Claviron_Workers_RestartWorkersRequest()
                    ),
                    options: callOptions
                )
                return WorkerManagementReceipt(
                    action: action,
                    accepted: response.accepted,
                    submissionKey: response.submissionKey
                )
            case .add:
                let response = try await workerClient.addWorker(
                    request: ClientRequest(
                        message: Claviron_Workers_ResizeWorkersRequest()
                    ),
                    options: callOptions
                )
                return try Self.resizeWorkerReceipt(
                    action: action,
                    response: response
                )
            case .remove:
                let response = try await workerClient.removeWorker(
                    request: ClientRequest(
                        message: Claviron_Workers_ResizeWorkersRequest()
                    ),
                    options: callOptions
                )
                return try Self.resizeWorkerReceipt(
                    action: action,
                    response: response
                )
            }
        } catch {
            throw Self.map(error)
        }
    }

    nonisolated static func workerReceipt(
        action: WorkerManagementAction,
        workerID: UInt32,
        response: Claviron_Workers_WorkerCommandResponse
    ) throws -> WorkerManagementReceipt {
        guard response.workerID == workerID else {
            throw ClavironClientFailure(
                kind: .protocolMismatch,
                diagnosticDetail: "The worker command targeted worker \(workerID), but the server acknowledged worker \(response.workerID)."
            )
        }
        return WorkerManagementReceipt(
            action: action,
            accepted: response.accepted,
            submissionKey: response.submissionKey,
            acknowledgedWorkerID: response.workerID
        )
    }

    nonisolated static func resizeWorkerReceipt(
        action: WorkerManagementAction,
        response: Claviron_Workers_ResizeWorkersResponse
    ) throws -> WorkerManagementReceipt {
        if response.accepted {
            let isValidTransition: Bool
            switch action {
            case .add:
                isValidTransition = response.targetWorkerCount
                    == response.previousWorkerCount.addingReportingOverflow(1).partialValue
                    && response.previousWorkerCount < UInt32.max
            case .remove:
                isValidTransition = response.previousWorkerCount
                    == response.targetWorkerCount.addingReportingOverflow(1).partialValue
                    && response.targetWorkerCount < UInt32.max
                    && response.targetWorkerCount > 0
            case .start, .stop, .reload, .restart, .reloadAll, .restartAll:
                isValidTransition = false
            }
            guard isValidTransition else {
                throw ClavironClientFailure(
                    kind: .protocolMismatch,
                    diagnosticDetail: "The accepted worker resize returned an invalid transition from \(response.previousWorkerCount) to \(response.targetWorkerCount)."
                )
            }
        }

        return WorkerManagementReceipt(
            action: action,
            accepted: response.accepted,
            submissionKey: response.submissionKey,
            previousWorkerCount: response.previousWorkerCount,
            targetWorkerCount: response.targetWorkerCount
        )
    }

    public func loadApplications() async throws -> ApplicationFleetSnapshot {
        do {
            let applicationClient = Claviron_Applications_ApplicationManager.Client(
                wrapping: grpcClient
            )
            let response = try await applicationClient.listApplications(
                request: ClientRequest(
                    message: Claviron_Applications_ListApplicationsRequest()
                ),
                options: callOptions
            )

            return ApplicationFleetSnapshot(
                capturedAt: response.hasCapturedAt ? response.capturedAt.date : nil,
                membersExpected: response.membersExpected,
                membersReporting: response.membersReporting,
                applications: response.applications.map(Self.applicationObservation)
            )
        } catch {
            throw Self.map(error)
        }
    }

    public func performApplicationAction(
        _ action: ApplicationManagementAction
    ) async throws -> ApplicationManagementReceipt {
        do {
            let applicationClient = Claviron_Applications_ApplicationManager.Client(
                wrapping: grpcClient
            )
            var id = Claviron_Applications_ApplicationId()
            id.runtime = action.applicationID.runtime
            id.name = action.applicationID.name
            var message = Claviron_Applications_ApplicationCommandRequest()
            message.id = id
            let request = ClientRequest(message: message)
            let response: Claviron_Applications_ApplicationCommandResponse
            switch action {
            case .start:
                response = try await applicationClient.startApplication(
                    request: request,
                    options: callOptions
                )
            case .stop:
                response = try await applicationClient.stopApplication(
                    request: request,
                    options: callOptions
                )
            case .restart:
                response = try await applicationClient.restartApplication(
                    request: request,
                    options: callOptions
                )
            }
            return try Self.applicationReceipt(action: action, response: response)
        } catch {
            throw Self.map(error)
        }
    }

    nonisolated static func applicationReceipt(
        action: ApplicationManagementAction,
        response: Claviron_Applications_ApplicationCommandResponse
    ) throws -> ApplicationManagementReceipt {
        guard response.hasID else {
            throw ClavironClientFailure(
                kind: .protocolMismatch,
                diagnosticDetail: "The application command response did not identify its target."
            )
        }
        let acknowledgedID = ApplicationIDObservation(
            runtime: response.id.runtime,
            name: response.id.name
        )
        guard acknowledgedID == action.applicationID else {
            throw ClavironClientFailure(
                kind: .protocolMismatch,
                diagnosticDetail: "The application command targeted '\(action.applicationID.runtime):\(action.applicationID.name)', but the server acknowledged '\(acknowledgedID.runtime):\(acknowledgedID.name)'."
            )
        }
        return ApplicationManagementReceipt(
            action: action,
            accepted: response.accepted,
            acknowledgedApplicationID: acknowledgedID
        )
    }

    public func loadTasks() async throws -> TaskFleetSnapshot {
        do {
            let taskClient = Claviron_Tasks_TaskManager.Client(wrapping: grpcClient)
            let response = try await taskClient.listTasks(
                request: ClientRequest(message: Claviron_Tasks_ListTasksRequest()),
                options: callOptions
            )

            return TaskFleetSnapshot(
                capturedAt: response.hasCapturedAt ? response.capturedAt.date : nil,
                membersExpected: response.membersExpected,
                membersReporting: response.membersReporting,
                tasks: response.tasks.map(Self.taskObservation)
            )
        } catch {
            throw Self.map(error)
        }
    }

    public func performTaskAction(
        _ action: TaskManagementAction,
        runExecutionTimeout: ProtobufDurationObservation?
    ) async throws -> TaskManagementReceipt {
        do {
            let taskClient = Claviron_Tasks_TaskManager.Client(wrapping: grpcClient)

            switch action {
            case .start, .stop, .reload, .restart:
                var message = Claviron_Tasks_TaskCommandRequest()
                message.name = action.taskName
                let request = ClientRequest(message: message)
                let response: Claviron_Tasks_TaskCommandResponse
                switch action {
                case .start:
                    response = try await taskClient.startTask(
                        request: request,
                        options: callOptions
                    )
                case .stop:
                    response = try await taskClient.stopTask(
                        request: request,
                        options: callOptions
                    )
                case .reload:
                    response = try await taskClient.reloadTask(
                        request: request,
                        options: callOptions
                    )
                case .restart:
                    response = try await taskClient.restartTask(
                        request: request,
                        options: callOptions
                    )
                case .run:
                    preconditionFailure("Run uses its synchronous response path")
                }
                return try Self.taskReceipt(action: action, response: response)

            case .run:
                var message = Claviron_Tasks_RunTaskRequest()
                message.name = action.taskName
                let response = try await taskClient.runTask(
                    request: ClientRequest(message: message),
                    options: taskRunCallOptions(
                        executionTimeout: runExecutionTimeout
                    )
                )
                return try Self.taskRunReceipt(action: action, response: response)
            }
        } catch {
            throw Self.map(error)
        }
    }

    nonisolated static func taskReceipt(
        action: TaskManagementAction,
        response: Claviron_Tasks_TaskCommandResponse
    ) throws -> TaskManagementReceipt {
        guard response.name == action.taskName else {
            throw ClavironClientFailure(
                kind: .protocolMismatch,
                diagnosticDetail: "The task command targeted '\(action.taskName)', but the server acknowledged '\(response.name)'."
            )
        }
        return TaskManagementReceipt(
            action: action,
            accepted: response.accepted,
            acknowledgedTaskName: response.name
        )
    }

    nonisolated static func taskRunReceipt(
        action: TaskManagementAction,
        response: Claviron_Tasks_RunTaskResponse
    ) throws -> TaskManagementReceipt {
        guard response.name == action.taskName else {
            throw ClavironClientFailure(
                kind: .protocolMismatch,
                diagnosticDetail: "The task run targeted '\(action.taskName)', but the server returned '\(response.name)'."
            )
        }

        let result: TaskRunResult
        switch response.result {
        case .success:
            result = .succeeded
        case let .failure(failure):
            result = .failed(TaskRunFailure(
                kind: Self.taskRunFailureKind(failure.kind),
                message: failure.message
            ))
        case nil:
            throw ClavironClientFailure(
                kind: .protocolMismatch,
                diagnosticDetail: "Task '\(response.name)' returned no execution result for run \(response.runID)."
            )
        }

        return TaskManagementReceipt(
            action: action,
            accepted: true,
            acknowledgedTaskName: response.name,
            runID: response.runID,
            runResult: result
        )
    }

    private nonisolated static func taskRunFailureKind(
        _ kind: Claviron_Tasks_RunTaskFailureKind
    ) -> TaskRunFailureKind {
        switch kind {
        case .unspecified: .unspecified
        case .io: .io
        case .cancelled: .cancelled
        case .shutdown: .shutdown
        case .gracefulTimeout: .gracefulTimeout
        case .executionTimeout: .executionTimeout
        case .task: .task
        case let .UNRECOGNIZED(rawValue): .unrecognized(rawValue)
        }
    }

    public func loadHosting() async throws -> HostingInventorySnapshot {
        do {
            let aliasClient = Claviron_Aliases_AliasManager.Client(wrapping: grpcClient)
            let response = try await aliasClient.listHosting(
                request: ClientRequest(message: Claviron_Aliases_ListHostingRequest()),
                options: callOptions
            )

            return HostingInventorySnapshot(
                vhosts: response.vhosts.map(Self.hostedVhostObservation)
            )
        } catch {
            throw Self.map(error)
        }
    }

    public func performHostingAction(
        _ action: HostingManagementAction
    ) async throws -> HostingManagementReceipt {
        do {
            let aliasClient = Claviron_Aliases_AliasManager.Client(wrapping: grpcClient)
            switch action {
            case let .addAlias(vhostName, hostname):
                var message = Claviron_Aliases_AddAliasRequest()
                message.vhostName = vhostName
                message.hostname = hostname
                let response = try await aliasClient.addAlias(
                    request: ClientRequest(message: message),
                    options: callOptions
                )
                return try Self.aliasReceipt(response)
            case let .removeAlias(hostname):
                var message = Claviron_Aliases_RemoveAliasRequest()
                message.hostname = hostname
                let response = try await aliasClient.removeAlias(
                    request: ClientRequest(message: message),
                    options: callOptions
                )
                return Self.operationReceipt(response)
            case let .replaceAlias(hostname, vhostName):
                var message = Claviron_Aliases_ReplaceAliasRequest()
                message.hostname = hostname
                message.vhostName = vhostName
                let response = try await aliasClient.replaceAlias(
                    request: ClientRequest(message: message),
                    options: callOptions
                )
                return Self.operationReceipt(response)
            }
        } catch {
            throw Self.map(error)
        }
    }

    nonisolated static func aliasReceipt(
        _ response: Claviron_Aliases_AliasResponse
    ) throws -> HostingManagementReceipt {
        guard response.hasAlias else {
            throw ClavironClientFailure(
                kind: .protocolMismatch,
                diagnosticDetail: "AliasManager returned an alias response without an alias."
            )
        }
        return .alias(
            VhostAliasObservation(
                id: response.alias.id,
                hostname: response.alias.hostname,
                enabled: response.alias.hasEnabled ? response.alias.enabled : nil,
                readOnly: response.alias.readOnly,
                readOnlyReason: response.alias.hasReadOnlyReason ? response.alias.readOnlyReason : nil
            ),
            vhostName: response.vhostName
        )
    }

    nonisolated static func operationReceipt(
        _ response: Claviron_Aliases_OperationResponse
    ) -> HostingManagementReceipt {
        .operation(
            success: response.success,
            message: response.hasMessage ? response.message : nil
        )
    }

    public func loadCertificates() async throws -> CertificateInventorySnapshot {
        do {
            let acmeClient = Claviron_Acme_AcmeManager.Client(wrapping: grpcClient)
            let response = try await acmeClient.listCertificateInventory(
                request: ClientRequest(message: Claviron_Acme_ListCertificatesRequest()),
                options: callOptions
            )

            return CertificateInventorySnapshot(
                certificates: response.certificates.map(Self.hostedCertificateObservation)
            )
        } catch {
            throw Self.map(error)
        }
    }

    public func loadCertificatePermissions() async throws -> CertificatePermissions {
        var names: [String] = []
        var cursor: String?
        var seenCursors: Set<String> = []
        repeat {
            try Task.checkCancellation()
            let page = try await loadManagedRecords(ManagementQuery(resource: .permission, pageSize: 20, cursor: cursor))
            names.append(contentsOf: page.records.map(\.key.reference))
            cursor = page.nextCursor
            if let cursor, !seenCursors.insert(cursor).inserted {
                throw ManagementClientError("The server repeated a permission page cursor.")
            }
        } while cursor != nil
        return try CertificatePermissions(names: names)
    }

    public func loadDnsZones() async throws -> DnsInventorySnapshot {
        do {
            let dnsClient = Claviron_Dns_DnsManager.Client(wrapping: grpcClient)
            let response = try await dnsClient.listZones(
                request: ClientRequest(message: Claviron_Dns_ListZonesRequest()),
                options: callOptions
            )
            return DnsInventorySnapshot(zones: response.zones.map(Self.dnsZoneObservation))
        } catch {
            throw Self.map(error)
        }
    }

    public func loadDnsRecords(zone: String) async throws -> DnsRecordsSnapshot {
        do {
            let dnsClient = Claviron_Dns_DnsManager.Client(wrapping: grpcClient)
            var message = Claviron_Dns_ListRecordsRequest()
            message.zone = zone
            let response = try await dnsClient.listRecords(
                request: ClientRequest(message: message),
                options: callOptions
            )
            return DnsRecordsSnapshot(
                zone: zone,
                records: response.records.map(Self.dnsRecordObservation)
            )
        } catch {
            throw Self.map(error)
        }
    }

    public func performDnsAction(
        _ action: DnsManagementAction
    ) async throws -> DnsManagementReceipt {
        do {
            let dnsClient = Claviron_Dns_DnsManager.Client(wrapping: grpcClient)
            switch action {
            case let .addZone(configuration):
                var message = Claviron_Dns_AddZoneRequest()
                message.config = try Self.dnsZoneConfigMessage(configuration)
                let response = try await dnsClient.addZone(
                    request: ClientRequest(message: message),
                    options: callOptions
                )
                return try Self.dnsZoneReceipt(response)
            case let .updateZone(id, configuration):
                var message = Claviron_Dns_UpdateZoneRequest()
                message.id = id
                message.config = try Self.dnsZoneConfigMessage(configuration)
                let response = try await dnsClient.updateZone(
                    request: ClientRequest(message: message),
                    options: callOptions
                )
                return try Self.dnsZoneReceipt(response)
            case let .removeZone(id, cascade):
                var message = Claviron_Dns_RemoveZoneRequest()
                message.id = id
                message.cascade = cascade
                let response = try await dnsClient.removeZone(
                    request: ClientRequest(message: message),
                    options: callOptions
                )
                return Self.dnsRemovalReceipt(response)
            case let .addRecord(zone, configuration):
                var message = Claviron_Dns_AddRecordRequest()
                message.zone = zone
                message.config = Self.dnsRecordConfigMessage(configuration)
                let response = try await dnsClient.addRecord(
                    request: ClientRequest(message: message),
                    options: callOptions
                )
                return try Self.dnsRecordReceipt(response)
            case let .updateRecord(id, configuration):
                var message = Claviron_Dns_UpdateRecordRequest()
                message.id = id
                message.config = Self.dnsRecordConfigMessage(configuration)
                let response = try await dnsClient.updateRecord(
                    request: ClientRequest(message: message),
                    options: callOptions
                )
                return try Self.dnsRecordReceipt(response)
            case let .removeRecord(id):
                var message = Claviron_Dns_RemoveRecordRequest()
                message.id = id
                let response = try await dnsClient.removeRecord(
                    request: ClientRequest(message: message),
                    options: callOptions
                )
                return Self.dnsRemovalReceipt(response)
            case .reload:
                let response = try await dnsClient.reloadDns(
                    request: ClientRequest(message: Claviron_Dns_ReloadDnsRequest()),
                    options: callOptions
                )
                return .reload(accepted: response.accepted)
            }
        } catch {
            throw Self.map(error)
        }
    }

    nonisolated static func dnsZoneObservation(
        _ zone: Claviron_Dns_ZoneInfo
    ) -> DnsZoneObservation {
        DnsZoneObservation(
            id: zone.id,
            configuration: zone.hasConfig ? DnsZoneConfiguration(
                domain: zone.config.domain,
                soa: zone.config.hasSoa ? DnsSOAConfiguration(
                    mname: zone.config.soa.mname,
                    rname: zone.config.soa.rname,
                    refresh: zone.config.soa.refresh,
                    retry: zone.config.soa.retry,
                    expire: zone.config.soa.expire,
                    minimum: zone.config.soa.minimum
                ) : nil,
                enabled: zone.config.enabled
            ) : nil,
            serial: zone.serial
        )
    }

    nonisolated static func dnsRecordObservation(
        _ record: Claviron_Dns_RecordInfo
    ) -> DnsRecordObservation {
        DnsRecordObservation(
            id: record.id,
            zone: record.zone,
            configuration: record.hasConfig ? DnsRecordConfiguration(
                name: record.config.name,
                type: record.config.type,
                value: record.config.value,
                ttl: record.config.ttl,
                priority: record.config.hasPriority ? record.config.priority : nil,
                weight: record.config.hasWeight ? record.config.weight : nil,
                port: record.config.hasPort ? record.config.port : nil,
                enabled: record.config.enabled
            ) : nil
        )
    }

    /// The store requires an SOA on every zone write; a configuration
    /// without one is refused here rather than sent as an empty message.
    nonisolated static func dnsZoneConfigMessage(
        _ configuration: DnsZoneConfiguration
    ) throws -> Claviron_Dns_ZoneConfig {
        guard let soa = configuration.soa else {
            throw ClavironClientFailure(
                kind: .invalidConfiguration,
                diagnosticDetail: "A DNS zone write requires its SOA configuration."
            )
        }
        var message = Claviron_Dns_ZoneConfig()
        message.domain = configuration.domain
        message.enabled = configuration.enabled
        message.soa.mname = soa.mname
        message.soa.rname = soa.rname
        message.soa.refresh = soa.refresh
        message.soa.retry = soa.retry
        message.soa.expire = soa.expire
        message.soa.minimum = soa.minimum
        return message
    }

    nonisolated static func dnsRecordConfigMessage(
        _ configuration: DnsRecordConfiguration
    ) -> Claviron_Dns_RecordConfig {
        var message = Claviron_Dns_RecordConfig()
        message.name = configuration.name
        message.type = configuration.type
        message.value = configuration.value
        message.ttl = configuration.ttl
        if let priority = configuration.priority {
            message.priority = priority
        }
        if let weight = configuration.weight {
            message.weight = weight
        }
        if let port = configuration.port {
            message.port = port
        }
        message.enabled = configuration.enabled
        return message
    }

    nonisolated static func dnsZoneReceipt(
        _ response: Claviron_Dns_ZoneResponse
    ) throws -> DnsManagementReceipt {
        guard response.hasZone else {
            throw ClavironClientFailure(
                kind: .protocolMismatch,
                diagnosticDetail: "DnsManager returned a zone response without a zone."
            )
        }
        return .zone(dnsZoneObservation(response.zone))
    }

    nonisolated static func dnsRecordReceipt(
        _ response: Claviron_Dns_RecordResponse
    ) throws -> DnsManagementReceipt {
        guard response.hasRecord else {
            throw ClavironClientFailure(
                kind: .protocolMismatch,
                diagnosticDetail: "DnsManager returned a record response without a record."
            )
        }
        return .record(dnsRecordObservation(response.record), zoneSerial: response.zoneSerial)
    }

    nonisolated static func dnsRemovalReceipt(
        _ response: Claviron_Dns_MutationResponse
    ) -> DnsManagementReceipt {
        .removed(
            zone: response.zone,
            zoneSerial: response.hasZoneSerial ? response.zoneSerial : nil
        )
    }

    public func performCertificateAction(
        _ action: CertificateManagementAction
    ) async throws -> CertificateManagementReceipt {
        do {
            let acmeClient = Claviron_Acme_AcmeManager.Client(wrapping: grpcClient)
            switch action {
            case let .importPEM(chain, privateKey, issuer):
                let client = Claviron_Certificates_CertificateTransfer.Client(wrapping: grpcClient)
                let message = Self.importMessage(chain: chain, privateKey: privateKey, issuer: issuer)
                let response = try await client.importCertificate(
                    request: ClientRequest(message: message), options: callOptions
                )
                return .imported(commonName: response.commonName)
            case let .exportPEM(commonName, includePrivateKey):
                let client = Claviron_Certificates_CertificateTransfer.Client(wrapping: grpcClient)
                let message = Self.exportMessage(commonName: commonName, includePrivateKey: includePrivateKey)
                let response = try await client.exportCertificate(
                    request: ClientRequest(message: message), options: callOptions
                )
                return Self.exportReceipt(response, includePrivateKey: includePrivateKey)
            case let .add(hostnames):
                var message = Claviron_Acme_AddCertificateRequest()
                message.aliases = hostnames
                let response = try await acmeClient.addCertificate(
                    request: ClientRequest(message: message),
                    options: issuanceCallOptions
                )
                return .added(id: response.id, attachedExisting: response.attachedExisting)
            case let .remove(commonName):
                var message = Claviron_Acme_UpdateCertificateRequest()
                message.cn = commonName
                let response = try await acmeClient.removeCertificate(
                    request: ClientRequest(message: message),
                    options: callOptions
                )
                return Self.certificateOperationReceipt(response)
            case let .renewACME(commonName):
                var message = Claviron_Acme_RenewCertificateRequest()
                message.cn = commonName
                // The order, challenge and finalize happen inside the call,
                // under the server's ACME policy, like issuance.
                let response = try await acmeClient.renewCertificate(
                    request: ClientRequest(message: message),
                    options: issuanceCallOptions
                )
                return .renewed(expiresAt: response.hasExpiresAt ? response.expiresAt.date : nil)
            case let .createRootCA(request):
                let mtlsClient = Claviron_Mtls_MtlsManager.Client(wrapping: grpcClient)
                let response = try await mtlsClient.createRootCa(
                    request: ClientRequest(message: Self.rootCAMessage(request)),
                    options: callOptions
                )
                return .local(Self.localCertificateObservation(response))
            case let .createLocal(request):
                guard request.subjectURI == nil || request.kind == .client else {
                    throw ClavironClientFailure(kind: .invalidConfiguration, diagnosticDetail: "A subject URI is valid only for a client certificate.")
                }
                guard request.permissions == nil || request.kind == .client else {
                    throw ClavironClientFailure(kind: .invalidConfiguration, diagnosticDetail: "Permissions are valid only for a client certificate.")
                }
                let mtlsClient = Claviron_Mtls_MtlsManager.Client(wrapping: grpcClient)
                let response = try await mtlsClient.createCertificate(
                    request: ClientRequest(message: Self.localCertificateMessage(request)),
                    options: callOptions
                )
                return .local(try Self.issuedLocalCertificate(response, request: request))
            case let .revoke(commonName):
                let mtlsClient = Claviron_Mtls_MtlsManager.Client(wrapping: grpcClient)
                var message = Claviron_Mtls_RevokeCertificateRequest()
                message.commonName = commonName
                let response = try await mtlsClient.revokeCertificate(
                    request: ClientRequest(message: message), options: callOptions
                )
                guard response.hasRevokedAt else {
                    throw ClavironClientFailure(kind: .unknown, diagnosticDetail: "The server did not confirm certificate revocation. Inspect the record before retrying.")
                }
                return .local(Self.localCertificateObservation(response))
            case let .renewLocal(commonName, validityDays):
                let mtlsClient = Claviron_Mtls_MtlsManager.Client(wrapping: grpcClient)
                let response = try await mtlsClient.renewCertificate(
                    request: ClientRequest(message: Self.renewalMessage(commonName: commonName, validityDays: validityDays)),
                    options: callOptions
                )
                return .local(Self.localCertificateObservation(response))
            }
        } catch {
            throw Self.map(error)
        }
    }

    nonisolated static func rootCAMessage(
        _ request: LocalRootCARequest
    ) -> Claviron_Mtls_CreateRootCaRequest {
        var message = Claviron_Mtls_CreateRootCaRequest()
        message.commonName = request.commonName
        message.validityDays = request.validityDays
        if let organization = request.organization {
            message.organization = organization
        }
        if let country = request.country {
            message.country = country
        }
        return message
    }

    nonisolated static func importMessage(
        chain: String, privateKey: String, issuer: String?
    ) -> Claviron_Certificates_ImportCertificateRequest {
        var message = Claviron_Certificates_ImportCertificateRequest()
        message.certificateChainPem = chain
        message.privateKeyPem = privateKey
        if let issuer { message.issuer = issuer }
        return message
    }

    nonisolated static func exportMessage(
        commonName: String, includePrivateKey: Bool
    ) -> Claviron_Certificates_ExportCertificateRequest {
        var message = Claviron_Certificates_ExportCertificateRequest()
        message.commonName = commonName
        message.includePrivateKey = includePrivateKey
        return message
    }

    nonisolated static func exportReceipt(
        _ response: Claviron_Certificates_ExportCertificateResponse,
        includePrivateKey: Bool
    ) -> CertificateManagementReceipt {
        .exported(chain: response.certificateChainPem,
                  privateKey: includePrivateKey && response.hasPrivateKeyPem ? response.privateKeyPem : nil)
    }

    nonisolated static func renewalMessage(
        commonName: String,
        validityDays: UInt32
    ) -> Claviron_Mtls_RenewCertificateRequest {
        var message = Claviron_Mtls_RenewCertificateRequest()
        message.commonName = commonName
        message.validityDays = validityDays
        return message
    }

    nonisolated static func localCertificateMessage(
        _ request: LocalCertificateRequest
    ) -> Claviron_Mtls_CreateCertificateRequest {
        var message = Claviron_Mtls_CreateCertificateRequest()
        message.commonName = request.commonName
        message.aliases = request.aliases
        message.validityDays = request.validityDays
        message.kind = switch request.kind {
        case .server: .server
        case .client: .client
        case .ca: .ca
        }
        if let caPathLength = request.caPathLength {
            message.caPathLen = caPathLength
        }
        if let issuer = request.issuer {
            message.issuer = issuer
        }
        if let subjectURI = request.subjectURI, request.kind == .client {
            message.subjectUri = subjectURI
        }
        if let permissions = request.permissions, request.kind == .client {
            var scope = Claviron_Mtls_CertificatePermissions()
            scope.names = permissions.names
            message.permissions = scope
        }
        return message
    }

    nonisolated static func issuedLocalCertificate(
        _ info: Claviron_Mtls_CertificateInfo,
        request: LocalCertificateRequest
    ) throws -> LocalCertificateObservation {
        if let subject = request.subjectURI {
            let identities = info.subjectUris.filter { !$0.hasPrefix("urn:claviron:permissions:") }
            guard request.kind == .client, info.kind == .client, identities == [subject] else {
                throw ClavironClientFailure(
                    kind: .certificateIdentityUnconfirmed,
                    diagnosticDetail: "The issued certificate did not confirm the requested client identity. Inspect the certificate before issuing another one."
                )
            }
        }
        if let permissions = request.permissions {
            guard info.kind == .client, info.hasPermissions,
                  Set(info.permissions.names) == Set(permissions.names) else {
                throw ClavironClientFailure(
                    kind: .certificateIdentityUnconfirmed,
                    diagnosticDetail: "The issued certificate did not confirm the requested permissions. Inspect the certificate before issuing another one."
                )
            }
        }
        return localCertificateObservation(info)
    }

    nonisolated static func localCertificateObservation(
        _ info: Claviron_Mtls_CertificateInfo
    ) -> LocalCertificateObservation {
        // A `switch` expression is only allowed as the source of an
        // assignment, not as an argument.
        let kind: ReportedLocalCertificateKind = switch info.kind {
        case .server: .kind(.server)
        case .client: .kind(.client)
        case .ca: .kind(.ca)
        case .unspecified: .unspecified
        case let .UNRECOGNIZED(rawValue): .unrecognized(rawValue)
        }
        return LocalCertificateObservation(
            id: info.id,
            commonName: info.commonName,
            aliases: info.aliases,
            issuedAt: info.hasIssuedAt ? timestampObservation(info.issuedAt) : nil,
            expiresAt: info.hasExpiresAt ? timestampObservation(info.expiresAt) : nil,
            enabled: info.enabled,
            kind: kind,
            issuerID: info.hasIssuerID ? info.issuerID : nil,
            subjectURIs: info.subjectUris,
            revokedAt: info.hasRevokedAt ? timestampObservation(info.revokedAt) : nil,
            permissions: info.hasPermissions ? info.permissions.names : nil
        )
    }

    nonisolated static func certificateOperationReceipt(
        _ response: Claviron_Acme_OperationResponse
    ) -> CertificateManagementReceipt {
        .operation(
            success: response.success,
            message: response.hasMessage ? response.message : nil
        )
    }

    /// ACME issuance happens inside the call (order, challenge, finalize);
    /// its duration belongs to the server's ACME policy, so the client sets
    /// no deadline of its own.
    private var issuanceCallOptions: CallOptions {
        var options = CallOptions.defaults
        options.timeout = nil
        options.waitForReady = true
        return options
    }

    // MARK: Domains

    public func loadDomains() async throws -> DomainInventorySnapshot {
        do {
            let client = Claviron_Domains_DomainManager.Client(wrapping: grpcClient)
            let registrars = try await client.listRegistrars(
                request: ClientRequest(message: Claviron_Domains_ListRegistrarsRequest()),
                options: callOptions
            )
            let domains = try await client.listDomains(
                request: ClientRequest(message: Claviron_Domains_ListDomainsRequest()),
                options: callOptions
            )
            return DomainInventorySnapshot(
                registrars: registrars.registrars.map(Self.registrarObservation),
                domains: domains.domains.map(Self.domainObservation)
            )
        } catch {
            throw Self.map(error)
        }
    }

    public func loadDomainRegistrarInfo(registrar: String, name: String) async throws -> DomainRegistrarInfo {
        do {
            let client = Claviron_Domains_DomainManager.Client(wrapping: grpcClient)
            var message = Claviron_Domains_GetDomainInfoRequest()
            message.registrar = registrar
            message.name = name
            let response = try await client.getDomainInfo(
                request: ClientRequest(message: message),
                options: registrarCallOptions
            )
            let info = response.info
            return DomainRegistrarInfo(
                name: info.name,
                registrar: info.registrar,
                registrarRef: info.registrarRef,
                registeredAt: info.hasRegisteredAt ? info.registeredAt.date : nil,
                expiresAt: info.hasExpiresAt ? info.expiresAt.date : nil,
                autoRenew: info.hasAutoRenew ? info.autoRenew : nil,
                whoisPrivacy: info.hasWhoisPrivacy ? info.whoisPrivacy : nil,
                nameservers: info.nameservers,
                registrarStatus: info.registrarStatus
            )
        } catch {
            throw Self.map(error)
        }
    }

    public func loadDomainNameservers(registrar: String, name: String) async throws -> DomainNameserversSnapshot {
        do {
            let client = Claviron_Domains_DomainManager.Client(wrapping: grpcClient)
            var message = Claviron_Domains_GetNameserversRequest()
            message.registrar = registrar
            message.name = name
            let response = try await client.getNameservers(
                request: ClientRequest(message: message),
                options: registrarCallOptions
            )
            return DomainNameserversSnapshot(name: response.name, nameservers: response.nameservers)
        } catch {
            throw Self.map(error)
        }
    }

    public func loadDomainTemplates() async throws -> [DomainTemplateObservation] {
        do {
            let client = Claviron_Domains_DomainManager.Client(wrapping: grpcClient)
            let response = try await client.listTemplates(
                request: ClientRequest(message: Claviron_Domains_ListTemplatesRequest()),
                options: callOptions
            )
            return response.templates.map(Self.templateObservation)
        } catch {
            throw Self.map(error)
        }
    }

    public func performDomainAction(
        _ action: DomainManagementAction
    ) async throws -> DomainManagementReceipt {
        do {
            let client = Claviron_Domains_DomainManager.Client(wrapping: grpcClient)
            switch action {
            case let .putTemplate(name, contacts, nameservers):
                var message = Claviron_Domains_PutTemplateRequest()
                message.name = name
                message.contacts = Self.contactsMessage(contacts)
                message.nameservers = nameservers
                let response = try await client.putTemplate(
                    request: ClientRequest(message: message),
                    options: callOptions
                )
                return .template(Self.templateObservation(response.template))
            case let .removeTemplate(name):
                var message = Claviron_Domains_RemoveTemplateRequest()
                message.name = name
                let response = try await client.removeTemplate(
                    request: ClientRequest(message: message),
                    options: callOptions
                )
                return .templateRemoved(name: name, removed: response.removed)
            case let .add(registrar, name):
                var message = Claviron_Domains_AddDomainRequest()
                message.registrar = registrar
                message.name = name
                let response = try await client.addDomain(
                    request: ClientRequest(message: message),
                    options: registrarCallOptions
                )
                return .domain(Self.domainObservation(response.domain))
            case let .refresh(name):
                var message = Claviron_Domains_RefreshDomainRequest()
                message.name = name
                let response = try await client.refreshDomain(
                    request: ClientRequest(message: message),
                    options: registrarCallOptions
                )
                return .domain(Self.domainObservation(response.domain))
            case let .renew(name, years):
                var message = Claviron_Domains_RenewDomainRequest()
                message.name = name
                message.years = years
                let response = try await client.renewDomain(
                    request: ClientRequest(message: message),
                    options: registrarCallOptions
                )
                return .domain(Self.domainObservation(response.domain))
            case let .syncRecords(name):
                var message = Claviron_Domains_SyncDnsRecordsRequest()
                message.name = name
                let response = try await client.syncDnsRecords(
                    request: ClientRequest(message: message),
                    options: registrarCallOptions
                )
                return .sync(DomainSyncReceipt(
                    found: response.found,
                    skipped: response.skipped,
                    created: response.created,
                    updated: response.updated,
                    failed: response.failed.map { (domain: $0.domain, message: $0.message) }
                ))
            case let .setNameservers(registrar, name, nameservers):
                var message = Claviron_Domains_SetNameserversRequest()
                message.registrar = registrar
                message.name = name
                message.nameservers = nameservers
                let response = try await client.setNameservers(
                    request: ClientRequest(message: message),
                    options: registrarCallOptions
                )
                return .nameservers(DomainNameserversSnapshot(name: response.name, nameservers: response.nameservers))
            case let .useClavironNameservers(registrar, name):
                var message = Claviron_Domains_UseClavironNameserversRequest()
                message.registrar = registrar
                message.name = name
                let response = try await client.useClavironNameservers(
                    request: ClientRequest(message: message),
                    options: registrarCallOptions
                )
                return .nameservers(DomainNameserversSnapshot(name: response.name, nameservers: response.nameservers))
            case let .sync(registrar):
                var message = Claviron_Domains_SyncDomainsRequest()
                message.registrar = registrar ?? ""
                let response = try await client.syncDomains(
                    request: ClientRequest(message: message),
                    options: registrarCallOptions
                )
                return .sync(DomainSyncReceipt(
                    found: response.found,
                    skipped: response.skipped,
                    created: response.created,
                    updated: response.updated,
                    failed: response.failed.map { (domain: $0.domain, message: $0.message) }
                ))
            }
        } catch {
            throw Self.map(error)
        }
    }

    /// A registrar call leaves the process for a third party; it is bounded
    /// by the server's own HTTP timeout, not by the probe deadline.
    private var registrarCallOptions: CallOptions {
        var options = CallOptions.defaults
        options.waitForReady = true
        return options
    }

    nonisolated static func templateObservation(
        _ template: Claviron_Domains_DomainTemplate
    ) -> DomainTemplateObservation {
        DomainTemplateObservation(
            id: template.id,
            name: template.name,
            contacts: template.hasContacts ? contactsObservation(template.contacts) : nil,
            nameservers: template.nameservers,
            updatedAt: template.hasUpdatedAt ? template.updatedAt.date : nil
        )
    }

    nonisolated static func contactsObservation(
        _ contacts: Claviron_Domains_Contacts
    ) -> DomainContacts {
        DomainContacts(
            registrant: contactObservation(contacts.registrant),
            admin: contacts.hasAdmin ? contactObservation(contacts.admin) : nil,
            tech: contacts.hasTech ? contactObservation(contacts.tech) : nil,
            billing: contacts.hasBilling ? contactObservation(contacts.billing) : nil
        )
    }

    nonisolated static func contactObservation(
        _ contact: Claviron_Domains_Contact
    ) -> DomainContact {
        DomainContact(
            firstName: contact.firstName,
            lastName: contact.lastName,
            address1: contact.address1,
            address2: contact.address2,
            city: contact.city,
            stateProvince: contact.stateProvince,
            postalCode: contact.postalCode,
            country: contact.country,
            phone: contact.phone,
            email: contact.email
        )
    }

    nonisolated static func contactsMessage(
        _ contacts: DomainContacts
    ) -> Claviron_Domains_Contacts {
        var message = Claviron_Domains_Contacts()
        message.registrant = contactMessage(contacts.registrant)
        if let admin = contacts.admin { message.admin = contactMessage(admin) }
        if let tech = contacts.tech { message.tech = contactMessage(tech) }
        if let billing = contacts.billing { message.billing = contactMessage(billing) }
        return message
    }

    nonisolated static func contactMessage(
        _ contact: DomainContact
    ) -> Claviron_Domains_Contact {
        var message = Claviron_Domains_Contact()
        message.firstName = contact.firstName
        message.lastName = contact.lastName
        message.address1 = contact.address1
        message.address2 = contact.address2
        message.city = contact.city
        message.stateProvince = contact.stateProvince
        message.postalCode = contact.postalCode
        message.country = contact.country
        message.phone = contact.phone
        message.email = contact.email
        return message
    }

    nonisolated static func registrarObservation(
        _ registrar: Claviron_Domains_RegistrarInfo
    ) -> RegistrarObservation {
        RegistrarObservation(
            name: registrar.name,
            configured: registrar.configured,
            supportsRegistration: registrar.supportsRegistration,
            supportsDns: registrar.supportsDns,
            supportsGlue: registrar.supportsGlue
        )
    }

    nonisolated static func domainObservation(
        _ domain: Claviron_Domains_Domain
    ) -> DomainObservation {
        DomainObservation(
            id: domain.id,
            name: domain.name,
            registrar: domain.registrar,
            registrarRef: domain.registrarRef,
            dnsProvider: domain.dnsProvider,
            status: domainStatus(domain.status),
            registeredAt: domain.hasRegisteredAt ? domain.registeredAt.date : nil,
            expiresAt: domain.hasExpiresAt ? domain.expiresAt.date : nil,
            autoRenew: domain.autoRenew,
            renewBeforeDays: domain.renewBeforeDays,
            whoisPrivacy: domain.whoisPrivacy,
            updatedAt: domain.hasUpdatedAt ? domain.updatedAt.date : nil
        )
    }

    nonisolated static func domainStatus(
        _ status: Claviron_Domains_DomainStatus
    ) -> DomainStatusObservation {
        switch status {
        case .unspecified: .unspecified
        case .pending: .pending
        case .active: .active
        case .expired: .expired
        case .suspended: .suspended
        case .transferring: .transferring
        case .failed: .failed
        case let .UNRECOGNIZED(value): .unrecognized(value)
        }
    }

    var callOptions: CallOptions {
        var options = CallOptions.defaults
        options.timeout = probeTimeout
        options.waitForReady = true
        return options
    }

    private func taskRunCallOptions(
        executionTimeout: ProtobufDurationObservation?
    ) -> CallOptions {
        var options = CallOptions.defaults
        options.timeout = Self.taskRunResponseTimeout(
            executionTimeout: executionTimeout
        )
        options.waitForReady = true
        return options
    }

    nonisolated static func taskRunResponseTimeout(
        executionTimeout: ProtobufDurationObservation?
    ) -> Duration? {
        guard let executionTimeout,
              executionTimeout.seconds >= 0,
              (0..<1_000_000_000).contains(executionTimeout.nanoseconds) else {
            return nil
        }

        let executionBudget = Duration.seconds(executionTimeout.seconds)
            + .nanoseconds(executionTimeout.nanoseconds)
        return executionBudget + .seconds(30)
    }

    nonisolated static func serviceObservation(
        _ service: Claviron_Services_ServiceStatus
    ) -> ServiceObservation {
        ServiceObservation(
            name: service.name,
            placements: service.placements.map(Self.placementObservation)
        )
    }

    private nonisolated static func placementObservation(
        _ placement: Claviron_Services_ServicePlacement
    ) -> ServicePlacementObservation {
        ServicePlacementObservation(
            member: placement.hasMember ? ServiceMemberObservation(
                nodeID: placement.member.nodeID,
                role: Self.memberRole(placement.member.role)
            ) : nil,
            lifecycle: Self.lifecycle(placement.lifecycle),
            reloadable: placement.reloadable,
            generation: placement.generation,
            reloadRevision: placement.reloadRevision,
            lastError: placement.hasLastError ? placement.lastError : nil,
            lastErrorTruncated: placement.lastErrorTruncated,
            lastReloadError: placement.hasLastReloadError ? placement.lastReloadError : nil,
            lastReloadErrorTruncated: placement.lastReloadErrorTruncated,
            observedAt: placement.hasObservedAt ? placement.observedAt.date : nil,
            startPolicy: Self.startPolicy(placement.startPolicy),
            activeExecutions: placement.hasActiveExecutions ? placement.activeExecutions : nil,
            dispatch: Self.serviceDispatch(placement.dispatch)
        )
    }

    private nonisolated static func serviceDispatch(
        _ value: Claviron_Services_ServiceDispatch
    ) -> ServiceDispatchObservation {
        switch value {
        case .unspecified: .unspecified
        case .each: .each
        case .one: .one
        case .pool: .pool
        case let .UNRECOGNIZED(rawValue): .unrecognized(rawValue)
        }
    }

    private nonisolated static func lifecycle(
        _ value: Claviron_Services_ServiceLifecycle
    ) -> ServiceLifecycleObservation {
        switch value {
        case .unspecified:
            .unspecified
        case .running:
            .running
        case .stopping:
            .stopping
        case .stopped:
            .stopped
        case .failed:
            .failed
        case let .UNRECOGNIZED(rawValue):
            .unrecognized(rawValue)
        }
    }

    private nonisolated static func startPolicy(
        _ value: Claviron_Services_ServiceStartPolicy
    ) -> ServiceStartPolicyObservation {
        switch value {
        case .unspecified:
            .unspecified
        case .automatic:
            .automatic
        case .manual:
            .manual
        case .unavailable:
            .unavailable
        case let .UNRECOGNIZED(rawValue):
            .unrecognized(rawValue)
        }
    }

    private nonisolated static func memberRole(
        _ value: Claviron_Services_ServiceMemberRole
    ) -> ServiceMemberRoleObservation {
        switch value {
        case .unspecified:
            .unspecified
        case .master:
            .master
        case .worker:
            .worker
        case .standalone:
            .standalone
        case let .UNRECOGNIZED(rawValue):
            .unrecognized(rawValue)
        }
    }

    nonisolated static func workerFleetSnapshot(
        _ response: Claviron_Workers_ListWorkersResponse
    ) -> WorkerFleetSnapshot {
        WorkerFleetSnapshot(
            capturedAt: response.hasCapturedAt ? response.capturedAt.date : nil,
            workersExpected: response.workersExpected,
            master: response.hasMaster ? Self.masterIdentity(response.master) : nil,
            fleetMode: Self.fleetMode(response.fleetMode),
            build: response.hasBuild ? BuildIdentityObservation(
                revision: response.build.revision,
                dirty: response.build.dirty
            ) : nil,
            workers: response.workers.map(Self.workerObservation)
        )
    }

    nonisolated static func workerObservation(
        _ worker: Claviron_Workers_WorkerStatus
    ) -> WorkerObservation {
        WorkerObservation(
            workerID: worker.workerID,
            lifecycle: Self.workerLifecycle(worker.lifecycle),
            ownership: Self.workerOwnership(worker.ownership),
            process: worker.hasProcess ? Self.processIdentity(worker.process) : nil,
            uptime: worker.hasUptime ? Self.duration(worker.uptime) : nil,
            recoveryAttempts: worker.recoveryAttempts,
            reloadRevision: worker.reloadRevision,
            incarnation: worker.incarnation,
            phase: Self.workerPhase(worker.phase),
            phaseAge: worker.hasPhaseAge ? Self.duration(worker.phaseAge) : nil,
            desired: worker.hasDesired ? Self.workerDesiredState(worker.desired) : .unspecified,
            desiredAge: worker.hasDesiredAge ? Self.duration(worker.desiredAge) : nil,
            operation: worker.hasOperation ? Self.workerOperation(worker.operation) : nil,
            heartbeatAge: worker.hasHeartbeatAge ? Self.duration(worker.heartbeatAge) : nil,
            blockReason: Self.workerBlockReason(worker.blockReason)
        )
    }

    private nonisolated static func processIdentity(
        _ value: Claviron_Workers_ProcessIdentity
    ) -> ProcessIdentityObservation {
        ProcessIdentityObservation(pid: value.pid, startedAt: value.startedAt)
    }

    private nonisolated static func masterIdentity(
        _ value: Claviron_Workers_MasterIdentity
    ) -> MasterIdentityObservation {
        MasterIdentityObservation(
            process: value.hasProcess ? Self.processIdentity(value.process) : nil,
            generation: value.generation
        )
    }

    private nonisolated static func fleetMode(
        _ value: Claviron_Workers_FleetMode
    ) -> FleetModeObservation {
        switch value {
        case .unspecified:
            .unspecified
        case .running:
            .running
        case .shuttingDown:
            .shuttingDown
        case let .UNRECOGNIZED(rawValue):
            .unrecognized(rawValue)
        }
    }

    private nonisolated static func workerLifecycle(
        _ value: Claviron_Workers_WorkerLifecycle
    ) -> WorkerLifecycleObservation {
        switch value {
        case .unspecified:
            .unspecified
        case .starting:
            .starting
        case .running:
            .running
        case .reloading:
            .reloading
        case .stopping:
            .stopping
        case .stopped:
            .stopped
        case .exited:
            .exited
        case .crashed:
            .crashed
        case .unclaimed:
            .unclaimed
        case let .UNRECOGNIZED(rawValue):
            .unrecognized(rawValue)
        }
    }

    private nonisolated static func workerOwnership(
        _ value: Claviron_Workers_WorkerOwnership
    ) -> WorkerOwnershipObservation {
        switch value {
        case .unspecified:
            .unspecified
        case .unowned:
            .unowned
        case .spawned:
            .spawned
        case .adopted:
            .adopted
        case let .UNRECOGNIZED(rawValue):
            .unrecognized(rawValue)
        }
    }

    private nonisolated static func workerPhase(
        _ value: Claviron_Workers_WorkerPhase
    ) -> WorkerPhaseObservation {
        switch value {
        case .unspecified:
            .unspecified
        case .unclaimed:
            .unclaimed
        case .ownershipPending:
            .ownershipPending
        case .reconciliationBlocked:
            .reconciliationBlocked
        case .starting:
            .starting
        case .running:
            .running
        case .reloading:
            .reloading
        case .drainAcknowledged:
            .drainAcknowledged
        case .teardownCompleted:
            .teardownCompleted
        case .exitedPlanned:
            .exitedPlanned
        case .exitedFailed:
            .exitedFailed
        case let .UNRECOGNIZED(rawValue):
            .unrecognized(rawValue)
        }
    }

    private nonisolated static func workerDesiredState(
        _ value: Claviron_Workers_WorkerDesiredState
    ) -> WorkerDesiredStateObservation {
        switch value.state {
        case .ensureRunning:
            .ensureRunning
        case .stopped:
            .stopped
        case let .drain(drain):
            .drain(
                reason: Self.drainReason(drain.reason),
                afterExit: Self.exitDisposition(drain.afterExit)
            )
        case nil:
            .unspecified
        }
    }

    private nonisolated static func drainReason(
        _ value: Claviron_Workers_WorkerDrainReason
    ) -> WorkerDrainReasonObservation {
        switch value {
        case .unspecified:
            .unspecified
        case .shutdown:
            .shutdown
        case .scaleDown:
            .scaleDown
        case .rotation:
            .rotation
        case .heartbeatTimeout:
            .heartbeatTimeout
        case .manualStop:
            .manualStop
        case .rollingRestart:
            .rollingRestart
        case let .UNRECOGNIZED(rawValue):
            .unrecognized(rawValue)
        }
    }

    private nonisolated static func exitDisposition(
        _ value: Claviron_Workers_WorkerExitDisposition
    ) -> WorkerExitDispositionObservation {
        switch value {
        case .unspecified:
            .unspecified
        case .stayStopped:
            .stayStopped
        case .replace:
            .replace
        case .removeSlot:
            .removeSlot
        case .finishFleetShutdown:
            .finishFleetShutdown
        case let .UNRECOGNIZED(rawValue):
            .unrecognized(rawValue)
        }
    }

    private nonisolated static func workerOperation(
        _ value: Claviron_Workers_WorkerOperation
    ) -> WorkerOperationObservation {
        WorkerOperationObservation(
            id: value.id,
            kind: Self.operationKind(value),
            origin: value.hasOrigin ? Self.operationOrigin(value.origin) : .unspecified,
            age: value.hasAge ? Self.duration(value.age) : nil
        )
    }

    private nonisolated static func operationKind(
        _ value: Claviron_Workers_WorkerOperation
    ) -> WorkerOperationKindObservation {
        switch value.kind {
        case .unspecified:
            .unspecified
        case .start:
            .start
        case .stop:
            .stop
        case .restart:
            .restart
        case .reload:
            .reload
        case .rotation:
            .rotation
        case .heartbeatRecovery:
            .heartbeatRecovery
        case .crashRecovery:
            .crashRecovery
        case .reloadAll:
            .reloadAll
        case .restartAll:
            .restartAll
        case .resize:
            .resize(from: value.resizeFrom, to: value.resizeTo)
        case .configReload:
            .configReload
        case .fleetShutdown:
            .fleetShutdown
        case let .UNRECOGNIZED(rawValue):
            .unrecognized(rawValue)
        }
    }

    private nonisolated static func operationOrigin(
        _ value: Claviron_Workers_WorkerOperationOrigin
    ) -> WorkerOperationOriginObservation {
        switch value.origin {
        case let .management(management):
            .management(
                viaWorker: management.hasViaWorker ? management.viaWorker : nil,
                submissionKey: management.submissionKey
            )
        case .supervisor:
            .supervisor
        case .signal:
            .signal
        case nil:
            .unspecified
        }
    }

    private nonisolated static func workerBlockReason(
        _ value: Claviron_Workers_WorkerBlockReason
    ) -> WorkerBlockReasonObservation? {
        switch value {
        case .unspecified:
            nil
        case .stalePresence:
            .stalePresence
        case .workerNotRunning:
            .workerNotRunning
        case .workerBusy:
            .workerBusy
        case .unknownMaster:
            .unknownMaster
        case .masterStillAlive:
            .masterStillAlive
        case .masterNotOlder:
            .masterNotOlder
        case .identityChanged:
            .identityChanged
        case let .UNRECOGNIZED(rawValue):
            .unrecognized(rawValue)
        }
    }

    nonisolated static func applicationObservation(
        _ application: Claviron_Applications_ApplicationStatus
    ) -> ApplicationObservation {
        ApplicationObservation(
            applicationID: application.hasID ? ApplicationIDObservation(
                runtime: application.id.runtime,
                name: application.id.name
            ) : nil,
            placements: application.placements.map(Self.applicationPlacementObservation)
        )
    }

    private nonisolated static func applicationPlacementObservation(
        _ placement: Claviron_Applications_ApplicationPlacement
    ) -> ApplicationPlacementObservation {
        ApplicationPlacementObservation(
            member: placement.hasMember ? ApplicationMemberObservation(
                nodeID: placement.member.nodeID,
                role: Self.applicationMemberRole(placement.member.role)
            ) : nil,
            lifecycle: Self.applicationLifecycle(placement.lifecycle),
            enabled: placement.enabled,
            generation: placement.generation,
            pool: placement.hasPool ? Self.applicationPoolObservation(placement.pool) : nil,
            lastError: placement.hasLastError ? placement.lastError : nil,
            lastErrorTruncated: placement.lastErrorTruncated,
            observedAt: placement.hasObservedAt ? placement.observedAt.date : nil,
            description: placement.hasDescription_p ? ApplicationDescriptionObservation(placement.description_p) : nil
        )
    }

    private nonisolated static func applicationPoolObservation(
        _ pool: Claviron_Applications_ApplicationPoolStatus
    ) -> ApplicationPoolObservation {
        ApplicationPoolObservation(
            accepting: pool.hasAccepting ? pool.accepting : nil,
            instances: pool.instances,
            ready: pool.hasReady ? pool.ready : nil,
            busy: pool.hasBusy ? pool.busy : nil,
            retiring: pool.hasRetiring ? pool.retiring : nil,
            backingOff: pool.hasBackingOff ? pool.backingOff : nil,
            exhausted: pool.hasExhausted ? pool.exhausted : nil
        )
    }

    private nonisolated static func applicationLifecycle(
        _ value: Claviron_Applications_ApplicationLifecycle
    ) -> ApplicationLifecycleObservation {
        switch value {
        case .unspecified:
            .unspecified
        case .starting:
            .starting
        case .running:
            .running
        case .stopping:
            .stopping
        case .stopped:
            .stopped
        case .failed:
            .failed
        case let .UNRECOGNIZED(rawValue):
            .unrecognized(rawValue)
        }
    }

    private nonisolated static func applicationMemberRole(
        _ value: Claviron_Applications_FleetMemberRole
    ) -> ApplicationMemberRoleObservation {
        switch value {
        case .unspecified:
            .unspecified
        case .master:
            .master
        case .worker:
            .worker
        case .standalone:
            .standalone
        case let .UNRECOGNIZED(rawValue):
            .unrecognized(rawValue)
        }
    }

    nonisolated static func taskObservation(
        _ task: Claviron_Tasks_TaskStatus
    ) -> TaskObservation {
        TaskObservation(
            name: task.name,
            kind: Self.taskKind(task.kind),
            scope: Self.taskScope(task.scope),
            dispatch: Self.taskDispatch(task.dispatch),
            timing: task.hasTiming ? Self.taskTiming(task.timing) : nil,
            concurrency: task.concurrency,
            placements: task.placements.map(Self.taskPlacementObservation)
        )
    }

    private nonisolated static func taskTiming(
        _ timing: Claviron_Tasks_TaskTiming
    ) -> TaskTimingObservation {
        switch timing.schedule {
        case let .daemon(daemon):
            .daemon(enabled: daemon.enabled)
        case let .interval(interval):
            .interval(
                every: interval.hasEvery ? Self.duration(interval.every) : nil,
                executionTimeout: interval.hasExecutionTimeout
                    ? Self.duration(interval.executionTimeout)
                    : nil,
                enabled: interval.enabled
            )
        case let .cron(cron):
            .cron(
                expression: cron.expression,
                executionTimeout: cron.hasExecutionTimeout
                    ? Self.duration(cron.executionTimeout)
                    : nil,
                enabled: cron.enabled
            )
        case let .manual(manual):
            .manual(
                executionTimeout: manual.hasExecutionTimeout
                    ? Self.duration(manual.executionTimeout)
                    : nil
            )
        case nil:
            .unspecified
        }
    }

    private nonisolated static func taskPlacementObservation(
        _ placement: Claviron_Tasks_TaskPlacementStatus
    ) -> TaskPlacementObservation {
        TaskPlacementObservation(
            member: placement.hasMember ? TaskMemberObservation(
                nodeID: placement.member.nodeID,
                role: Self.taskMemberRole(placement.member.role)
            ) : nil,
            lifecycle: Self.taskLifecycle(placement.lifecycle),
            inFlight: placement.inFlight,
            lastExecution: placement.hasLastExecution
                ? Self.taskExecutionOutcome(placement.lastExecution)
                : nil,
            observedAt: placement.hasObservedAt ? placement.observedAt.date : nil,
            generation: placement.generation,
            ownedSlots: placement.ownedSlots
        )
    }

    private nonisolated static func taskExecutionOutcome(
        _ outcome: Claviron_Tasks_TaskExecutionOutcome
    ) -> TaskExecutionOutcomeObservation {
        TaskExecutionOutcomeObservation(
            result: Self.taskExecutionResult(outcome.result),
            finishedAt: outcome.hasFinishedAt ? outcome.finishedAt.date : nil
        )
    }

    private nonisolated static func duration(
        _ duration: SwiftProtobuf.Google_Protobuf_Duration
    ) -> ProtobufDurationObservation {
        ProtobufDurationObservation(
            seconds: duration.seconds,
            nanoseconds: duration.nanos
        )
    }

    private nonisolated static func taskKind(
        _ value: Claviron_Tasks_TaskKind
    ) -> TaskKindObservation {
        switch value {
        case .unspecified: .unspecified
        case .builtin: .builtin
        case .command: .command
        case .php: .php
        case .js: .js
        case .lua: .lua
        case let .UNRECOGNIZED(rawValue): .unrecognized(rawValue)
        }
    }

    private nonisolated static func taskScope(
        _ value: Claviron_Tasks_TaskScope
    ) -> TaskScopeObservation {
        switch value {
        case .unspecified: .unspecified
        case .master: .master
        case .workers: .workers
        case .fleet: .fleet
        case let .UNRECOGNIZED(rawValue): .unrecognized(rawValue)
        }
    }

    private nonisolated static func taskDispatch(
        _ value: Claviron_Tasks_TaskDispatch
    ) -> TaskDispatchObservation {
        switch value {
        case .unspecified: .unspecified
        case .each: .each
        case .one: .one
        case .pool: .pool
        case let .UNRECOGNIZED(rawValue): .unrecognized(rawValue)
        }
    }

    private nonisolated static func taskMemberRole(
        _ value: Claviron_Tasks_TaskMemberRole
    ) -> TaskMemberRoleObservation {
        switch value {
        case .unspecified: .unspecified
        case .master: .master
        case .worker: .worker
        case .standalone: .standalone
        case let .UNRECOGNIZED(rawValue): .unrecognized(rawValue)
        }
    }

    private nonisolated static func taskLifecycle(
        _ value: Claviron_Tasks_TaskLifecycle
    ) -> TaskLifecycleObservation {
        switch value {
        case .unspecified: .unspecified
        case .ineligible: .ineligible
        case .disabled: .disabled
        case .inactive: .inactive
        case .active: .active
        case .stopping: .stopping
        case .finished: .finished
        case .missingRunner: .missingRunner
        case let .UNRECOGNIZED(rawValue): .unrecognized(rawValue)
        }
    }

    private nonisolated static func taskExecutionResult(
        _ value: Claviron_Tasks_TaskExecutionResult
    ) -> TaskExecutionResultObservation {
        switch value {
        case .unspecified: .unspecified
        case .succeeded: .succeeded
        case .failed: .failed
        case .cancelled: .cancelled
        case .timedOut: .timedOut
        case .gaveUp: .gaveUp
        case let .UNRECOGNIZED(rawValue): .unrecognized(rawValue)
        }
    }

    nonisolated static func hostedVhostObservation(
        _ hosted: Claviron_Aliases_HostingVhostInfo
    ) -> HostedVhostObservation {
        HostedVhostObservation(
            vhost: hosted.hasVhost ? VhostObservation(
                id: hosted.vhost.id,
                name: hosted.vhost.name,
                enabled: hosted.vhost.enabled,
                readOnly: hosted.vhost.readOnly,
                readOnlyReason: hosted.vhost.hasReadOnlyReason ? hosted.vhost.readOnlyReason : nil
            ) : nil,
            aliases: hosted.aliases.map { alias in
                VhostAliasObservation(
                    id: alias.id,
                    hostname: alias.hostname,
                    enabled: alias.hasEnabled ? alias.enabled : nil,
                    readOnly: alias.readOnly,
                    readOnlyReason: alias.hasReadOnlyReason ? alias.readOnlyReason : nil
                )
            },
            servers: hosted.servers.map { server in
                HostingServerObservation(
                    id: server.id,
                    name: server.name,
                    enabled: server.enabled
                )
            }
        )
    }

    nonisolated static func hostedCertificateObservation(
        _ hosted: Claviron_Acme_CertificateInventoryInfo
    ) -> HostedCertificateObservation {
        HostedCertificateObservation(
            certificate: hosted.hasCertificate ? CertificateObservation(
                id: hosted.certificate.id,
                commonName: hosted.certificate.cname,
                aliases: hosted.certificate.aliases,
                issuedAt: hosted.certificate.hasIssuedAt
                    ? timestampObservation(hosted.certificate.issuedAt)
                    : nil,
                expiresAt: hosted.certificate.hasExpiresAt
                    ? timestampObservation(hosted.certificate.expiresAt)
                    : nil,
                updatedAt: hosted.certificate.hasUpdatedAt
                    ? timestampObservation(hosted.certificate.updatedAt)
                    : nil,
                enabled: hosted.certificate.enabled,
                kind: inventoryKind(hosted.certificate.kind),
                revokedAt: hosted.certificate.hasRevokedAt
                    ? timestampObservation(hosted.certificate.revokedAt) : nil
            ) : nil,
            servers: hosted.servers.map { server in
                CertificateServerObservation(
                    id: server.id,
                    name: server.name,
                    enabled: server.enabled
                )
            }
        )
    }

    nonisolated static func inventoryKind(
        _ kind: Claviron_Acme_CertificateKind
    ) -> ReportedLocalCertificateKind {
        switch kind {
        case .server: .kind(.server)
        case .client: .kind(.client)
        case .ca: .kind(.ca)
        case .unspecified: .unspecified
        case let .UNRECOGNIZED(value): .unrecognized(value)
        }
    }

    private nonisolated static func timestampObservation(
        _ timestamp: Google_Protobuf_Timestamp
    ) -> ProtobufTimestampObservation {
        ProtobufTimestampObservation(
            seconds: timestamp.seconds,
            nanoseconds: timestamp.nanos
        )
    }

    public func disconnect() async {
        grpcClient.beginGracefulShutdown()
        _ = await connectionTask?.result
        connectionTask = nil
    }

    nonisolated static func map(
        _ error: any Error,
        defaultKind: ClavironClientFailure.Kind = .unknown
    ) -> ClavironClientFailure {
        if let failure = error as? ClavironClientFailure {
            return failure
        }

        if let rpcError = error as? RPCError {
            let kind: ClavironClientFailure.Kind
            if Self.containsTLSHandshakeFailure(rpcError) {
                kind = .tlsHandshakeFailed
            } else {
                switch rpcError.code {
                case .unauthenticated, .permissionDenied:
                    kind = .authenticationRejected
                case .unavailable:
                    kind = .unavailable
                case .deadlineExceeded:
                    kind = .timedOut
                case .cancelled:
                    kind = .cancelled
                case .unimplemented:
                    kind = .protocolMismatch
                default:
                    kind = .serverRejected
                }
            }
            return ClavironClientFailure(
                kind: kind,
                diagnosticDetail: rpcError.description
            )
        }

        if error is CancellationError {
            return ClavironClientFailure(
                kind: .cancelled,
                diagnosticDetail: String(describing: error)
            )
        }

        return ClavironClientFailure(
            kind: defaultKind,
            diagnosticDetail: String(describing: error)
        )
    }

    private nonisolated static func containsTLSHandshakeFailure(
        _ error: any Error,
        remainingDepth: Int = 8
    ) -> Bool {
        guard remainingDepth > 0 else {
            return false
        }

        if let sslError = error as? NIOSSLError {
            switch sslError {
            case .handshakeFailed, .noCertificateToValidate,
                 .unableToValidateCertificate:
                return true
            case .writeDuringTLSShutdown, .unableToAllocateBoringSSLObject,
                 .noSuchFilesystemObject, .failedToLoadCertificate,
                 .failedToLoadPrivateKey, .shutdownFailed, .cannotMatchULabel,
                 .cannotFindPeerIP, .readInInvalidTLSState, .uncleanShutdown:
                return false
            }
        }

        if let extraError = error as? NIOSSLExtraError {
            return extraError == .failedToValidateHostname
                || extraError == .serverHostnameImpossibleToMatch
        }

        let cause: (any Error)?
        if let rpcError = error as? RPCError {
            cause = rpcError.cause
        } else if let runtimeError = error as? RuntimeError {
            cause = runtimeError.cause
        } else {
            cause = nil
        }

        guard let cause else {
            return false
        }
        return Self.containsTLSHandshakeFailure(
            cause,
            remainingDepth: remainingDepth - 1
        )
    }
}
