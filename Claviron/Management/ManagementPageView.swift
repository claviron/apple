import ClavironControlPlane
import SwiftUI

struct ManagementPageView: View {
    let serverID: ServerID
    let connection: ConnectionModel
    let resource: ManagementResource
    @State private var model: ManagementModel
    @State private var creating = false
    @NavigationDetailPath(.users) private var navigationPath: [ManagedRecordKey] = []
    @Environment(\.isWorkspacePageActive) private var isActive

    init(serverID: ServerID, connection: ConnectionModel, resource: ManagementResource) {
        self.serverID = serverID
        self.connection = connection
        self.resource = resource
        _model = State(initialValue: ManagementModel(resource: resource, serverID: serverID, connection: connection))
        _navigationPath = NavigationDetailPath(wrappedValue: [], resource.destination)
    }

    private var supported: Bool {
        connection.serverInfo(for: serverID)?.capabilities.contains(resource.capability) == true
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if supported {
                    ManagedRecordsList(model: model, allowsSelection: model.schema?.operations.contains(.read) == true) { record in
                        if navigationPath.last != record.key { navigationPath.append(record.key) }
                    }
                } else {
                    ContentUnavailableView("\(resource.title) Unavailable", systemImage: resource.systemImage,
                                           description: Text("The connected server has not reported this management capability."))
                }
            }
            .workspaceNavigationTitle(resource.title)
            .toolbar {
                if isActive, model.schema?.operations.contains(.create) == true, model.schema?.create != nil {
                    Button("Create \(resource.singular)", systemImage: "plus") { creating = true }
                        .disabled(!model.isCurrent || model.isLoading)
                }
            }
            .sheet(isPresented: $creating) {
                if let schema = model.schema, let session = model.session {
                    ManagementFormView(schema: schema, record: nil, session: session, serverID: serverID, connection: connection) { _ in
                        await model.reload()
                    }
                }
            }
            .managementDestination(for: ManagedRecordKey.self) { key in
                ManagedRecordView(key: key, serverID: serverID, connection: connection) {
                    await model.refresh()
                }
            }
        }
        .pageRefreshable(every: .seconds(2), enabled: supported) {
            if !model.isCurrent || model.schema == nil { await model.reload() }
            else { await model.refresh() }
        }
        .onChange(of: supported) { _, supported in
            if !supported { model.invalidate() }
        }
        .onChange(of: connection.managementSessionID(for: serverID)) { _, session in
            if session == nil { model.invalidate() }
        }
    }
}

/// Search runs on the server; pagination follows its opaque cursors.
struct ManagedRecordsList: View {
    @Bindable var model: ManagementModel
    var allowsSelection = true
    var showsSearch = true
    let select: (ManagedRecord) -> Void
    @State private var searchRequest: Task<Void, Never>?

    var body: some View {
        List {
            if showsSearch {
                Section {
                    HStack {
                        TextField("Search \(model.resource.title.lowercased())", text: $model.search)
                            .autocorrectionDisabled()
                            .onSubmit { search() }
                        Button("Search", systemImage: "magnifyingglass") { search() }
                            .buttonStyle(.borderless)
                            .disabled(model.isLoading)
                    }
                }
            }
            if let failure = model.failure {
                Section { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            }
            if model.isLoading { ProgressView("Loading…") }
            if model.isCurrent, let page = model.page {
                if page.records.isEmpty {
                    ContentUnavailableView("No Results", systemImage: "magnifyingglass")
                } else {
                    ForEach(page.records) { record in
                        Button { select(record) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: model.resource.systemImage).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.title).fontWeight(.medium)
                                    if record.subtitle != record.title {
                                        Text(record.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 6)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(!allowsSelection || !model.isCurrent || model.isLoading)
                    }
                }
                Section {
                    HStack {
                        Button("Previous") { Task { await model.back() } }.disabled(!model.canGoBack)
                        Spacer()
                        Text("\(page.records.count) on this page").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Next") { Task { await model.next() } }.disabled(!model.canGoForward)
                    }
                }
            } else if let schema = model.schema, !schema.operations.contains(.list) {
                Text("Listing is not available for this identity.").foregroundStyle(.secondary)
            }
        }
        .onChange(of: model.search) { if showsSearch { search() } }
        .onDisappear { searchRequest?.cancel() }
    }

    private func search() {
        searchRequest?.cancel()
        searchRequest = Task { await model.reload() }
    }
}
