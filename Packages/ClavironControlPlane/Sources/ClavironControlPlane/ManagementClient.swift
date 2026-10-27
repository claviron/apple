import Foundation
import GRPCCore

public extension ClavironClient {
    func loadManagementSchema(_ resource: ManagementResource) async throws -> ManagementSchema { throw unsupportedManagement() }
    func loadManagedRecords(_ query: ManagementQuery) async throws -> ManagementPage { throw unsupportedManagement() }
    func loadManagedRecord(_ key: ManagedRecordKey) async throws -> ManagedRecord { throw unsupportedManagement() }
    func performManagementAction(_ action: ManagementAction) async throws -> ManagementMutation { throw unsupportedManagement() }
    func loadAssignmentSchema(_ relation: ManagementRelation) async throws -> ManagementAssignmentSchema { throw unsupportedManagement() }
    func loadAssignments(_ key: ManagementAssignmentKey) async throws -> ManagementAssignments { throw unsupportedManagement() }
    func replaceAssignments(_ assignments: ManagementAssignments) async throws -> ManagementAssignmentMutation { throw unsupportedManagement() }

    private func unsupportedManagement() -> ClavironClientFailure {
        ClavironClientFailure(kind: .protocolMismatch, diagnosticDetail: "User or authorization management is not supported by this client.")
    }
}

extension DirectClavironClient {
    public func loadManagementSchema(_ resource: ManagementResource) async throws -> ManagementSchema {
        do {
            let client = Claviron_Users_UserManagement.Client(wrapping: grpcClient)
            var message = Claviron_Users_GetSchemaRequest()
            message.resource = resource.wire
            let response = try await client.getSchema(request: ClientRequest(message: message), options: callOptions)
            guard response.resource == resource.wire, !response.revision.isEmpty else { throw invalidManagement() }
            return try Self.managementSchema(response)
        } catch { throw Self.managementFailure(error) }
    }

    public func loadManagedRecords(_ query: ManagementQuery) async throws -> ManagementPage {
        do {
            guard query.pageSize > 0 else { throw invalidManagement() }
            let client = Claviron_Users_UserManagement.Client(wrapping: grpcClient)
            var message = Claviron_Users_ListRecordsRequest()
            message.resource = query.resource.wire
            message.pageSize = query.pageSize
            if let cursor = query.cursor { message.cursor = cursor }
            if let search = query.search { message.query = search }
            let response = try await client.listRecords(request: ClientRequest(message: message), options: callOptions)
            return try Self.managementPage(response, query: query)
        } catch { throw Self.managementFailure(error) }
    }

    public func loadManagedRecord(_ key: ManagedRecordKey) async throws -> ManagedRecord {
        do {
            let client = Claviron_Users_UserManagement.Client(wrapping: grpcClient)
            var message = Claviron_Users_GetRecordRequest()
            message.key = try Self.managementKey(key)
            let response = try await client.getRecord(request: ClientRequest(message: message), options: callOptions)
            let record = try Self.managedRecord(response)
            guard record.key == key else { throw invalidManagement() }
            return record
        } catch { throw Self.managementFailure(error) }
    }

    public func performManagementAction(_ action: ManagementAction) async throws -> ManagementMutation {
        do {
            let client = Claviron_Users_UserManagement.Client(wrapping: grpcClient)
            let response: Claviron_Users_RecordMutationResult
            let resource: ManagementResource
            switch action {
            case let .create(kind, schemaRevision, values):
                guard !schemaRevision.isEmpty else { throw invalidManagement() }
                var message = Claviron_Users_CreateRecordRequest()
                resource = kind
                message.resource = kind.wire
                message.schemaRevision = schemaRevision
                message.dataJson = try ManagementValue.object(values).encoded()
                response = try await client.createRecord(request: ClientRequest(message: message), options: callOptions)
            case let .update(key, revision, schemaRevision, changes):
                guard !revision.isEmpty, !schemaRevision.isEmpty else { throw invalidManagement() }
                resource = key.resource
                var message = Claviron_Users_UpdateRecordRequest()
                message.key = try Self.managementKey(key)
                message.revision = revision
                message.schemaRevision = schemaRevision
                message.changesJson = try ManagementValue.object(changes).encoded()
                response = try await client.updateRecord(request: ClientRequest(message: message), options: callOptions)
            case let .delete(key, revision):
                guard !revision.isEmpty else { throw invalidManagement() }
                var message = Claviron_Users_DeleteRecordRequest()
                message.key = try Self.managementKey(key)
                message.revision = revision
                _ = try await client.deleteRecord(request: ClientRequest(message: message), options: callOptions)
                return .deleted
            }
            let result = try Self.managementMutation(response)
            if case let .record(record) = result {
                guard record.key.resource == resource else { throw invalidManagement() }
                if case let .update(key, _, _, _) = action, record.key != key { throw invalidManagement() }
            }
            return result
        } catch { throw Self.managementFailure(error) }
    }

