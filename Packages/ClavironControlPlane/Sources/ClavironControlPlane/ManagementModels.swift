import Foundation

public enum ManagementResource: String, CaseIterable, Sendable {
    case user, role, permission
    public var title: String {
        switch self { case .user: "Users"; case .role: "Roles"; case .permission: "Permissions" }
    }
    public var singular: String {
        switch self { case .user: "User"; case .role: "Role"; case .permission: "Permission" }
    }
    public var capability: String { self == .user ? "users" : "authorization" }
}

public enum ManagementOperation: Int, Sendable {
    case list = 1, read, create, update, delete, readAssignments, replaceAssignments
}

public struct ManagedRecordKey: Hashable, Sendable {
    public let resource: ManagementResource
    public let reference: String
    public init(resource: ManagementResource, reference: String) {
        self.resource = resource
        self.reference = reference
    }
}

public struct ManagedRecord: Identifiable, Equatable, Sendable {
    public let key: ManagedRecordKey
    public let revision: String
    public let values: [String: ManagementValue]
    public var id: ManagedRecordKey { key }
    public var title: String {
        values["username"]?.string ?? values["name"]?.string ?? values["slug"]?.string ?? key.reference
    }
    public var subtitle: String { values["name"]?.string ?? key.reference }
    public init(key: ManagedRecordKey, revision: String, values: [String: ManagementValue]) {
        self.key = key
        self.revision = revision
        self.values = values
    }
}

public struct ManagementForm: Equatable, Sendable {
    public let schema: [String: ManagementValue]
    public let layout: [String: ManagementValue]?
    public init(schema: [String: ManagementValue], layout: [String: ManagementValue]? = nil) {
        self.schema = schema
        self.layout = layout
    }
}

public struct ManagementSchema: Equatable, Sendable {
    public let resource: ManagementResource
    public let revision: String
    public let recordSchema: [String: ManagementValue]
    public let create: ManagementForm?
    public let update: ManagementForm?
    public let operations: Set<ManagementOperation>
    public init(resource: ManagementResource, revision: String, recordSchema: [String: ManagementValue], create: ManagementForm?, update: ManagementForm?, operations: Set<ManagementOperation>) {
        self.resource = resource
        self.revision = revision
        self.recordSchema = recordSchema
        self.create = create
        self.update = update
        self.operations = operations
    }
}

public struct ManagementQuery: Equatable, Sendable {
    public let resource: ManagementResource
    public var pageSize: UInt32
    public var cursor: String?
    public var search: String?
    public init(resource: ManagementResource, pageSize: UInt32, cursor: String? = nil, search: String? = nil) {
        self.resource = resource
        self.pageSize = pageSize
        self.cursor = cursor
        self.search = search
    }
}

public struct ManagementPage: Equatable, Sendable {
    public let records: [ManagedRecord]
    public let nextCursor: String?
    public init(records: [ManagedRecord], nextCursor: String?) {
        self.records = records
        self.nextCursor = nextCursor
    }
}

public struct ManagementViolation: Equatable, Sendable, Identifiable {
    public let path: String
    public let code: String
    public let message: String
    public var id: String { path + ":" + code + ":" + message }
    public init(path: String, code: String, message: String) {
        self.path = path
        self.code = code
        self.message = message
    }
}

public enum ManagementAction: Equatable, Sendable {
    case create(resource: ManagementResource, schemaRevision: String, values: [String: ManagementValue])
    case update(key: ManagedRecordKey, revision: String, schemaRevision: String, changes: [String: ManagementValue])
    case delete(key: ManagedRecordKey, revision: String)
}

public enum ManagementMutation: Equatable, Sendable {
    case record(ManagedRecord)
    case validation([ManagementViolation])
    case deleted
}

public enum ManagementRelation: String, CaseIterable, Sendable {
    case userRoles, userPermissions, rolePermissions
    public var owner: ManagementResource { self == .rolePermissions ? .role : .user }
    public var target: ManagementResource { self == .userRoles ? .role : .permission }
    public var title: String { self == .userRoles ? "Roles" : "Permissions" }
}

public struct ManagementAssignmentKey: Hashable, Sendable {
    public let relation: ManagementRelation
    public let reference: String
    public init(relation: ManagementRelation, reference: String) {
        self.relation = relation
        self.reference = reference
    }
}

public struct ManagementAssignmentSchema: Equatable, Sendable {
    public let relation: ManagementRelation
    public let revision: String
    public let operations: Set<ManagementOperation>
    public init(relation: ManagementRelation, revision: String, operations: Set<ManagementOperation>) {
        self.relation = relation
        self.revision = revision
        self.operations = operations
    }
}

public struct ManagementAssignments: Equatable, Sendable {
    public let key: ManagementAssignmentKey
    public let revision: String
    public let members: [String]
    public init(key: ManagementAssignmentKey, revision: String, members: [String]) {
        self.key = key
        self.revision = revision
        self.members = members
    }
}

public enum ManagementAssignmentMutation: Equatable, Sendable {
    case assignments(ManagementAssignments)
    case validation([ManagementViolation])
}
