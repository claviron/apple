import ClavironControlPlane
import Foundation
import Observation

nonisolated enum ManagementActionSubmissionDisposition: Equatable, Sendable {
    case accepted
    case acknowledged
    case completed
    case rejected
}

nonisolated struct ManagementActionSubmission<Response: Equatable & Sendable>: Equatable, Sendable {
    let disposition: ManagementActionSubmissionDisposition
    let response: Response

    static func accepted(_ response: Response) -> Self {
        Self(disposition: .accepted, response: response)
    }

    static func acknowledged(_ response: Response) -> Self {
        Self(disposition: .acknowledged, response: response)
    }

    static func completed(_ response: Response) -> Self {
        Self(disposition: .completed, response: response)
    }

    static func rejected(_ response: Response) -> Self {
        Self(disposition: .rejected, response: response)
    }
}

nonisolated enum ManagementActionObservationAssessment: Equatable, Sendable {
    case completed
    case notYetObserved
    case failed(ClavironClientFailure)
}

nonisolated struct ManagementActionWaitPolicy: Equatable, Sendable {
    let timeout: Duration
    let pollInterval: Duration

    init(timeout: Duration, pollInterval: Duration = .seconds(1)) {
        self.timeout = timeout
        self.pollInterval = pollInterval
    }
}

nonisolated enum ManagementActionState<
    Response: Equatable & Sendable,
    Snapshot: Equatable & Sendable
>: Equatable, Sendable {
    case idle
    case submitting
    case accepted(Response)
    case acknowledged(Response)
    case completed(Response)
    case refreshing(Response)
    case waiting(
        response: Response,
        latestObservation: Snapshot?,
        latestFailure: ClavironClientFailure?
    )
    case succeeded(response: Response, observation: Snapshot)
    case rejected(Response)
    case failed(ClavironClientFailure, acceptedResponse: Response?)
}

@MainActor
@Observable
final class ManagementActionPipeline<
    Response: Equatable & Sendable,
    Snapshot: Equatable & Sendable
