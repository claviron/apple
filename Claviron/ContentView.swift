//
//  ContentView.swift
//  Claviron
//
//  Created by Developer on 12.09.2026.
//

import ClavironControlPlane
import SwiftUI

struct ContentView: View {
    @Bindable var applicationModel: ApplicationModel
    @State private var connectionModel: ConnectionModel
    @State private var pageRefreshRunner = PageRefreshRunner()
#if os(macOS)
    @State private var navigationHistory = NavigationHistory()
    @State private var workspaceTitle = "Overview"
    @AppStorage(SidebarDensity.storageKey) private var storedDensity = SidebarDensity.expanded.rawValue
#else
    @State private var selectedDestination: AppDestination? = .overview
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
#endif

    init(
        applicationModel: ApplicationModel,
        connectionModel: ConnectionModel? = nil
    ) {
        self.applicationModel = applicationModel
        _connectionModel = State(
            initialValue: connectionModel ?? ConnectionModel(
                applicationModel: applicationModel
            )
        )
    }

    var body: some View {
        navigation
        .environment(\.pageRefreshRunner, pageRefreshRunner)
        .environment(\.pageRefreshSession, activeManagementSessionID)
        .toolbar {
#if os(macOS)
            // Bare: they sit beside the window controls, where a capsule
            // behind them would read as one more group of those.
            ToolbarItem(placement: .navigation) {
                NavigationToolbarControls(
                    history: navigationHistory,
                    hasWorkspaceNavigation: hasWorkspaceNavigation
                )
            }
            .sharedBackgroundVisibility(.hidden)
#endif
#if !os(macOS)
            ToolbarItem(placement: .secondaryAction) {
                ProfileMenu(selection: destinationSelection, userManagementAvailable: userManagementAvailable)
            }
#endif
        }
        .backgroundPreferenceValue(PageRefreshKey.self) { action in
            PageRefreshHost(
                action: action,
                sessionID: activeManagementSessionID,
                runner: pageRefreshRunner
            ) { refresh in
                Color.clear.frame(width: 0, height: 0)
                    .toolbar {
                        ToolbarItemGroup(placement: .primaryAction) {
                            ActiveServerPicker(applicationModel: applicationModel)
                            if let serverID = applicationModel.configuration.activeServerID {
                                ConnectionStatusControl(
                                    serverID: serverID,
                                    connectionModel: connectionModel,
                                    pageRefresh: refresh
                                )
                            }
                        }
                    }
#if os(macOS)
                    .focusedSceneValue(\.clavironPageRefreshCommands, refresh)
#endif
            }
        }
        .task(id: activeConnectionIdentity) {
            guard let serverID = applicationModel.configuration.activeServerID else {
                return
            }
            await connectionModel.connect(to: serverID)
        }
#if os(macOS)
        .environment(\.navigationHistory, navigationHistory)
        .onPreferenceChange(WorkspaceNavigationTitleKey.self) { title in
            workspaceTitle = title?.title ?? navigationHistory.current.destination.title
        }
        .navigationTitle(workspaceTitle)
        .onChange(of: applicationModel.configuration.activeServerID) { _, _ in
            navigationHistory.reset()
        }
        .focusedSceneValue(\.clavironConnectionCommands, connectionCommandActions)
#endif
    }

    /// macOS keeps an outer icon rail and a separately collapsible navigation
    /// pane inside the workspace. iOS retains its adaptive system split view.
    @ViewBuilder
    private var navigation: some View {
#if os(macOS)
        HStack(spacing: 0) {
            SidebarView(selection: destinationSelection, userManagementAvailable: userManagementAvailable)
                .zIndex(1)
            WorkspaceView(
                density: SidebarDensity.resolve(storedDensity),
                hasNavigation: hasWorkspaceNavigation
            ) {
                WorkspaceNavigationView(selection: destinationSelection, userManagementAvailable: userManagementAvailable)
            } detail: {
                WorkspacePages(
                    destinations: navigationHistory.visitedDestinations,
                    selection: navigationHistory.current.destination
                ) { destination in
                    destinationView(for: destination)
                }
                .id(applicationModel.configuration.activeServerID)
            }
        }
        .background(.background.secondary)
#else
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            SidebarView(selection: destinationSelection, userManagementAvailable: userManagementAvailable)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
#endif
    }

#if os(macOS)
    private var hasWorkspaceNavigation: Bool {
        (currentDestination ?? .overview) != .overview
    }
#endif

