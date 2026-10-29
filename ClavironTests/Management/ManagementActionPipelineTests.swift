import ClavironControlPlane
import Testing
@testable import Claviron

@MainActor
struct ManagementActionPipelineTests {
    private let response = TestActionResponse(revision: 4)
    private let observation = TestActionObservation(revision: 4)
    private let immediatePolicy = ManagementActionWaitPolicy(
        timeout: .seconds(1),
        pollInterval: .zero
    )

    @Test
    func successRequiresAnAcceptedResponseAndObservedCompletion() async {
        let pipeline = ManagementActionPipeline<TestActionResponse, TestActionObservation>()

        await pipeline.perform(waitPolicy: immediatePolicy) {
            .accepted(response)
        } refresh: {
            observation
        } assess: { response, observation in
            response.revision == observation.revision ? .completed : .notYetObserved
        }

        #expect(pipeline.state == .succeeded(
            response: response,
            observation: observation
        ))
    }

    @Test
    func acceptedCommandRemainsDistinctWhenCompletionIsNotYetObserved() async {
        let pipeline = ManagementActionPipeline<TestActionResponse, TestActionObservation>()
        let earlierObservation = TestActionObservation(revision: 3)

        let action = Task { @MainActor in
            await pipeline.perform(
                waitPolicy: ManagementActionWaitPolicy(
                    timeout: .seconds(1),
                    pollInterval: .milliseconds(10)
                )
            ) {
                .accepted(response)
            } refresh: {
                earlierObservation
            } assess: { response, observation in
                response.revision == observation.revision ? .completed : .notYetObserved
            }
        }

        while true {
            if case .waiting = pipeline.state {
                break
            }
            await Task.yield()
        }

        #expect(pipeline.state == .waiting(
            response: response,
            latestObservation: earlierObservation,
            latestFailure: nil
        ))

        pipeline.incorporate(observation: observation) { response, observation in
            response.revision == observation.revision ? .completed : .notYetObserved
        }
        await action.value

        #expect(pipeline.state == .succeeded(
            response: response,
            observation: observation
        ))
    }

    @Test
    func transientObservationFailureIsRetriedUntilCompletionIsObserved() async {
        let failure = ClavironClientFailure(
            kind: .unavailable,
            diagnosticDetail: "refresh transport unavailable"
        )
        let pipeline = ManagementActionPipeline<TestActionResponse, TestActionObservation>()

        var refreshCount = 0
        await pipeline.perform(
            waitPolicy: ManagementActionWaitPolicy(
                timeout: .seconds(1),
                pollInterval: .zero
            )
        ) {
            .accepted(response)
        } refresh: {
            refreshCount += 1
            if refreshCount == 1 {
                throw failure
            }
            return observation
        } assess: { _, _ in
            .completed
        }

        #expect(pipeline.state == .succeeded(
            response: response,
            observation: observation
        ))
        #expect(refreshCount == 2)
    }

    @Test
    func rejectedResponseDoesNotFabricateARefreshOrSuccess() async {
        let pipeline = ManagementActionPipeline<TestActionResponse, TestActionObservation>()
        var refreshCount = 0

        await pipeline.perform(waitPolicy: immediatePolicy) {
            .rejected(response)
        } refresh: {
            refreshCount += 1
            return observation
        } assess: { _, _ in
            .completed
        }

        #expect(pipeline.state == .rejected(response))
        #expect(refreshCount == 0)
    }

    @Test
    func failureRetainsWhetherTheCommandWasAlreadyAccepted() async {
        let failure = ClavironClientFailure(
            kind: .unavailable,
            diagnosticDetail: "refresh transport unavailable"
        )
        let beforeAcceptance = ManagementActionPipeline<
            TestActionResponse,
            TestActionObservation
        >()

        await beforeAcceptance.perform(waitPolicy: immediatePolicy) {
            throw failure
        } refresh: {
            observation
        } assess: { _, _ in
            .completed
        }
        #expect(beforeAcceptance.state == .failed(
            failure,
            acceptedResponse: nil
        ))

        let afterAcceptance = ManagementActionPipeline<
            TestActionResponse,
            TestActionObservation
        >()
        await afterAcceptance.perform(
            waitPolicy: ManagementActionWaitPolicy(
                timeout: .milliseconds(5),
                pollInterval: .milliseconds(1)
            )
        ) {
            .accepted(response)
        } refresh: {
            throw failure
        } assess: { _, _ in
            .completed
        }
        guard case let .failed(timeoutFailure, acceptedResponse) = afterAcceptance.state else {
            Issue.record("accepted command did not finish with an explicit client timeout")
            return
        }
        #expect(timeoutFailure.kind == .timedOut)
        #expect(timeoutFailure.diagnosticDetail.contains(failure.diagnosticDetail))
        #expect(acceptedResponse == response)
    }

    @Test
    func observedTerminalFailureRetainsTheAcceptedResponse() async {
        let failure = ClavironClientFailure(
            kind: .operationFailed,
            diagnosticDetail: "runtime did not converge"
        )
        let pipeline = ManagementActionPipeline<TestActionResponse, TestActionObservation>()

        await pipeline.perform(waitPolicy: immediatePolicy) {
            .accepted(response)
        } refresh: {
            observation
        } assess: { _, _ in
            .failed(failure)
        }

        #expect(pipeline.state == .failed(failure, acceptedResponse: response))
        pipeline.incorporate(observation: observation) { _, _ in .notYetObserved }
        #expect(pipeline.state == .failed(failure, acceptedResponse: response))
    }

    @Test
    func passiveRefreshDoesNotRestartAnExpiredWaitButCanProveLateCompletion() async {
        let pipeline = ManagementActionPipeline<TestActionResponse, TestActionObservation>()
        var refreshCount = 0
        await pipeline.perform(
            waitPolicy: ManagementActionWaitPolicy(timeout: .zero, pollInterval: .zero)
        ) {
            .accepted(response)
        } refresh: {
            refreshCount += 1
            return observation
        } assess: { _, _ in
            .notYetObserved
        }
        let expired = pipeline.state
        guard case let .failed(failure, acceptedResponse) = expired else {
            Issue.record("zero-budget wait did not expire")
            return
        }
        #expect(failure.kind == .timedOut)
        #expect(acceptedResponse == response)
        #expect(refreshCount == 0)
        pipeline.incorporate(observation: TestActionObservation(revision: 3)) { _, _ in
            .notYetObserved
        }
        #expect(pipeline.state == expired)
        pipeline.incorporate(observation: observation) { _, _ in .completed }
        #expect(pipeline.state == .succeeded(response: response, observation: observation))
    }

    @Test
    func resetInvalidatesAnInFlightAction() async {
        let refreshGate = ActionRefreshGate()
        let pipeline = ManagementActionPipeline<TestActionResponse, TestActionObservation>()
        let action = Task { @MainActor in
            await pipeline.perform(waitPolicy: immediatePolicy) {
                .accepted(response)
            } refresh: {
                await refreshGate.wait()
            } assess: { _, _ in
                .completed
            }
        }

        while !(await refreshGate.isWaiting) {
            await Task.yield()
        }
        #expect(pipeline.state == .refreshing(response))

        pipeline.reset()
        await refreshGate.resume(returning: observation)
        await action.value

        #expect(pipeline.state == .idle)
    }
}

private struct TestActionResponse: Equatable, Sendable {
    let revision: UInt64
}

private struct TestActionObservation: Equatable, Sendable {
    let revision: UInt64
}

private actor ActionRefreshGate {
    private var continuation: CheckedContinuation<TestActionObservation, Never>?
    private(set) var isWaiting = false

    func wait() async -> TestActionObservation {
        isWaiting = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(returning observation: TestActionObservation) {
        continuation?.resume(returning: observation)
        continuation = nil
    }
}