> {
    private(set) var state: ManagementActionState<Response, Snapshot> = .idle
    @ObservationIgnored private var operationID = UUID()

    func perform(
        waitPolicy: ManagementActionWaitPolicy,
        submit: @MainActor () async throws -> ManagementActionSubmission<Response>,
        refresh: @MainActor () async throws -> Snapshot,
        assess: @MainActor (Response, Snapshot) -> ManagementActionObservationAssessment
    ) async {
        let currentOperationID = UUID()
        operationID = currentOperationID
        state = .submitting

        let submission: ManagementActionSubmission<Response>
        do {
            submission = try await submit()
        } catch {
            guard operationID == currentOperationID else {
                return
            }
            state = .failed(Self.failure(from: error), acceptedResponse: nil)
            return
        }

        guard operationID == currentOperationID else {
            return
        }
        switch submission.disposition {
        case .rejected:
            state = .rejected(submission.response)
            return
        case .acknowledged:
            state = .acknowledged(submission.response)
            return
        case .completed:
            state = .completed(submission.response)
            return
        case .accepted:
            break
        }

        state = .accepted(submission.response)
        await Task.yield()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: waitPolicy.timeout)
        var latestObservation: Snapshot?
        var latestFailure: ClavironClientFailure?

        while operationID == currentOperationID {
            guard !Task.isCancelled else {
                state = .failed(
                    Self.cancelledFailure(),
                    acceptedResponse: submission.response
                )
                return
            }
            guard clock.now < deadline else {
                state = .failed(
                    Self.timeoutFailure(latestFailure: latestFailure),
                    acceptedResponse: submission.response
                )
                return
            }

            state = .refreshing(submission.response)
            do {
                let observation = try await refresh()
                guard operationID == currentOperationID else {
                    return
                }
                latestObservation = observation
                latestFailure = nil

                guard clock.now < deadline else {
                    state = .failed(
                        Self.timeoutFailure(latestFailure: nil),
                        acceptedResponse: submission.response
                    )
                    return
                }

                switch assess(submission.response, observation) {
                case .completed:
                    state = .succeeded(
                        response: submission.response,
                        observation: observation
                    )
                    return
                case .notYetObserved:
                    state = .waiting(
                        response: submission.response,
                        latestObservation: observation,
                        latestFailure: nil
                    )
                case let .failed(failure):
                    state = .failed(
                        failure,
                        acceptedResponse: submission.response
                    )
                    return
                }
            } catch {
                guard operationID == currentOperationID else {
                    return
                }
                guard !Task.isCancelled else {
                    state = .failed(
                        Self.cancelledFailure(),
                        acceptedResponse: submission.response
                    )
                    return
                }
                latestFailure = Self.failure(from: error)
                state = .waiting(
                    response: submission.response,
                    latestObservation: latestObservation,
                    latestFailure: latestFailure
                )
            }

            let remaining = clock.now.duration(to: deadline)
            guard remaining > .zero else {
                state = .failed(
                    Self.timeoutFailure(latestFailure: latestFailure),
                    acceptedResponse: submission.response
                )
                return
            }

            do {
                try await clock.sleep(for: min(waitPolicy.pollInterval, remaining))
            } catch {
                guard operationID == currentOperationID else {
                    return
                }
                state = .failed(
                    Self.cancelledFailure(),
                    acceptedResponse: submission.response
                )
                return
            }
        }
    }

    func reset() {
        operationID = UUID()
        state = .idle
    }

    func incorporate(
        observation: Snapshot,
        assess: @MainActor (Response, Snapshot) -> ManagementActionObservationAssessment
    ) {
        let response: Response
        switch state {
        case let .waiting(currentResponse, _, _):
            response = currentResponse
        case let .failed(_, acceptedResponse: .some(currentResponse)):
            response = currentResponse
        case .idle, .submitting, .accepted, .acknowledged, .completed,
             .refreshing, .succeeded, .rejected,
             .failed(_, acceptedResponse: nil):
            return
        }

        switch assess(response, observation) {
        case .completed:
            state = .succeeded(response: response, observation: observation)
            operationID = UUID()
        case .notYetObserved:
            state = .waiting(
                response: response,
                latestObservation: observation,
                latestFailure: nil
            )
        case let .failed(failure):
            state = .failed(failure, acceptedResponse: response)
            operationID = UUID()
        }
    }

    private static func timeoutFailure(
        latestFailure: ClavironClientFailure?
    ) -> ClavironClientFailure {
        let suffix = latestFailure.map {
            " The latest observation request failed: \($0.diagnosticDetail)"
        } ?? " The latest authoritative observation remains visible in the resource view."
        return ClavironClientFailure(
            kind: .timedOut,
            diagnosticDetail: "The command was accepted, but its required runtime state was not observed before the client deadline.\(suffix)"
        )
    }

    private static func cancelledFailure() -> ClavironClientFailure {
        ClavironClientFailure(
            kind: .cancelled,
            diagnosticDetail: "Waiting for the accepted command was cancelled."
        )
    }

    private static func failure(from error: any Error) -> ClavironClientFailure {
        if let failure = error as? ClavironClientFailure {
            return failure
        }
        if error is CancellationError {
            return ClavironClientFailure(
                kind: .cancelled,
                diagnosticDetail: String(describing: error)
            )
        }
        return ClavironClientFailure(
            kind: .unknown,
            diagnosticDetail: String(describing: error)
        )
    }
}

/// Retains independent action state for each resource while its detail view is
/// not visible. The values themselves remain the observable state owners.
@MainActor
final class ManagementResourceActionStore<Key: Hashable, Value: AnyObject> {
    private var valuesByKey: [Key: Value] = [:]
    private let makeValue: @MainActor () -> Value

    init(makeValue: @escaping @MainActor () -> Value) {
        self.makeValue = makeValue
    }

    func value(for key: Key) -> Value {
        if let value = valuesByKey[key] {
            return value
        }
        let value = makeValue()
        valuesByKey[key] = value
        return value
    }

    var values: [Value] {
        Array(valuesByKey.values)
    }
}
