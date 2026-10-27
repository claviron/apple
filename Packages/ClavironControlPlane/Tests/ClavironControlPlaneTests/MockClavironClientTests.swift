import Foundation
import Testing
@testable import ClavironControlPlane

@Suite("Mock Claviron client")
struct MockClavironClientTests {
    @Test("Results are returned in deterministic order")
    func resultsAreReturnedInOrder() async throws {
        let expected = ServiceFleetSnapshot(
            capturedAt: Date(timeIntervalSince1970: 123),
            membersExpected: 3,
            membersReporting: 2,
            services: []
        )
        let failure = ClavironClientFailure(
            kind: .unavailable,
            diagnosticDetail: "offline"
        )
        let client = MockClavironClient(
            results: [.success(expected), .failure(failure)]
        )

        #expect(try await client.loadServices() == expected)
        await #expect(throws: failure) {
            try await client.loadServices()
        }
        #expect(await client.requestCount == 2)
    }

    @Test("Service actions preserve their typed request and use an independent queue")
    func serviceActionsAreIndependent() async throws {
        let action = ServiceManagementAction.restart(name: "http")
        let receipt = ServiceManagementReceipt(
            action: action,
            accepted: true,
            acknowledgedServiceName: "http"
        )
        let client = MockClavironClient(
            results: [],
            serviceActionResults: [.success(receipt)]
        )

        #expect(try await client.performServiceAction(action) == receipt)
        #expect(await client.serviceActions == [action])
        #expect(await client.requestCount == 0)
        #expect(await client.workerRequestCount == 0)
    }

    @Test("Named service status uses the service result queue")
    func namedServiceStatusIsRecorded() async throws {
        let expected = ServiceFleetSnapshot(
            capturedAt: nil,
            membersExpected: 2,
            membersReporting: 2,
            services: []
        )
        let client = MockClavironClient(results: [.success(expected)])

        #expect(try await client.loadServiceStatus(named: "HttpWatchdogProvider") == expected)
        #expect(await client.serviceStatusNames == ["HttpWatchdogProvider"])
        #expect(await client.requestCount == 1)
    }

    @Test("Disconnect state is observable without network work")
    func disconnectStateIsObservable() async {
        let client = MockClavironClient(results: [])

        await client.disconnect()

        #expect(await client.isDisconnected)
    }

    @Test("Worker results use an independent deterministic queue")
    func workerResultsAreIndependent() async throws {
        let workers = WorkerFleetSnapshot(
            capturedAt: nil,
            workersExpected: 1,
            workers: []
        )
        let client = MockClavironClient(
            results: [],
            workerResults: [.success(workers)]
        )

        #expect(try await client.loadWorkers() == workers)
        #expect(await client.workerRequestCount == 1)
        #expect(await client.requestCount == 0)
    }

    @Test("Worker actions preserve their typed request and use an independent queue")
    func workerActionsAreIndependent() async throws {
        let action = WorkerManagementAction.restart(workerID: 7)
        let receipt = WorkerManagementReceipt(
            action: action,
            accepted: true,
            acknowledgedWorkerID: 7
        )
        let client = MockClavironClient(
            results: [],
            workerActionResults: [.success(receipt)]
        )

        #expect(try await client.performWorkerAction(action) == receipt)
        #expect(await client.workerActions == [action])
        #expect(await client.workerRequestCount == 0)
        #expect(await client.requestCount == 0)
    }

    @Test("Application results use an independent deterministic queue")
    func applicationResultsAreIndependent() async throws {
        let applications = ApplicationFleetSnapshot(
            capturedAt: nil,
            membersExpected: 1,
            membersReporting: 1,
            applications: []
        )
        let client = MockClavironClient(
            results: [],
            applicationResults: [.success(applications)]
        )

        #expect(try await client.loadApplications() == applications)
        #expect(await client.applicationRequestCount == 1)
        #expect(await client.requestCount == 0)
        #expect(await client.workerRequestCount == 0)
    }

    @Test("Application actions preserve their typed request and use an independent queue")
    func applicationActionsAreIndependent() async throws {
        let id = ApplicationIDObservation(runtime: "php", name: "storefront")
        let action = ApplicationManagementAction.restart(id: id)
        let receipt = ApplicationManagementReceipt(
            action: action,
            accepted: true,
            acknowledgedApplicationID: id
        )
        let client = MockClavironClient(
            results: [],
            applicationActionResults: [.success(receipt)]
        )

        #expect(try await client.performApplicationAction(action) == receipt)
        #expect(await client.applicationActions == [action])
        #expect(await client.applicationRequestCount == 0)
        #expect(await client.requestCount == 0)
    }

    @Test("Task results use an independent deterministic queue")
    func taskResultsAreIndependent() async throws {
        let tasks = TaskFleetSnapshot(
            capturedAt: nil,
            membersExpected: 1,
            membersReporting: 1,
            tasks: []
        )
        let client = MockClavironClient(
            results: [],
            taskResults: [.success(tasks)]
        )

        #expect(try await client.loadTasks() == tasks)
        #expect(await client.taskRequestCount == 1)
        #expect(await client.requestCount == 0)
        #expect(await client.workerRequestCount == 0)
        #expect(await client.applicationRequestCount == 0)
    }

    @Test("Task actions preserve their typed request and use an independent queue")
    func taskActionsAreIndependent() async throws {
        let action = TaskManagementAction.restart(name: "queue")
        let receipt = TaskManagementReceipt(
            action: action,
            accepted: true,
            acknowledgedTaskName: "queue"
        )
        let client = MockClavironClient(
            results: [],
            taskActionResults: [.success(receipt)]
        )

        #expect(try await client.performTaskAction(action) == receipt)
        #expect(await client.taskActions == [action])
        #expect(await client.taskRequestCount == 0)
        #expect(await client.requestCount == 0)
    }

    @Test("Task actions preserve the observed run execution timeout")
    func taskActionsPreserveRunExecutionTimeout() async throws {
        let action = TaskManagementAction.run(name: "queue")
        let timeout = ProtobufDurationObservation(seconds: 120, nanoseconds: 0)
        let receipt = TaskManagementReceipt(
            action: action,
            accepted: true,
            acknowledgedTaskName: "queue"
        )
        let client = MockClavironClient(
            results: [],
            taskActionResults: [.success(receipt)]
        )

        _ = try await client.performTaskAction(
            action,
            runExecutionTimeout: timeout
        )

        #expect(await client.taskActionRunExecutionTimeouts == [timeout])
    }

    @Test("Hosting results use an independent deterministic queue")
    func hostingResultsAreIndependent() async throws {
        let hosting = HostingInventorySnapshot(vhosts: [])
        let client = MockClavironClient(
            results: [],
            hostingResults: [.success(hosting)]
        )

        #expect(try await client.loadHosting() == hosting)
        #expect(await client.hostingRequestCount == 1)
        #expect(await client.requestCount == 0)
        #expect(await client.workerRequestCount == 0)
        #expect(await client.applicationRequestCount == 0)
        #expect(await client.taskRequestCount == 0)
    }

    @Test("Certificate results use an independent deterministic queue")
    func certificateResultsAreIndependent() async throws {
        let certificates = CertificateInventorySnapshot(certificates: [])
        let client = MockClavironClient(
            results: [],
            certificateResults: [.success(certificates)]
        )

        #expect(try await client.loadCertificates() == certificates)
        #expect(await client.certificateRequestCount == 1)
        #expect(await client.requestCount == 0)
        #expect(await client.workerRequestCount == 0)
        #expect(await client.applicationRequestCount == 0)
        #expect(await client.taskRequestCount == 0)
        #expect(await client.hostingRequestCount == 0)
    }
}
