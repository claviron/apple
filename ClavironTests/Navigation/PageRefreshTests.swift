import Foundation
import Testing
@testable import Claviron

@MainActor
struct PageRefreshTests {
    @Test
    func detailActionTakesPrecedenceOverParentInEitherOrder() {
        let parent = PageRefreshAction(id: UUID(), depth: 0, interval: nil, perform: {})
        let detail = PageRefreshAction(id: UUID(), depth: 1, interval: .seconds(2), perform: {})
        var selected: PageRefreshAction?
        PageRefreshKey.reduce(value: &selected) { parent }
        PageRefreshKey.reduce(value: &selected) { detail }
        PageRefreshKey.reduce(value: &selected) { nil }
        PageRefreshKey.reduce(value: &selected) { parent }
        #expect(selected?.id == detail.id)
    }

    @Test
    func overlappingRequestsShareOneRefreshAndCompletionReleasesIt() async {
        let runner = PageRefreshRunner()
        let gate = RefreshGate()
        let action = PageRefreshAction(id: UUID(), depth: 0, interval: nil) {
            await gate.perform()
        }
        let session = UUID()
        let first = Task { await runner.run(action, session: session) }
        await gate.waitUntilEntered()
        await runner.run(action, session: session)
        #expect(gate.calls == 1)
        #expect(runner.running.count == 1)
        gate.release()
        await first.value
        #expect(runner.running.isEmpty)
        await runner.run(action, session: session)
        #expect(gate.calls == 2)
    }

    @Test
    func replacementConnectionDoesNotInheritAnOldRefreshLock() async {
        let runner = PageRefreshRunner()
        let gate = RefreshGate()
        let id = UUID()
        let first = Task {
            await runner.run(PageRefreshAction(id: id, depth: 0, interval: nil) { await gate.perform() }, session: UUID())
        }
        await gate.waitUntilEntered()
        var calls = 0
        await runner.run(PageRefreshAction(id: id, depth: 0, interval: nil) { calls += 1 }, session: UUID())
        #expect(calls == 1)
        gate.release()
        await first.value
        #expect(runner.running.isEmpty)
    }
}

@MainActor
private final class RefreshGate {
    var calls = 0
    private var entered: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<Void, Never>?
    private var released = false

    func perform() async {
        calls += 1
        entered?.resume()
        entered = nil
        if !released {
            await withCheckedContinuation { pending = $0 }
        }
    }

    func waitUntilEntered() async {
        if calls == 0 { await withCheckedContinuation { entered = $0 } }
    }

    func release() {
        released = true
        pending?.resume()
        pending = nil
    }
}