    public func loadAssignmentSchema(_ relation: ManagementRelation) async throws -> ManagementAssignmentSchema {
        do {
            let client = Claviron_Users_UserManagement.Client(wrapping: grpcClient)
            var message = Claviron_Users_GetAssignmentSchemaRequest()
            message.relation = relation.wire
            let response = try await client.getAssignmentSchema(request: ClientRequest(message: message), options: callOptions)
            guard response.relation == relation.wire, !response.revision.isEmpty else { throw invalidManagement() }
            return try ManagementAssignmentSchema(relation: relation, revision: response.revision, operations: Self.managementOperations(response.operations))
        } catch { throw Self.managementFailure(error) }
    }

    public func loadAssignments(_ key: ManagementAssignmentKey) async throws -> ManagementAssignments {
        do {
            let client = Claviron_Users_UserManagement.Client(wrapping: grpcClient)
            var message = Claviron_Users_GetAssignmentsRequest()
            message.key = try Self.assignmentKey(key)
            let response = try await client.getAssignments(request: ClientRequest(message: message), options: callOptions)
            return try Self.managementAssignments(response, expected: key)
        } catch { throw Self.managementFailure(error) }
    }

    public func replaceAssignments(_ assignments: ManagementAssignments) async throws -> ManagementAssignmentMutation {
        do {
            guard !assignments.revision.isEmpty, Set(assignments.members).count == assignments.members.count,
                  assignments.members.allSatisfy({ !$0.isEmpty }) else { throw invalidManagement() }
            let client = Claviron_Users_UserManagement.Client(wrapping: grpcClient)
            var message = Claviron_Users_ReplaceAssignmentsRequest()
            message.key = try Self.assignmentKey(assignments.key)
            message.revision = assignments.revision
            message.members = assignments.members
            let response = try await client.replaceAssignments(request: ClientRequest(message: message), options: callOptions)
            switch response.outcome {
            case let .assignments(value): return .assignments(try Self.managementAssignments(value, expected: assignments.key))
            case let .validation(value): return .validation(try Self.managementViolations(value))
            case nil: throw invalidManagement()
            }
        } catch { throw Self.managementFailure(error) }
    }

    nonisolated static func managedRecord(_ value: Claviron_Users_ManagedRecord) throws -> ManagedRecord {
        guard value.hasKey, let resource = ManagementResource(wire: value.key.resource),
              !value.key.reference.isEmpty, !value.revision.isEmpty,
              let values = try ManagementValue.decode(value.dataJson).object else { throw invalidManagement() }
        return ManagedRecord(key: ManagedRecordKey(resource: resource, reference: value.key.reference), revision: value.revision, values: values)
    }

    nonisolated static func managementSchema(_ value: Claviron_Users_ManagementSchema) throws -> ManagementSchema {
        guard let resource = ManagementResource(wire: value.resource), !value.revision.isEmpty,
              let recordSchema = try ManagementValue.decode(value.recordSchemaJson).object else { throw invalidManagement() }
        return try ManagementSchema(resource: resource, revision: value.revision, recordSchema: recordSchema,
                                    create: value.hasCreate ? managementForm(value.create) : nil,
                                    update: value.hasUpdate ? managementForm(value.update) : nil,
                                    operations: managementOperations(value.operations))
    }

