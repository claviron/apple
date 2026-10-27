import ClavironControlPlane
import SwiftUI
import Testing
@testable import Claviron

@MainActor
struct ManagementResourceStatusTests {
    private enum State: Equatable {
        case running
        case stopped
        case failed
    }

    @Test
    func emptyUniformMixedAndDegradedAggregatesRemainDistinct() {
        #expect(status([]).title == "Unknown")
        #expect(status([.running, .running]).title == "Running")
        #expect(status([.running, .stopped]).title == "Mixed")
        #expect(status([.running, .failed]).title == "Degraded")
    }

    @Test
    func scheduledTasksRemainActiveWhenNonTargetsAreIneligible() {
        let task = task(
            timing: .interval(every: nil, executionTimeout: nil, enabled: true),
            placements: [
                placement(nodeID: 0, lifecycle: .ineligible),
                placement(nodeID: 1, lifecycle: .active, ownedSlots: 1),
            ]
        )

        #expect(TaskPresentationStatus.summary(for: task).title == "Armed")
        #expect(
            TaskPresentationStatus.placement(
                task.placements[1],
                timing: task.timing,
                dispatch: task.dispatch
            ).title == "Armed"
        )
    }

    @Test
    func manualAndScheduledExecutionsAreRunningRegardlessOfScheduleState() {
        for timing in [
            TaskTimingObservation.manual(executionTimeout: nil),
            .interval(every: nil, executionTimeout: nil, enabled: true),
            .cron(expression: "0 * * * *", executionTimeout: nil, enabled: false),
        ] {
            let executing = task(timing: timing, placements: [
                placement(nodeID: 1, lifecycle: .disabled, inFlight: 1),
            ])
            #expect(TaskPresentationStatus.summary(for: executing).title == "Running")
            #expect(TaskPresentationStatus.placement(
                executing.placements[0], timing: timing, dispatch: executing.dispatch
            ).title == "Running")
        }
    }

    @Test
    func lastCompletedResultDoesNotHideAnActiveExecution() {
        let executing = task(timing: .manual(executionTimeout: nil), placements: [
            TaskPlacementObservation(
                member: TaskMemberObservation(nodeID: 1, role: .worker), lifecycle: .active,
                inFlight: 1, lastExecution: TaskExecutionOutcomeObservation(
                    result: .succeeded, finishedAt: Date(timeIntervalSince1970: 100)
                ), observedAt: Date(timeIntervalSince1970: 200), generation: 1
            ),
        ])
        #expect(TaskPresentationStatus.summary(for: executing).title == "Running")
        #expect(TaskPresentationStatus.detail(for: executing).contains("1 instance"))
        #expect(TaskPresentationStatus.instanceSummary(for: executing) == " · 1 instance")
        #expect(TaskPresentationStatus.detail(for: executing).contains("Last: Succeeded"))
    }

    @Test
    func daemonStatusShowsWhereInstancesAreActuallyRunning() {
        let task = task(
            timing: .daemon(enabled: true),
            placements: [
                placement(nodeID: 0, lifecycle: .ineligible),
                placement(nodeID: 1, lifecycle: .active, inFlight: 2),
                placement(nodeID: 2, lifecycle: .active),
            ]
        )

        #expect(TaskPresentationStatus.summary(for: task).title == "Running")
        #expect(TaskPresentationStatus.runningInstanceCount(for: task) == 2)
        #expect(
            TaskPresentationStatus.placement(
                task.placements[1],
                timing: task.timing,
                dispatch: task.dispatch
            ).title == "Running"
        )
        #expect(
            TaskPresentationStatus.placement(
                task.placements[2],
                timing: task.timing,
                dispatch: task.dispatch
            ).title == "Waiting"
        )
    }

    @Test
    func runningInstanceCountSumsTheFleetObservationInsteadOfConcurrency() {
        let task = TaskObservation(
            name: "pooled-daemon",
            kind: .php,
            scope: .workers,
            dispatch: .pool,
            timing: .daemon(enabled: true),
            concurrency: 6,
            placements: [
                placement(nodeID: 1, lifecycle: .active, inFlight: 2),
                placement(nodeID: 2, lifecycle: .active, inFlight: 1),
            ]
        )

        #expect(TaskPresentationStatus.runningInstanceCount(for: task) == 3)
        #expect(TaskPresentationStatus.instanceSummary(for: task) == " · 3 instances")
    }

    @Test
    func daemonWithoutAnyRunningInstancesIsNotPresentedAsActive() {
        let pool = task(
            timing: .daemon(enabled: true),
            placements: [placement(nodeID: 1, lifecycle: .active)]
        )
        let each = TaskObservation(
            name: "local-daemon",
            kind: .command,
            scope: .workers,
            dispatch: .each,
            timing: .daemon(enabled: true),
            concurrency: 1,
            placements: [placement(nodeID: 1, lifecycle: .active)]
        )

        #expect(TaskPresentationStatus.summary(for: pool).title == "Waiting")
        #expect(TaskPresentationStatus.summary(for: each).title == "Not running")
        #expect(TaskPresentationStatus.instanceSummary(for: pool) == "")
    }

    @Test
    func taskKindsUseDistinctIcons() {
        #expect(TaskKindObservation.builtin.assetImage == "TaskIconRust")
        #expect(TaskKindObservation.php.assetImage == "TaskIconPHP")
        #expect(TaskKindObservation.js.assetImage == "TaskIconJavaScript")
        #expect(TaskKindObservation.lua.assetImage == "TaskIconLua")
        #expect(TaskKindObservation.command.systemImage == "terminal")
        #expect(TaskKindObservation.command.assetImage == nil)
        #expect(!TaskKindObservation.builtin.assetIsTemplate)
    }

    @Test
    func applicationRuntimesReuseTaskBrandIcons() {
        let php = ApplicationRuntimePresentation("php")
        let javascript = ApplicationRuntimePresentation("js")
        let lua = ApplicationRuntimePresentation(" Lua ")
        let rust = ApplicationRuntimePresentation("builtin")
        let python = ApplicationRuntimePresentation("python")
        let asgi = ApplicationRuntimePresentation(" ASGI ")
        let custom = ApplicationRuntimePresentation("custom")

        #expect(php.title == "PHP")
        #expect(php.assetImage == "TaskIconPHP")
        #expect(javascript.title == "JavaScript")
        #expect(javascript.assetImage == "TaskIconJavaScript")
        #expect(lua.title == "Lua")
        #expect(lua.assetImage == "TaskIconLua")
        #expect(rust.title == "Rust")
        #expect(rust.assetImage == "TaskIconRust")
        #expect(python.title == "Python")
        #expect(python.assetImage == "TaskIconPython")
        #expect(asgi.title == "Python")
        #expect(asgi.assetImage == "TaskIconPython")
        #expect(custom.title == "custom")
        #expect(custom.assetImage == nil)
        #expect(custom.systemImage == "app.fill")

        // A symbolic code chooses presentation only, never the reported runtime.
        let branded = ApplicationIconPresentation("fastapi", runtime: "python")
        #expect(branded.assetImage == "FrameworkIconFastAPI")
        #expect(branded.title == "Python")
        let generic = ApplicationIconPresentation("server", runtime: "php")
        #expect(generic.assetImage == nil)
        #expect(generic.systemImage == "server.rack")
        #expect(ApplicationIconPresentation("unknown", runtime: "php").assetImage == "TaskIconPHP")
        #expect(ApplicationIconPresentation(nil, runtime: "python").assetImage == "TaskIconPython")
    }

    @Test
    func servicesUseTheRustRuntimeIcon() {
        #expect(ServicePresentation.assetImage == "TaskIconRust")
    }

    @Test
    func resourceCodesArePresentedAsReadableTitles() {
        #expect(ManagementResourceName.title("send_mails", fallback: "Missing") == "Send Mails")
        #expect(ManagementResourceName.title("job-bridge", fallback: "Missing") == "Job Bridge")
        #expect(ManagementResourceName.title("", fallback: "Missing") == "Missing")
    }

    @Test
    func taskTimingGroupsSeparateScheduledDaemonAndManualWork() {
        #expect(TaskTimingGroup.allCases == [.scheduled, .daemon, .manual, .unspecified])
        #expect(TaskTimingGroup.tabs(for: []) == [.scheduled, .daemon, .manual])
        #expect(
            TaskTimingGroup.tabs(for: [], preserving: .unspecified)
                == [.scheduled, .daemon, .manual, .unspecified]
        )
        #expect(TaskTimingGroup.manual.emptyTitle == "No Manual Tasks")
        #expect(TaskTimingGroup.scheduled.contains(.interval(
            every: nil,
            executionTimeout: nil,
            enabled: true
        )))
        #expect(TaskTimingGroup.scheduled.contains(.cron(
            expression: "0 * * * *",
            executionTimeout: nil,
            enabled: true
        )))
        #expect(TaskTimingGroup.daemon.contains(.daemon(enabled: true)))
        #expect(TaskTimingGroup.manual.contains(.manual(executionTimeout: nil)))
        #expect(TaskTimingGroup.unspecified.contains(nil))
    }

    private func status(_ states: [State]) -> ManagementResourceStatus {
        ManagementResourceStatus.aggregate(
            states,
            display: { state in
                switch state {
                case .running:
                    ManagementResourceStatus(title: "Running", color: .green)
                case .stopped:
                    ManagementResourceStatus(title: "Stopped", color: .secondary)
                case .failed:
                    ManagementResourceStatus(title: "Failed", color: .red)
                }
            },
            isFailure: { $0 == .failed }
        )
    }

    private func task(
        timing: TaskTimingObservation,
        placements: [TaskPlacementObservation]
    ) -> TaskObservation {
        TaskObservation(
            name: "sample",
            kind: .builtin,
            scope: .workers,
            dispatch: .pool,
            timing: timing,
            concurrency: 2,
            placements: placements
        )
    }

    private func placement(
        nodeID: UInt32,
        lifecycle: TaskLifecycleObservation,
        inFlight: UInt64 = 0,
        ownedSlots: UInt64 = 0
    ) -> TaskPlacementObservation {
        TaskPlacementObservation(
            member: TaskMemberObservation(
                nodeID: nodeID,
                role: nodeID == 0 ? .master : .worker
            ),
            lifecycle: lifecycle,
            inFlight: inFlight,
            lastExecution: nil,
            observedAt: nil,
            generation: 1,
            ownedSlots: ownedSlots
        )
    }
}