    private var destinationSelection: Binding<AppDestination?> {
        Binding(
            get: { currentDestination },
            set: { destination in
#if os(macOS)
                if let destination {
                    navigationHistory.visit(NavigationLocation(destination: destination))
                }
#else
                selectedDestination = destination
                // Menu destinations do not have a sidebar NavigationLink.
                if destination != nil { preferredCompactColumn = .detail }
#endif
            }
        )
    }

    private var currentDestination: AppDestination? {
#if os(macOS)
        navigationHistory.current.destination
#else
        selectedDestination
#endif
    }

    private var userManagementAvailable: Bool {
        guard let serverID = applicationModel.configuration.activeServerID else { return false }
        return connectionModel.serverInfo(for: serverID)?.capabilities.contains("users") == true
    }

    private var activeManagementSessionID: UUID? {
        applicationModel.configuration.activeServerID.flatMap {
            connectionModel.managementSessionID(for: $0)
        }
    }

    private var activeConnectionIdentity: ActiveConnectionIdentity? {
        guard
            let server = applicationModel.activeServer,
            let profile = applicationModel.configuration.tlsProfiles.first(
                where: { $0.id == server.tlsProfileID }
            )
        else {
            return nil
        }

        return ActiveConnectionIdentity(
            serverID: server.id,
            address: server.address,
            tlsProfileID: profile.id,
            caCertificatePath: profile.caCertificatePath,
            clientCertificatePath: profile.clientCertificatePath,
            clientPrivateKeyPath: profile.clientPrivateKeyPath
        )
    }

#if os(macOS)
    private var connectionCommandActions: ClavironConnectionCommandActions? {
        guard let serverID = applicationModel.configuration.activeServerID else {
            return nil
        }
        return ClavironConnectionCommandActions(
            availability: ConnectionCommandAvailability(
                state: connectionModel.state(for: serverID)
            ),
            connect: {
                Task {
                    await connectionModel.connect(to: serverID)
                }
            },
            reconnect: {
                Task {
                    await connectionModel.reconnect(serverID)
                }
            },
            disconnect: {
                Task {
                    await connectionModel.disconnect(serverID)
                }
            }
        )
    }
#endif

    private var detailView: some View {
        destinationView(for: currentDestination ?? .overview)
    }

    @ViewBuilder
    private func destinationView(for destination: AppDestination) -> some View {
        if destination == .overview, let server = applicationModel.activeServer {
            OverviewView(
                server: server,
                tlsProfile: applicationModel.configuration.tlsProfiles.first { $0.id == server.tlsProfileID },
                connectionModel: connectionModel
            )
        } else if destination == .runtimeOverview, let server = applicationModel.activeServer {
            RuntimeOverviewView(server: server, connectionModel: connectionModel)
        } else if destination == .edgeOverview,
                  let serverID = applicationModel.configuration.activeServerID {
            EdgeOverviewView(serverID: serverID, connectionModel: connectionModel)
        } else if destination == .usersOverview || destination == .authorizationOverview,
                  let serverID = applicationModel.configuration.activeServerID {
            AccountOverviewView(
                group: destination.group,
                serverID: serverID,
                connectionModel: connectionModel
            )
        } else if destination == .users || destination == .roles || destination == .permissions,
                  let serverID = applicationModel.configuration.activeServerID {
            ManagementPageView(
                serverID: serverID,
                connection: connectionModel,
                resource: destination == .users ? .user : destination == .roles ? .role : .permission
            )
        } else if destination == .workers,
                  let serverID = applicationModel.configuration.activeServerID {
            WorkersView(
                serverID: serverID,
                connectionModel: connectionModel
            )
        } else if destination == .services,
                  let serverID = applicationModel.configuration.activeServerID {
            ServicesView(
                serverID: serverID,
                connectionModel: connectionModel
            )
        } else if destination == .applications,
                  let serverID = applicationModel.configuration.activeServerID {
            ApplicationsView(
                serverID: serverID,
                connectionModel: connectionModel
            )
        } else if destination == .tasks,
                  let serverID = applicationModel.configuration.activeServerID {
            TasksView(
                serverID: serverID,
                connectionModel: connectionModel
            )
        } else if destination == .hosting,
                  let serverID = applicationModel.configuration.activeServerID {
            HostingView(
                serverID: serverID,
                connectionModel: connectionModel
            )
        } else if destination == .dns,
                  let serverID = applicationModel.configuration.activeServerID {
            DnsView(
                serverID: serverID,
                connectionModel: connectionModel
            )
        } else if destination == .domains,
                  let serverID = applicationModel.configuration.activeServerID {
            DomainsView(
                serverID: serverID,
                connectionModel: connectionModel
            )
        } else if destination == .certificates,
                  let serverID = applicationModel.configuration.activeServerID {
            CertificatesView(
                serverID: serverID,
                connectionModel: connectionModel
            )
        } else if destination == .profile {
            if userManagementAvailable {
                ProfileView()
            } else {
                ContentUnavailableView(
                    "User Management Unavailable",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("This server does not report user management support.")
                )
            }
        } else if destination == .settings {
            ConfigurationView(applicationModel: applicationModel)
        } else {
            DestinationPlaceholderView(destination: destination)
        }
    }
}

