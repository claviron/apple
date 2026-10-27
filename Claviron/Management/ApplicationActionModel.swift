import ClavironControlPlane
import Observation

nonisolated struct ApplicationActionContext: Equatable, Sendable {
    let receipt: ApplicationManagementReceipt
    let baseline: ApplicationFleetSnapshot
}

@MainActor
@Observable
final class ApplicationActionModel {
    let serverID: ServerID
    private let connectionModel: ConnectionModel
    private let pipeline = ManagementActionPipeline<ApplicationActionContext, ApplicationFleetSnapshot>()

    init(serverID: ServerID, connectionModel: ConnectionModel) {
        self.serverID = serverID
        self.connectionModel = connectionModel
    }

    var state: ManagementActionState<ApplicationActionContext, ApplicationFleetSnapshot> {
        pipeline.state
    }

    var isBusy: Bool {
        switch state {
        case .submitting, .accepted, .refreshing, .waiting:
            true
        case .idle, .acknowledged, .completed, .succeeded, .rejected, .failed:
            false
        }
    }

    func perform(
        _ action: ApplicationManagementAction,
        baseline: ApplicationFleetSnapshot
    ) async {
        await pipeline.perform(waitPolicy: Self.waitPolicy(for: action)) {
            let receipt = try await connectionModel.performApplicationAction(
                action,
                for: serverID
            )
            let context = ApplicationActionContext(receipt: receipt, baseline: baseline)
            return receipt.accepted ? .accepted(context) : .rejected(context)
        } refresh: {
            try await connectionModel.refreshApplicationsForAction(for: serverID)
        } assess: { context, observation in
            Self.assess(context: context, observation: observation)
        }
    }

    func incorporate(_ observation: ApplicationFleetSnapshot) {
        pipeline.incorporate(observation: observation) { context, observation in
            Self.assess(context: context, observation: observation)
        }
    }

    nonisolated static func canSubmit(
        action: ApplicationManagementAction,
        application: ApplicationObservation,
        snapshot: ApplicationFleetSnapshot
    ) -> Bool {
        guard let id = application.applicationID,
              id == action.applicationID,
              snapshot.coverage == .complete,
              snapshot.applications.filter({ $0.applicationID == id }).count == 1,
              application.placements.count == Int(snapshot.membersReporting),
              application.hasUniqueKnownMembers else {
            return false
        }

        switch action {
        case .start:
            return application.placements.contains {
                !$0.enabled || $0.lifecycle != .running
            }
        case .stop:
            return application.placements.contains {
                $0.enabled || $0.lifecycle == .running || $0.lifecycle == .starting
            }
        case .restart:
            return !application.placements.isEmpty
        }
    }

    nonisolated static func assess(
        context: ApplicationActionContext,
        observation: ApplicationFleetSnapshot
    ) -> ManagementActionObservationAssessment {
        let receipt = context.receipt
        let id = receipt.action.applicationID
        guard receipt.accepted,
              receipt.acknowledgedApplicationID == id,
              context.baseline.coverage == .complete,
              observation.coverage == .complete,
              let before = context.baseline.uniqueApplication(id: id),
              let after = observation.uniqueApplication(id: id),
              before.placements.count == Int(context.baseline.membersReporting),
              after.placements.count == Int(observation.membersReporting),
              before.hasUniqueKnownMembers,
              after.hasUniqueKnownMembers else {
            return .notYetObserved
        }

        for baselinePlacement in before.placements {
            guard let member = baselinePlacement.member,
                  let current = after.placements.first(where: { $0.member == member }) else {
                return .notYetObserved
            }

            switch receipt.action {
            case .start:
                if current.lifecycle == .failed {
                    return .failed(failure(
                        id: id,
                        operation: "start",
                        placement: current
                    ))
                }
                let wasAlreadyRunning = baselinePlacement.lifecycle == .running
                    && baselinePlacement.enabled
                guard current.lifecycle == .running,
                      current.enabled,
                      wasAlreadyRunning || current.generation > baselinePlacement.generation else {
                    return .notYetObserved
                }
            case .stop:
                guard !current.enabled,
                      current.lifecycle == .stopped || current.lifecycle == .failed else {
                    return .notYetObserved
                }
            case .restart:
                if current.lifecycle == .failed {
                    return .failed(failure(
                        id: id,
                        operation: "restart",
                        placement: current
                    ))
                }
                guard current.lifecycle == .running,
                      current.enabled,
                      current.generation > baselinePlacement.generation else {
                    return .notYetObserved
                }
            }
        }
        return .completed
    }

    private nonisolated static func waitPolicy(
        for action: ApplicationManagementAction
    ) -> ManagementActionWaitPolicy {
        switch action {
        case .start, .stop:
            ManagementActionWaitPolicy(timeout: .seconds(30))
        case .restart:
            ManagementActionWaitPolicy(timeout: .seconds(60))
        }
    }

    private nonisolated static func failure(
        id: ApplicationIDObservation,
        operation: String,
        placement: ApplicationPlacementObservation
    ) -> ClavironClientFailure {
        let detail = placement.lastError ?? "No runtime error was reported."
        return ClavironClientFailure(
            kind: .operationFailed,
            diagnosticDetail: "Application '\(id.runtime):\(id.name)' failed to \(operation). \(detail)"
        )
    }
}

private extension ApplicationFleetSnapshot {
    nonisolated func uniqueApplication(
        id: ApplicationIDObservation
    ) -> ApplicationObservation? {
        let matches = applications.filter { $0.applicationID == id }
        return matches.count == 1 ? matches[0] : nil
    }
}

private extension ApplicationObservation {
    nonisolated var hasUniqueKnownMembers: Bool {
        var members: [ApplicationMemberObservation] = []
        for placement in placements {
            guard let member = placement.member,
                  member.role != .unspecified,
                  !member.role.isUnrecognized,
                  !members.contains(member) else {
                return false
            }
            members.append(member)
        }
        return true
    }
}

private extension ApplicationMemberRoleObservation {
    nonisolated var isUnrecognized: Bool {
        if case .unrecognized = self {
            return true
        }
        return false
    }
}
