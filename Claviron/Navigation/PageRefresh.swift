import Observation
import SwiftUI

/// A page supplies its own read operation and optional automatic cadence.
struct PageRefreshAction: Sendable {
    let id: UUID
    let depth: Int
    let interval: Duration?
    let perform: @MainActor @Sendable () async -> Void
}

struct PageRefreshKey: PreferenceKey {
    static let defaultValue: PageRefreshAction? = nil

    static func reduce(value: inout PageRefreshAction?, nextValue: () -> PageRefreshAction?) {
        guard let next = nextValue() else { return }
        if let current = value, current.depth > next.depth { return }
        value = next
    }
}

extension View {
    func pageRefreshable(
        every interval: Duration? = nil,
        enabled: Bool = true,
        action: @escaping @MainActor @Sendable () async -> Void
    ) -> some View {
        modifier(PageRefreshModifier(interval: interval, enabled: enabled, action: action))
    }
}

private struct PageRefreshModifier: ViewModifier {
    let interval: Duration?
    let enabled: Bool
    let action: @MainActor @Sendable () async -> Void
    @State private var id = UUID()
    @State private var visible = false
    @Environment(\.pageRefreshRunner) private var runner
    @Environment(\.pageRefreshSession) private var sessionID
    @Environment(\.isWorkspacePageActive) private var active
    @Environment(\.workspaceNavigationDepth) private var depth

    func body(content: Content) -> some View {
        content
            .refreshable {
                guard active, enabled, let sessionID, let runner else { return }
                await runner.run(PageRefreshAction(id: id, depth: depth, interval: interval, perform: { await action() }), session: sessionID)
            }
            .onAppear { visible = true }
            .onDisappear { visible = false }
            .background {
                // A sibling preference preserves deeper detail-page actions.
                Color.clear.preference(
                    key: PageRefreshKey.self,
                    value: active && visible && enabled
                        ? PageRefreshAction(id: id, depth: depth, interval: interval, perform: { await action() }) : nil
                )
            }
    }
}

struct PageRefreshIdentity: Hashable {
    let action: UUID?
    let session: UUID?
}

@MainActor
@Observable
final class PageRefreshRunner {
    private(set) var running: Set<PageRefreshIdentity> = []

    func run(_ action: PageRefreshAction, session: UUID) async {
        let identity = PageRefreshIdentity(action: action.id, session: session)
        guard !Task.isCancelled, running.insert(identity).inserted else { return }
        defer { running.remove(identity) }
        await action.perform()
    }
}

extension EnvironmentValues {
    @Entry var pageRefreshRunner: PageRefreshRunner? = nil
    @Entry var pageRefreshSession: UUID? = nil
}

struct PageRefreshCommands {
    let canRefresh: Bool
    let canAutomaticallyRefresh: Bool
    let automatic: Binding<Bool>
    let refresh: () -> Void
}

/// One refresh owner per window. Hidden retained pages cannot publish actions.
struct PageRefreshHost<Content: View>: View {
    let action: PageRefreshAction?
    let sessionID: UUID?
    let runner: PageRefreshRunner
    @ViewBuilder let content: (PageRefreshCommands) -> Content
    @Environment(\.scenePhase) private var scenePhase
    @State private var automatic = false
    @State private var tick = 0
    @State private var manualRequest: Task<Void, Never>?

    private struct Schedule: Hashable {
        let identity: PageRefreshIdentity
        let automatic: Bool
        let interval: Duration?
        let foreground: Bool
    }

    private var identity: PageRefreshIdentity {
        PageRefreshIdentity(action: action?.id, session: sessionID)
    }

    var body: some View {
        let available = action != nil && sessionID != nil
        let commands = PageRefreshCommands(
            canRefresh: available && !runner.running.contains(identity),
            canAutomaticallyRefresh: available && action?.interval != nil,
            automatic: $automatic,
            refresh: {
                requestRefresh()
            }
        )
        content(commands)
            .task(id: identity) {
                guard let action, let sessionID else { return }
                await runner.run(action, session: sessionID)
            }
            .task(id: Schedule(identity: identity, automatic: automatic, interval: action?.interval, foreground: scenePhase == .active)) {
                guard automatic, scenePhase == .active, let action, let interval = action.interval, sessionID != nil else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: interval) }
                    catch { return }
                    tick += 1
                }
            }
            .onChange(of: tick) { _, _ in requestRefresh() }
            .onChange(of: identity) { _, _ in
                manualRequest?.cancel()
            }
            .onDisappear { manualRequest?.cancel() }
    }

    private func requestRefresh() {
        guard let action, let sessionID, !runner.running.contains(identity) else { return }
        manualRequest = Task { await runner.run(action, session: sessionID) }
    }
}

#if os(macOS)
private struct PageRefreshCommandsKey: FocusedValueKey {
    typealias Value = PageRefreshCommands
}

extension FocusedValues {
    var clavironPageRefreshCommands: PageRefreshCommands? {
        get { self[PageRefreshCommandsKey.self] }
        set { self[PageRefreshCommandsKey.self] = newValue }
    }
}
#endif
