import ClavironControlPlane
import Foundation
import Testing
@testable import Claviron

struct RuntimeOverviewSummaryTests {
    @Test
    func preservesUnavailableCountsInsteadOfReportingZero() {
        let summary = RuntimeOverviewSummary(
            services: nil,
            workers: nil,
            applications: nil,
            tasks: nil
        )

        #expect(summary.workerCount == nil)
        #expect(summary.workersRunning == nil)
        #expect(summary.workersExpected == nil)
        #expect(summary.controllerPID == nil)
        #expect(summary.serviceCount == nil)
        #expect(summary.applicationCount == nil)
        #expect(summary.taskCount == nil)
    }

    @Test
    func countsRuntimeResources() {
        let tasks = TaskFleetSnapshot(
            capturedAt: .now,
            membersExpected: 1,
            membersReporting: 1,
            tasks: [
                task(named: "daemon", timing: .daemon(enabled: true)),
                task(named: "interval", timing: .interval(every: nil, executionTimeout: nil, enabled: true)),
                task(named: "cron", timing: .cron(expression: "0 * * * *", executionTimeout: nil, enabled: true)),
                task(named: "manual", timing: .manual(executionTimeout: nil)),
                task(named: "unknown", timing: nil),
            ]
        )

        let summary = RuntimeOverviewSummary(
            services: .preview,
            workers: .preview,
            applications: .preview,
            tasks: tasks
        )

        #expect(summary.workerCount == 2)
        #expect(summary.serviceCount == 1)
        #expect(summary.applicationCount == 1)
        #expect(summary.taskCount == 5)
    }

    @Test
    func countsOnlyConnectedLinkedApplicationsOncePerRunner() {
        func summary(_ reachability: LinkReachabilityObservation) -> RuntimeOverviewSummary {
            RuntimeOverviewSummary(
                services: nil,
                workers: nil,
                applications: .preview,
                linkedApplications: LinkedApplicationSnapshot(capturedAt: .now, applications: [
                    LinkedApplicationObservation(
                        id: LinkedApplicationIDObservation(fleetName: "example", name: "demo"),
                        runtime: "asgi", link: reachability, connectedLanes: 4,
                        lanes: [], hosted: nil
                    ),
                ]),
                tasks: nil
            )
        }
        #expect(summary(.connected).applicationCount == 2)
        #expect(summary(.disconnected).applicationCount == 1)
        #expect(summary(.unspecified).applicationCount == 1)
    }

    @Test
    func serverInfoUsesCurrentWorkerFleetAndTypedControllerIdentity() {
        let oldInfo = ServerInfoSnapshot(
            name: "example", environment: "production", hostname: "example.test",
            clavironVersion: "1.0", workersDesired: 2, workersRunning: 2
        )
        func summary(lastLifecycle: WorkerLifecycleObservation = .running) -> RuntimeOverviewSummary {
            RuntimeOverviewSummary(
                services: nil,
                workers: WorkerFleetSnapshot(
                    capturedAt: .now, workersExpected: 16,
                    master: MasterIdentityObservation(
                        process: ProcessIdentityObservation(pid: 1234, startedAt: 42), generation: 1
                    ),
                    workers: (1...16).map { id in
                        WorkerObservation(
                            workerID: UInt32(id), lifecycle: id == 16 ? lastLifecycle : .running,
                            ownership: .spawned, process: nil, uptime: nil,
                            recoveryAttempts: 0, reloadRevision: 0, incarnation: 1
                        )
                    }
                ),
                applications: nil, tasks: nil
            )
        }
        #expect(summary().workerCount == 16)
        #expect(summary().workerStatus(fallback: oldInfo) == "16 / 16")
        #expect(summary().controllerPID == 1234)
        #expect(summary(lastLifecycle: .stopped).workerStatus(fallback: oldInfo) == "15 / 16")
        let missing = RuntimeOverviewSummary(
            services: nil, workers: nil, applications: nil, tasks: nil
        )
        #expect(missing.workerStatus(fallback: oldInfo) == "2 / 2")
        #expect(missing.controllerPID == nil)
    }

    @Test
    func runtimeMetricsContainOnlyRuntimeResources() {
        #expect(RuntimeOverviewMetric.primaryRow == [.workers, .services, .applications, .tasks])
        #expect(RuntimeOverviewMetric.allCases == [.workers, .services, .applications, .tasks])
    }

    private func task(
        named name: String,
        timing: TaskTimingObservation?
    ) -> TaskObservation {
        TaskObservation(
            name: name,
            kind: .builtin,
            scope: .fleet,
            dispatch: .one,
            timing: timing,
            concurrency: 1,
            placements: []
        )
    }
}