private struct ActiveConnectionIdentity: Hashable {
    let serverID: ServerID
    let address: String
    let tlsProfileID: TLSProfileID
    let caCertificatePath: String
    let clientCertificatePath: String
    let clientPrivateKeyPath: String
}

#Preview("Wide") {
    ClavironPreviewRoot()
        .frame(width: 1_200, height: 800)
}

#Preview("Compact") {
    ClavironPreviewRoot()
        .frame(width: 390, height: 844)
}

private struct ClavironPreviewRoot: View {
    var body: some View {
        let applicationModel = ApplicationModel.preview(configuration: .preview)
        let connectionModel = ConnectionModel(applicationModel: applicationModel) { _ in
            MockClavironClient(
                results: [.success(.preview)],
                workerResults: [.success(.preview)],
                applicationResults: [.success(.preview)],
                taskResults: [.success(.preview)],
                hostingResults: [.success(.preview)],
                certificateResults: [.success(.preview)],
                dnsZoneResults: [.success(.preview)],
                dnsRecordResults: [.success(.preview)]
            )
        }
        ContentView(
            applicationModel: applicationModel,
            connectionModel: connectionModel
        )
    }
}

extension ServiceFleetSnapshot {
    static let preview = ServiceFleetSnapshot(
        capturedAt: .now,
        membersExpected: 2,
        membersReporting: 2,
        services: [
            ServiceObservation(
                name: "HttpsServer",
                placements: [
                    ServicePlacementObservation(
                        member: ServiceMemberObservation(nodeID: 1, role: .master),
                        lifecycle: .running,
                        reloadable: true,
                        generation: 4,
                        reloadRevision: 2,
                        lastError: nil,
                        lastErrorTruncated: false,
                        lastReloadError: nil,
                        lastReloadErrorTruncated: false,
                        observedAt: .now,
                        startPolicy: .automatic
                    ),
                ]
            ),
        ]
    )
}

extension WorkerFleetSnapshot {
    static let preview = WorkerFleetSnapshot(
        capturedAt: .now,
        workersExpected: 2,
        master: MasterIdentityObservation(
            process: ProcessIdentityObservation(pid: 4_300, startedAt: 0x1a2b00),
            generation: 7
        ),
        fleetMode: .running,
        build: BuildIdentityObservation(revision: "0e0d369e", dirty: false),
        workers: [
            WorkerObservation(
                workerID: 1,
                lifecycle: .running,
                ownership: .spawned,
                process: ProcessIdentityObservation(pid: 4_321, startedAt: 0x1a2b3c),
                uptime: ProtobufDurationObservation(seconds: 3_661, nanoseconds: 0),
                recoveryAttempts: 0,
                reloadRevision: 2,
                incarnation: 1,
                phase: .running,
                phaseAge: ProtobufDurationObservation(seconds: 3_650, nanoseconds: 0),
                desired: .ensureRunning,
                desiredAge: ProtobufDurationObservation(seconds: 3_661, nanoseconds: 0),
                heartbeatAge: ProtobufDurationObservation(seconds: 0, nanoseconds: 700_000_000)
            ),
            WorkerObservation(
                workerID: 2,
                lifecycle: .running,
                ownership: .adopted,
                process: ProcessIdentityObservation(pid: 4_322, startedAt: 0x1a2a10),
                uptime: ProtobufDurationObservation(seconds: 7_240, nanoseconds: 0),
                recoveryAttempts: 1,
                reloadRevision: 3,
                incarnation: 2,
                phase: .running,
                phaseAge: ProtobufDurationObservation(seconds: 3_600, nanoseconds: 0),
                desired: .ensureRunning,
                desiredAge: ProtobufDurationObservation(seconds: 3_600, nanoseconds: 0),
                heartbeatAge: ProtobufDurationObservation(seconds: 0, nanoseconds: 400_000_000)
            ),
        ]
    )
}

