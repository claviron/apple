import ClavironControlPlane
import Foundation
import SwiftUI

struct TaskActionStatusView: View {
    let state: ManagementActionState<TaskActionContext, TaskFleetSnapshot>
    let targetName: String?
    let submittedAction: TaskManagementAction?
    let submittedAt: Date?
    let runExecutionTimeout: ProtobufDurationObservation?

    var body: some View {
        Group {
            if case .idle = state {
                Label("Ready", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else if case .submitting = state,
                      Self.submittingLabel(for: submittedAction) != nil {
                runProgress
            } else if let receipt = terminalRunReceipt,
               let result = receipt.runResult {
                runResult(result)
            } else {
                ManagementActionStatusView(state: state) { context in
                    context.receipt.action.title
                }
            }

            if let targetName {
                LabeledContent(
                    "Task",
                    value: ManagementResourceName.title(
                        targetName,
                        fallback: "Unnamed Task"
                    )
                )
            }

            if let runID = context?.receipt.runID {
                LabeledContent("Run ID", value: "#\(runID)")
            }

            if case let .failed(failure, _) = state {
                Text(failure.diagnosticDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    nonisolated static func submittingLabel(
        for action: TaskManagementAction?,
        elapsedSeconds: Int = 0
    ) -> String? {
        guard let action, case .run = action else {
            return nil
        }
        return elapsedSeconds >= 30
            ? "Still awaiting task result…"
            : "Awaiting task result…"
    }

    nonisolated static func elapsedLabel(seconds: Int) -> String {
        let seconds = max(0, seconds)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    nonisolated static func timeoutLabel(
        _ timeout: ProtobufDurationObservation?
    ) -> String? {
        guard let roundedSeconds = roundedTimeoutSeconds(timeout) else {
            return nil
        }

        let hours = roundedSeconds / 3_600
        let minutes = (roundedSeconds % 3_600) / 60
        let seconds = roundedSeconds % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes > 0 {
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        }
        return "\(seconds)s"
    }

    nonisolated static func remainingSeconds(
        timeout: ProtobufDurationObservation?,
        elapsedSeconds: Int
    ) -> Int? {
        guard let timeoutSeconds = roundedTimeoutSeconds(timeout),
              timeoutSeconds <= Int64(Int.max) else {
            return nil
        }
        return max(0, Int(timeoutSeconds) - max(0, elapsedSeconds))
    }

    private nonisolated static func roundedTimeoutSeconds(
        _ timeout: ProtobufDurationObservation?
    ) -> Int64? {
        guard let timeout,
              timeout.seconds >= 0,
              (0..<1_000_000_000).contains(timeout.nanoseconds),
              timeout.seconds < Int64.max else {
            return nil
        }
        return timeout.seconds + (timeout.nanoseconds > 0 ? 1 : 0)
    }

    private var runProgress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let elapsedSeconds = max(
                0,
                Int(timeline.date.timeIntervalSince(submittedAt ?? timeline.date))
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)

                    Text(Self.submittingLabel(
                        for: submittedAction,
                        elapsedSeconds: elapsedSeconds
                    ) ?? "Awaiting task result…")

                    if elapsedSeconds >= 30,
                       let remainingSeconds = Self.remainingSeconds(
                           timeout: runExecutionTimeout,
                           elapsedSeconds: elapsedSeconds
                       ) {
                        Text("\(Self.elapsedLabel(seconds: remainingSeconds)) remaining")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if let timeout = Self.timeoutLabel(runExecutionTimeout) {
                    Text("Execution timeout: \(timeout)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func runResult(_ result: TaskRunResult) -> some View {
        switch result {
        case .succeeded:
            Label(
                "Run completed successfully.",
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
        case let .failed(failure):
            Label("Run failed.", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
            LabeledContent("Failure", value: failure.kind.title)
            if !failure.message.isEmpty {
                Text(failure.message)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private var terminalRunReceipt: TaskManagementReceipt? {
        guard case let .completed(context) = state,
              case .run = context.receipt.action else {
            return nil
        }
        return context.receipt
    }

    private var context: TaskActionContext? {
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

private extension TaskRunFailureKind {
    var title: String {
        switch self {
        case .unspecified: "Unspecified"
        case .io: "I/O"
        case .cancelled: "Cancelled"
        case .shutdown: "Shutdown"
        case .gracefulTimeout: "Graceful timeout"
        case .executionTimeout: "Execution timeout"
        case .task: "Task"
        case let .unrecognized(rawValue): "Unknown (\(rawValue))"
        }
    }
}
