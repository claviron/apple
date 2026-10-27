import ClavironControlPlane
import SwiftUI

struct ManagementActionStatusSection<
    Response: Equatable & Sendable,
    Snapshot: Equatable & Sendable
>: View {
    let state: ManagementActionState<Response, Snapshot>
    let sectionTitle: String
    let actionTitle: (Response) -> String

    init(
        state: ManagementActionState<Response, Snapshot>,
        sectionTitle: String = "Last action",
        actionTitle: @escaping (Response) -> String
    ) {
        self.state = state
        self.sectionTitle = sectionTitle
        self.actionTitle = actionTitle
    }

    var body: some View {
        Section(sectionTitle) {
            ManagementActionStatusView(state: state, actionTitle: actionTitle)
        }
    }
}

struct ManagementActionStatusView<
    Response: Equatable & Sendable,
    Snapshot: Equatable & Sendable
>: View {
    let state: ManagementActionState<Response, Snapshot>
    let actionTitle: (Response) -> String

    var body: some View {
        status.copyableMessage(clipboardText)
    }

    /// The sentence the view shows for the current state, for the clipboard.
    private var clipboardText: String {
        switch state {
        case .idle: "Ready"
        case .submitting: "Sending command…"
        case let .accepted(response): "\(actionTitle(response)) is in progress…"
        case let .acknowledged(response): "\(actionTitle(response)) accepted by Claviron."
        case let .completed(response): "\(actionTitle(response)) completed."
        case let .refreshing(response): "\(actionTitle(response)) is in progress; checking runtime state…"
        case let .waiting(response, _, _): "\(actionTitle(response)) is in progress; waiting for runtime state…"
        case let .succeeded(response, _): "\(actionTitle(response)) completed and was observed."
        case let .rejected(response): "Claviron did not accept \(actionTitle(response).lowercased())."
        case let .failed(failure, acceptedResponse):
            failureMessage(failure: failure, acceptedResponse: acceptedResponse)
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch state {
            case .idle:
                Label("Ready", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            case .submitting:
                progress("Sending command…")
            case let .accepted(response):
                progress("\(actionTitle(response)) is in progress…")
            case let .acknowledged(response):
                Label(
                    "\(actionTitle(response)) accepted by Claviron.",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            case let .completed(response):
                Label(
                    "\(actionTitle(response)) completed.",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            case let .refreshing(response):
                progress("\(actionTitle(response)) is in progress; checking runtime state…")
            case let .waiting(response, _, latestFailure):
                if latestFailure == nil {
                    progress("\(actionTitle(response)) is in progress; waiting for runtime state…")
                } else {
                    progress("\(actionTitle(response)) is in progress; the latest state check failed and will be retried.")
                }
            case let .succeeded(response, _):
                Label(
                    "\(actionTitle(response)) completed and was observed.",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            case let .rejected(response):
                Label(
                    "Claviron did not accept \(actionTitle(response).lowercased()).",
                    systemImage: "xmark.circle"
                )
                .foregroundStyle(.red)
            case let .failed(failure, acceptedResponse):
                Label(
                    failureMessage(
                        failure: failure,
                        acceptedResponse: acceptedResponse
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.red)
            }
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

    private func failureMessage(
        failure: ClavironClientFailure,
        acceptedResponse: Response?
    ) -> String {
        guard let acceptedResponse else {
            return failure.localizedDescription
        }
        if failure.kind == .operationFailed {
            return "\(actionTitle(acceptedResponse)) was accepted, but runtime observation showed that it did not complete."
        }
        return "The command was accepted, but its completion could not be checked. \(failure.localizedDescription)"
    }
}