extension ApplicationFleetSnapshot {
    static let preview = ApplicationFleetSnapshot(
        capturedAt: .now,
        membersExpected: 2,
        membersReporting: 2,
        applications: [
            ApplicationObservation(
                applicationID: ApplicationIDObservation(
                    runtime: "php",
                    name: "storefront"
                ),
                placements: [
                    ApplicationPlacementObservation(
                        member: ApplicationMemberObservation(nodeID: 1, role: .worker),
                        lifecycle: .running,
                        enabled: true,
                        generation: 4,
                        pool: ApplicationPoolObservation(
                            accepting: true,
                            instances: 8,
                            ready: 6,
                            busy: 2,
                            retiring: 0,
                            backingOff: 0,
                            exhausted: 0
                        ),
                        lastError: nil,
                        lastErrorTruncated: false,
                        observedAt: .now
                    ),
                ]
            ),
        ]
    )
}

extension TaskFleetSnapshot {
    static let preview = TaskFleetSnapshot(
        capturedAt: .now,
        membersExpected: 2,
        membersReporting: 2,
        tasks: [
            TaskObservation(
                name: "wallet-reconciliation",
                kind: .builtin,
                scope: .workers,
                dispatch: .one,
                timing: .interval(
                    every: ProtobufDurationObservation(seconds: 60, nanoseconds: 0),
                    executionTimeout: ProtobufDurationObservation(seconds: 30, nanoseconds: 0),
                    enabled: true
                ),
                concurrency: 1,
                placements: [
                    TaskPlacementObservation(
                        member: TaskMemberObservation(nodeID: 1, role: .worker),
                        lifecycle: .active,
                        inFlight: 1,
                        lastExecution: TaskExecutionOutcomeObservation(
                            result: .succeeded,
                            finishedAt: .now
                        ),
                        observedAt: .now,
                        generation: 2
                    ),
                ]
            ),
        ]
    )
}

extension HostingInventorySnapshot {
    static let preview = HostingInventorySnapshot(
        vhosts: [
            HostedVhostObservation(
                vhost: VhostObservation(id: 1, name: "example.net", enabled: true),
                aliases: [
                    VhostAliasObservation(id: 2, hostname: "example.com", enabled: nil),
                    VhostAliasObservation(id: 3, hostname: "example.test", enabled: nil),
                ],
                servers: [
                    HostingServerObservation(id: 1, name: "edge", enabled: true),
                ]
            ),
        ]
    )
}

extension DnsInventorySnapshot {
    static let preview = DnsInventorySnapshot(
        zones: [
            DnsZoneObservation(
                id: 1,
                configuration: DnsZoneConfiguration(
                    domain: "example.com",
                    soa: DnsSOAConfiguration(
                        mname: "ns1.example.com",
                        rname: "hostmaster.example.com",
                        refresh: 7_200,
                        retry: 3_600,
                        expire: 1_209_600,
                        minimum: 300
                    ),
                    enabled: true
                ),
                serial: 2_026_100_301
            ),
            DnsZoneObservation(
                id: 2,
                configuration: DnsZoneConfiguration(
                    domain: "example.test",
                    soa: nil,
                    enabled: false
                ),
                serial: 1
            ),
        ]
    )
}

extension DnsRecordsSnapshot {
    static let preview = DnsRecordsSnapshot(
        zone: "example.com",
        records: [
            DnsRecordObservation(
                id: 1,
                zone: "example.com",
                configuration: DnsRecordConfiguration(
                    name: "@", type: "A", value: "192.0.2.10", ttl: 300,
                    priority: nil, weight: nil, port: nil, enabled: true
                )
            ),
            DnsRecordObservation(
                id: 2,
                zone: "example.com",
                configuration: DnsRecordConfiguration(
                    name: "@", type: "MX", value: "mail.example.com", ttl: 3_600,
                    priority: 10, weight: nil, port: nil, enabled: true
                )
            ),
            DnsRecordObservation(
                id: 3,
                zone: "example.com",
                configuration: DnsRecordConfiguration(
                    name: "_sip._tcp", type: "SRV", value: "sip.example.com", ttl: 300,
                    priority: 10, weight: 0, port: 5_060, enabled: false
                )
            ),
        ]
    )
}

extension CertificateInventorySnapshot {
    static let preview = CertificateInventorySnapshot(
        certificates: [
            HostedCertificateObservation(
                certificate: CertificateObservation(
                    id: 1,
                    commonName: "example.com",
                    aliases: ["example.com", "www.example.com"],
                    issuedAt: ProtobufTimestampObservation(seconds: 1_788_249_600, nanoseconds: 0),
                    expiresAt: ProtobufTimestampObservation(seconds: 1_796_025_600, nanoseconds: 0),
                    updatedAt: nil,
                    enabled: true
                ),
                servers: [
                    CertificateServerObservation(id: 1, name: "edge", enabled: true),
                ]
            ),
        ]
    )
}
