import ClavironControlPlane
import SwiftUI
import Testing
@testable import Claviron

struct ManagementActionConfirmationTests {
    @Test
    func routineActionsCanRunWithoutAConfirmation() {
        #expect(!ManagementActionImpact.routine.requiresConfirmation)
        #expect(ManagementActionImpact.routine.confirmationRole == nil)
    }

    @Test
    func serviceWideActionsRequireANonDestructiveConfirmation() {
        #expect(ManagementActionImpact.serviceWide.requiresConfirmation)
        #expect(ManagementActionImpact.serviceWide.confirmationRole == nil)
    }

    @Test
    func disruptiveActionsRequireANonDestructiveConfirmation() {
        #expect(ManagementActionImpact.disruptive.requiresConfirmation)
        #expect(ManagementActionImpact.disruptive.confirmationRole == nil)
    }

    @Test
    func destructiveActionsRequireADestructiveConfirmation() {
        #expect(ManagementActionImpact.destructive.requiresConfirmation)
        #expect(ManagementActionImpact.destructive.confirmationRole == .destructive)
    }

    @Test
    func intentPreservesExactUserFacingScope() {
        let intent = ManagementActionIntent(
            actionTitle: "Restart All Workers",
            confirmationTitle: "Restart all workers?",
            confirmationMessage: "Running workers will be replaced one at a time.",
            impact: .serviceWide
        )

        #expect(intent.actionTitle == "Restart All Workers")
        #expect(intent.confirmationTitle == "Restart all workers?")
        #expect(intent.confirmationMessage == "Running workers will be replaced one at a time.")
        #expect(intent.impact == .serviceWide)
    }

    @Test
    func workerActionIntentsMatchTheirOperationalImpact() {
        #expect(WorkerManagementAction.start(workerID: 2).intent.impact == .routine)
        #expect(WorkerManagementAction.reload(workerID: 2).intent.impact == .routine)
        #expect(WorkerManagementAction.restart(workerID: 2).intent.impact == .disruptive)
        #expect(WorkerManagementAction.stop(workerID: 2).intent.impact == .destructive)
        #expect(WorkerManagementAction.reloadAll.intent.impact == .serviceWide)
        #expect(WorkerManagementAction.restartAll.intent.impact == .serviceWide)
        #expect(WorkerManagementAction.add.intent.impact == .serviceWide)
        #expect(WorkerManagementAction.remove.intent.impact == .destructive)
    }

    @Test
    func serviceActionIntentsReflectTheirFleetScope() {
        #expect(ServiceManagementAction.start(name: "http").intent.impact == .serviceWide)
        #expect(ServiceManagementAction.reload(name: "http").intent.impact == .serviceWide)
        #expect(ServiceManagementAction.restart(name: "http").intent.impact == .serviceWide)
        #expect(ServiceManagementAction.stop(name: "http").intent.impact == .destructive)
    }

    @Test
    func taskActionIntentsReflectExecutionAndFleetImpact() {
        #expect(TaskManagementAction.start(name: "queue").intent.impact == .routine)
        #expect(TaskManagementAction.run(name: "queue").intent.impact == .routine)
        #expect(TaskManagementAction.reload(name: "queue").intent.impact == .serviceWide)
        #expect(TaskManagementAction.restart(name: "queue").intent.impact == .disruptive)
        #expect(TaskManagementAction.stop(name: "queue").intent.impact == .destructive)
    }

    @Test
    func applicationActionIntentsReflectTheirFleetScope() {
        let id = ApplicationIDObservation(runtime: "php", name: "storefront")
        #expect(ApplicationManagementAction.start(id: id).intent.impact == .serviceWide)
        #expect(ApplicationManagementAction.restart(id: id).intent.impact == .disruptive)
        #expect(ApplicationManagementAction.stop(id: id).intent.impact == .destructive)
    }
}
