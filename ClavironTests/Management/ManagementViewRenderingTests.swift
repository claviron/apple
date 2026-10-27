import ClavironControlPlane
import SwiftUI
import Testing
@testable import Claviron

@MainActor
struct ManagementViewRenderingTests {
    @Test
    func initialConfigurationWizardStepsRender() {
        let applicationModel = ApplicationModel.preview()
        let input = InitialConfigurationInput(
            serverName: "Production",
            serverAddress: "https://control.example.com:7443",
            tlsProfileName: "Operator"
        )
        let credentials = TLSCredentialImport(
            certificateAuthority: ImportedCredential(
                fileName: "ca.pem",
                data: Data("ca".utf8)
            ),
            clientCertificate: ImportedCredential(
                fileName: "client.pem",
                data: Data("certificate".utf8)
            ),
            clientPrivateKey: ImportedCredential(
                fileName: "client-key.pem",
                data: Data("private key".utf8)
            )
        )

        let sizes: [(name: String, width: CGFloat, height: CGFloat)] = [
            ("Wide", 800, 700),
            ("Compact", 390, 844),
        ]

        for step in InitialConfigurationStep.allCases {
            for size in sizes {
                let view = InitialConfigurationView(
                    applicationModel: applicationModel,
                    initialStep: step,
                    input: input,
                    credentials: credentials
                )
                let renderer = ImageRenderer(
                    content: view.frame(width: size.width, height: size.height)
                )
                renderer.scale = 1
                #expect(
                    renderer.cgImage != nil,
                    "\(step.title) setup step did not render at \(size.name) size"
                )
            }
        }
    }

    @Test
    func applicationShellRendersAtWideAndCompactSizes() {
        let applicationModel = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let connectionModel = ConnectionModel(applicationModel: applicationModel) { _ in
            MockClavironClient(results: [.success(.preview)])
        }
        let shell = ContentView(
            applicationModel: applicationModel,
            connectionModel: connectionModel
        )
        let sizes: [(name: String, width: CGFloat, height: CGFloat)] = [
            ("Wide", 1_200, 800),
            ("Compact", 390, 844),
        ]

        for size in sizes {
            let renderer = ImageRenderer(
                content: shell.frame(width: size.width, height: size.height)
            )
            renderer.scale = 1
            #expect(renderer.cgImage != nil, "\(size.name) shell did not render")
        }
    }

    @Test
    func loadedManagementViewsRender() async throws {
        let applicationModel = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let client = MockClavironClient(
            results: [.success(.preview)],
            workerResults: [.success(.preview)],
            applicationResults: [.success(.preview)],
            taskResults: [.success(.preview)],
            hostingResults: [.success(.preview)],
            certificateResults: [.success(.preview)]
        )
        let connectionModel = ConnectionModel(applicationModel: applicationModel) { _ in client }
        let serverID = TestConfiguration.primaryServerID

        await connectionModel.connect(to: serverID)
        await connectionModel.loadWorkers(for: serverID)
        await connectionModel.loadApplications(for: serverID)
        await connectionModel.loadTasks(for: serverID)
        await connectionModel.loadHosting(for: serverID)
        await connectionModel.loadCertificates(for: serverID)

        let server = try #require(applicationModel.activeServer)
        let views: [(name: String, view: AnyView)] = [
            ("Overview", AnyView(OverviewView(
                server: server,
                tlsProfile: applicationModel.configuration.tlsProfiles.first { $0.id == server.tlsProfileID },
                connectionModel: connectionModel
            ))),
            ("Workers", AnyView(WorkersView(serverID: serverID, connectionModel: connectionModel))),
            ("Services", AnyView(ServicesView(serverID: serverID, connectionModel: connectionModel))),
            ("Applications", AnyView(ApplicationsView(serverID: serverID, connectionModel: connectionModel))),
            ("Tasks", AnyView(TasksView(serverID: serverID, connectionModel: connectionModel))),
            ("Hosting", AnyView(HostingView(serverID: serverID, connectionModel: connectionModel))),
            ("Certificates", AnyView(CertificatesView(serverID: serverID, connectionModel: connectionModel))),
        ]

        for item in views {
            let renderer = ImageRenderer(
                content: item.view.frame(width: 900, height: 700)
            )
            renderer.scale = 1
            #expect(renderer.cgImage != nil, "\(item.name) did not produce a rendered image")
        }
    }

    @Test
    func runtimeResourceDetailViewsRender() async throws {
        let applicationModel = ApplicationModel.preview(configuration: TestConfiguration.valid)
        let client = MockClavironClient(
            results: [.success(.preview)],
            workerResults: [.success(.preview)],
            applicationResults: [.success(.preview)],
            taskResults: [.success(.preview)]
        )
        let connectionModel = ConnectionModel(applicationModel: applicationModel) { _ in client }
        let serverID = TestConfiguration.primaryServerID

        await connectionModel.connect(to: serverID)
        await connectionModel.loadWorkers(for: serverID)
        await connectionModel.loadApplications(for: serverID)
        await connectionModel.loadTasks(for: serverID)

        let worker = try #require(
            connectionModel.workerObservationState(for: serverID).snapshot?.workers.first
        )
        let service = try #require(
            connectionModel.serviceObservationState(for: serverID).snapshot?.services.first
        )
        let application = try #require(
            connectionModel.applicationObservationState(for: serverID).snapshot?.applications.first
        )
        let applicationID = try #require(application.applicationID)
        let task = try #require(
            connectionModel.taskObservationState(for: serverID).snapshot?.tasks.first
        )
        let views: [(name: String, view: AnyView)] = [
            (
                "Worker detail",
                AnyView(
                    WorkersView(
                        serverID: serverID,
                        connectionModel: connectionModel,
                        initialWorkerID: worker.workerID
                    )
                )
            ),
            (
                "Service detail",
                AnyView(
                    ServicesView(
                        serverID: serverID,
                        connectionModel: connectionModel,
                        initialServiceName: service.name
                    )
                )
            ),
            (
                "Application detail",
                AnyView(
                    ApplicationsView(
                        serverID: serverID,
                        connectionModel: connectionModel,
                        initialApplicationID: applicationID
                    )
                )
            ),
            (
                "Task detail",
                AnyView(
                    TasksView(
                        serverID: serverID,
                        connectionModel: connectionModel,
                        initialTaskName: task.name
                    )
                )
            ),
        ]

        for item in views {
            let renderer = ImageRenderer(
                content: item.view.frame(width: 900, height: 700)
            )
            renderer.scale = 1
            #expect(renderer.cgImage != nil, "\(item.name) did not produce a rendered image")
        }
    }
}
