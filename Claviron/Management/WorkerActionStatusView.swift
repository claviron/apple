import ClavironControlPlane
import SwiftUI

struct WorkerActionStatusView: View {
    let state: ManagementActionState<WorkerActionContext, WorkerFleetSnapshot>
    let submittedAction: WorkerManagementAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch state {
            case .idle:
                Label("Ready", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            case .submitting:
                progress(Self.progressLabel(for: submittedAction, receipt: nil))
            case let .accepted(context),
                 let .refreshing(context),
                 let .waiting(context, _, _):
                progress(Self.progressLabel(
                    for: context.receipt.action,
                    receipt: context.receipt
                ))
            case let .acknowledged(context),
                 let .completed(context),
                 let .succeeded(context, _):
                Label(
                    Self.successLabel(for: context.receipt),
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            case .rejected, .failed:
                ManagementActionStatusView(state: state) { context in
                    context.receipt.action.title
                }
            }

            if let submissionKey = context?.receipt.submissionKey {
                LabeledContent("Submission", value: submissionKey.submissionKeyFormatted)
            }

            if case let .failed(failure, _) = state {
                Text(failure.diagnosticDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .textSelection(.enabled)
    }

    nonisolated static func progressLabel(
        for action: WorkerManagementAction?,
        receipt: WorkerManagementReceipt?
    ) -> String {
        guard let action else {
            return "Sending worker command…"
        }
        switch action {
        case let .start(workerID):
            return "Starting Worker \(workerID)…"
        case let .stop(workerID):
            return "Stopping Worker \(workerID)…"
        case let .reload(workerID):
            return "Reloading Worker \(workerID)…"
        case let .restart(workerID):
            return "Restarting Worker \(workerID)…"
        case .reloadAll:
            return "Reloading all workers…"
        case .restartAll:
            return "Restarting all workers…"
        case .add:
            return receipt?.targetWorkerCount.map { "Adding Worker \($0)…" }
                ?? "Adding a worker…"
        case .remove:
            return receipt?.previousWorkerCount.map { "Removing Worker \($0)…" }
                ?? "Removing a worker…"
        }
    }

    nonisolated static func successLabel(for receipt: WorkerManagementReceipt) -> String {
        switch receipt.action {
        case let .start(workerID):
            return "Worker \(workerID) started successfully."
        case let .stop(workerID):
            return "Worker \(workerID) stopped successfully."
        case let .reload(workerID):
            return "Worker \(workerID) reloaded successfully."
        case let .restart(workerID):
            return "Worker \(workerID) restarted successfully."
        case .reloadAll:
            return "All workers reloaded successfully."
        case .restartAll:
            return "All workers restarted successfully."
        case .add:
            return receipt.targetWorkerCount.map { "Worker \($0) added successfully." }
                ?? "Worker added successfully."
        case .remove:
            return receipt.previousWorkerCount.map { "Worker \($0) removed successfully." }
                ?? "Worker removed successfully."
        }
    }

    private func progress(_ message: String) -> some View {
        HStack(spacing: 9) {
            ProgressView()
                .controlSize(.small)
            Text(message)
        }
        .foregroundStyle(.orange)
    }

    private var context: WorkerActionContext? {
        switch state {
        case let .accepted(context),
             let .acknowledged(context),
             let .completed(context),
             let .refreshing(context),
             let .waiting(context, _, _),
             let .succeeded(context, _),
             let .rejected(context):
            context
        case let .failed(_, acceptedResponse: context?):
            context
        case .idle, .submitting, .failed(_, acceptedResponse: nil):
            nil
        }
    }
}
