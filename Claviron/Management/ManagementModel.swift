import ClavironControlPlane
import Foundation
import Observation

struct ManagementSession: Sendable {
    let id: UUID
    let client: any ClavironClient
}

@MainActor
@Observable
final class ManagementModel {
    let resource: ManagementResource
    let serverID: ServerID
    let connection: ConnectionModel
    private(set) var schema: ManagementSchema?
    private(set) var page: ManagementPage?
    private(set) var session: ManagementSession?
    private(set) var failure: String?
    private(set) var isLoading = false
    var search = ""
    var pageSize: UInt32 = 20
    private(set) var currentCursor: String?
    private var previousCursors: [String?] = []
    private var appliedSearch: String?
    private var requestID = UUID()

    init(resource: ManagementResource, serverID: ServerID, connection: ConnectionModel) {
        self.resource = resource
        self.serverID = serverID
        self.connection = connection
    }

    var isCurrent: Bool {
        session?.id != nil && session?.id == connection.managementSessionID(for: serverID)
    }
    var canGoBack: Bool { !previousCursors.isEmpty && !isLoading }
    var canGoForward: Bool { page?.nextCursor != nil && !isLoading }

    func invalidate() {
        requestID = UUID()
        session = nil
        schema = nil
        page = nil
        currentCursor = nil
        previousCursors = []
        failure = nil
        isLoading = false
    }

    func reload() async {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        await load(cursor: nil, previous: [], search: query.isEmpty ? nil : query)
    }

    func refresh() async {
        await load(cursor: currentCursor, previous: previousCursors, search: appliedSearch)
    }

    func next() async {
        guard canGoForward, let cursor = page?.nextCursor else { return }
        await load(cursor: cursor, previous: previousCursors + [currentCursor], search: appliedSearch)
    }

    func back() async {
        guard canGoBack else { return }
        var previous = previousCursors
        let cursor = previous.removeLast()
        await load(cursor: cursor, previous: previous, search: appliedSearch)
    }

    private func load(cursor: String?, previous: [String?], search: String?) async {
        if !isCurrent { invalidate() }
        let ticket = UUID()
        requestID = ticket
        isLoading = true
        failure = nil
        defer { if ticket == requestID { isLoading = false } }
        do {
            let captured = try connection.managementSession(for: serverID)
            let description = try await captured.client.loadManagementSchema(resource)
            try check(captured)
            guard ticket == requestID, !Task.isCancelled else { return }
            let loaded: ManagementPage?
            if description.operations.contains(.list) {
                loaded = try await captured.client.loadManagedRecords(
                    ManagementQuery(resource: resource, pageSize: pageSize, cursor: cursor, search: search)
                )
            } else { loaded = nil }
            try check(captured)
            guard ticket == requestID, !Task.isCancelled else { return }
            session = captured
            schema = description
            page = loaded
            currentCursor = cursor
            previousCursors = previous
            appliedSearch = search
        } catch {
            guard ticket == requestID, !Task.isCancelled else { return }
            failure = error.localizedDescription
        }
    }

    func check(_ captured: ManagementSession) throws {
        guard connection.managementSessionID(for: serverID) == captured.id else {
            throw ManagementClientError("The connection changed. Reload before editing or selecting users.")
        }
    }
}

extension ManagementResource {
    var destination: AppDestination {
        switch self { case .user: .users; case .role: .roles; case .permission: .permissions }
    }
    var systemImage: String {
        switch self { case .user: "person.crop.circle"; case .role: "person.badge.key"; case .permission: "key" }
    }
}
