import ClavironControlPlane
import Observation

nonisolated struct ServiceActionContext: Equatable, Sendable {
    let receipt: ServiceManagementReceipt
    let baseline: ServiceFleetSnapshot
}

@MainActor
@Observable
final class ServiceActionModel {
    let serverID: ServerID
    private let connectionModel: ConnectionModel
    private let pipeline = ManagementActionPipeline<ServiceActionContext, ServiceFleetSnapshot>()

    init(serverID: ServerID, connectionModel: ConnectionModel) {
        self.serverID = serverID
        self.connectionModel = connectionModel
    }

    var state: ManagementActionState<ServiceActionContext, ServiceFleetSnapshot> {
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
        _ action: ServiceManagementAction,
        baseline: ServiceFleetSnapshot
    ) async {
        await pipeline.perform(waitPolicy: Self.waitPolicy(for: action)) {
            let receipt = try await connectionModel.performServiceAction(
                action,
                for: serverID
            )
            let context = ServiceActionContext(receipt: receipt, baseline: baseline)
            return receipt.accepted ? .accepted(context) : .rejected(context)
        } refresh: {
            try await connectionModel.refreshServiceForAction(
                named: action.serviceName,
                for: serverID
            )
        } assess: { context, observation in
            Self.assess(context: context, observation: observation)
        }
    }

    private nonisolated static func waitPolicy(
        for action: ServiceManagementAction
    ) -> ManagementActionWaitPolicy {
        switch action {
        case .start, .stop, .reload:
            ManagementActionWaitPolicy(timeout: .seconds(30))
        case .restart:
            ManagementActionWaitPolicy(timeout: .seconds(60))
        }
    }

    func incorporate(_ observation: ServiceFleetSnapshot) {
        pipeline.incorporate(observation: observation) { context, observation in
            Self.assess(context: context, observation: observation)
        }
    }

    nonisolated static func assess(
        context: ServiceActionContext,
        observation: ServiceFleetSnapshot
    ) -> ManagementActionObservationAssessment {
        let receipt = context.receipt
        let name = receipt.action.serviceName
        guard receipt.accepted,
              receipt.acknowledgedServiceName == name,
              context.baseline.coverage == .complete,
              observation.coverage == .complete,
              let baselineService = context.baseline.uniqueService(named: name),
              !baselineService.placements.isEmpty,
              baselineService.hasUniqueKnownMembers,
              let observedService = observation.uniqueService(named: name),
              observedService.hasUniqueKnownMembers else {
            return .notYetObserved
        }

        for before in baselineService.placements {
            guard let member = before.member,
                  let after = observedService.placement(for: member) else {
                return .notYetObserved
            }
            switch after.lifecycle {
            case .unspecified, .unrecognized:
                return .failed(ClavironClientFailure(
                    kind: .protocolMismatch,
                    diagnosticDetail: "Service '\(name)' reported an unknown lifecycle on \(member.role.label):\(member.nodeID)."
                ))
            case .running, .stopping, .stopped, .failed:
                break
            }

            switch receipt.action {
            case .start:
                if after.lifecycle == .failed {
                    return .failed(runtimeFailure(
                        action: "start",
                        serviceName: name,
                        member: member,
                        detail: after.lastError
                    ))
                }
                guard after.lifecycle == .running,
                      before.lifecycle == .running
                        || after.generation > before.generation else {
                    return .notYetObserved
                }
            case .stop:
                guard after.lifecycle == .stopped || after.lifecycle == .failed else {
                    return .notYetObserved
                }
            case .reload:
                guard after.reloadRevision > before.reloadRevision else {
                    return .notYetObserved
                }
                if let error = after.lastReloadError {
                    return .failed(runtimeFailure(
                        action: "reload",
                        serviceName: name,
                        member: member,
                        detail: error
                    ))
                }
            case .restart:
                if after.lifecycle == .failed {
                    return .failed(runtimeFailure(
                        action: "restart",
                        serviceName: name,
                        member: member,
                        detail: after.lastError
                    ))
                }
                guard after.lifecycle != .stopping,
                      after.generation > before.generation else {
                    return .notYetObserved
                }
            }
        }
        return .completed
    }

    nonisolated static func canSubmit(
        action: ServiceManagementAction,
        service: ServiceObservation,
        snapshot: ServiceFleetSnapshot
    ) -> Bool {
        guard action.serviceName == service.name,
              snapshot.coverage == .complete,
              !service.placements.isEmpty,
              service.hasUniqueKnownMembers,
              service.placements.allSatisfy({ placement in
                  switch placement.lifecycle {
                  case .running, .stopped, .failed:
                      true
                  case .unspecified, .stopping, .unrecognized:
                      false
                  }
              }) else {
            return false
        }

        switch action {
        case .reload:
            return service.placements.allSatisfy(\.reloadable)
        case .stop:
            return true
        case .start, .restart:
            return service.placements.allSatisfy {
                $0.startPolicy != .unavailable
                    && $0.startPolicy != .unspecified
                    && !$0.startPolicy.isUnrecognized
            }
        }
    }

    private nonisolated static func runtimeFailure(
        action: String,
        serviceName: String,
        member: ServiceMemberObservation,
        detail: String?
    ) -> ClavironClientFailure {
        let suffix = detail.map { ": \($0)" } ?? ""
        return ClavironClientFailure(
            kind: .operationFailed,
            diagnosticDetail: "Service '\(serviceName)' failed to \(action) on \(member.role.label):\(member.nodeID)\(suffix)"
        )
    }
}

private extension ServiceFleetSnapshot {
    nonisolated func uniqueService(named name: String) -> ServiceObservation? {
        let matches = services.filter { $0.name == name }
        return matches.count == 1 ? matches[0] : nil
    }
}

private extension ServiceObservation {
    nonisolated var hasUniqueKnownMembers: Bool {
        var members: [ServiceMemberObservation] = []
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

    nonisolated func placement(
        for member: ServiceMemberObservation
    ) -> ServicePlacementObservation? {
        placements.first { $0.member == member }
    }
}

private extension ServiceMemberRoleObservation {
    nonisolated var isUnrecognized: Bool {
        if case .unrecognized = self {
            return true
        }
        return false
    }

    nonisolated var label: String {
        switch self {
        case .master:
            "master"
        case .worker:
            "worker"
        case .standalone:
            "standalone"
        case .unspecified:
            "unspecified"
        case let .unrecognized(rawValue):
            "unknown(\(rawValue))"
        }
    }
}

private extension ServiceStartPolicyObservation {
    nonisolated var isUnrecognized: Bool {
        if case .unrecognized = self {
            return true
        }
        return false
    }
}