    nonisolated static func managementPage(_ value: Claviron_Users_ListRecordsResponse, query: ManagementQuery) throws -> ManagementPage {
        guard value.records.count <= Int(query.pageSize) else { throw invalidManagement() }
        let records = try value.records.map(managedRecord)
        guard records.count <= Int(query.pageSize), records.allSatisfy({ $0.key.resource == query.resource }),
              Set(records.map(\.key)).count == records.count,
              !value.hasNextCursor || !value.nextCursor.isEmpty else { throw invalidManagement() }
        return ManagementPage(records: records, nextCursor: value.hasNextCursor ? value.nextCursor : nil)
    }

    nonisolated static func managementMutation(_ value: Claviron_Users_RecordMutationResult) throws -> ManagementMutation {
        switch value.outcome {
        case let .record(record): return .record(try managedRecord(record))
        case let .validation(failure): return .validation(try managementViolations(failure))
        case nil: throw invalidManagement()
        }
    }

    nonisolated static func managementForm(_ form: Claviron_Management_Form) throws -> ManagementForm {
        guard let schema = try ManagementValue.decode(form.dataSchemaJson).object else { throw invalidManagement() }
        var layout: [String: ManagementValue]?
        if form.hasUiSchemaJson {
            guard let object = try ManagementValue.decode(form.uiSchemaJson).object else { throw invalidManagement() }
            layout = object
        }
        return ManagementForm(schema: schema, layout: layout)
    }

    nonisolated static func managementViolations(_ failure: Claviron_Management_ValidationFailure) throws -> [ManagementViolation] {
        guard !failure.violations.isEmpty else { throw invalidManagement() }
        return failure.violations.map { ManagementViolation(path: $0.path, code: $0.code, message: $0.message) }
    }

    nonisolated static func managementOperations(_ values: [Claviron_Users_Operation]) throws -> Set<ManagementOperation> {
        try Set(values.map {
            guard let operation = ManagementOperation(rawValue: $0.rawValue) else { throw invalidManagement() }
            return operation
        })
    }

    nonisolated static func managementKey(_ key: ManagedRecordKey) throws -> Claviron_Users_RecordKey {
        guard !key.reference.isEmpty else { throw invalidManagement() }
        var message = Claviron_Users_RecordKey()
        message.resource = key.resource.wire
        message.reference = key.reference
        return message
    }

    nonisolated static func assignmentKey(_ key: ManagementAssignmentKey) throws -> Claviron_Users_AssignmentKey {
        guard !key.reference.isEmpty else { throw invalidManagement() }
        var message = Claviron_Users_AssignmentKey()
        message.relation = key.relation.wire
        message.reference = key.reference
        return message
    }

    nonisolated static func managementAssignments(_ value: Claviron_Users_Assignments, expected: ManagementAssignmentKey) throws -> ManagementAssignments {
        guard value.hasKey, value.key.relation == expected.relation.wire, value.key.reference == expected.reference,
              !value.revision.isEmpty, value.members.allSatisfy({ !$0.isEmpty }), Set(value.members).count == value.members.count else { throw invalidManagement() }
        return ManagementAssignments(key: expected, revision: value.revision, members: value.members)
    }

    nonisolated static func managementFailure(_ error: any Error) -> any Error {
        if let issue = error as? ManagementClientError { return issue }
        guard let rpc = error as? RPCError else { return map(error) }
        switch rpc.code {
        case .aborted: return ManagementClientError("The record or its assignments changed. Reload before saving again.")
        case .failedPrecondition: return ManagementClientError("The management schema changed. Reload the form before saving again.")
        case .notFound: return ManagementClientError("This record is no longer available in your management scope.")
        case .permissionDenied: return ManagementClientError("This operation is not permitted for the connected identity.")
        case .unimplemented: return ManagementClientError("This server does not support the requested management operation.")
        default: return map(error)
        }
    }
}

private nonisolated func invalidManagement() -> ManagementClientError {
    ManagementClientError("The server returned an incomplete or inconsistent management response.")
}

extension ManagementResource {
    var wire: Claviron_Users_Resource {
        switch self { case .user: .user; case .role: .role; case .permission: .permission }
    }
    init?(wire: Claviron_Users_Resource) {
        switch wire { case .user: self = .user; case .role: self = .role; case .permission: self = .permission; default: return nil }
    }
}

extension ManagementRelation {
    var wire: Claviron_Users_Relation {
        switch self { case .userRoles: .userRoles; case .userPermissions: .userPermissions; case .rolePermissions: .rolePermissions }
    }
}
