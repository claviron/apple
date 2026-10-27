#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Claviron

enum WorkspacePageLayout: CaseIterable {
    case list
    case cards
}

@MainActor
struct WorkspacePagesTests {
    @Test(arguments: WorkspacePageLayout.allCases)
    func groupSwitchesRetainFiltersSelectionsAndNativeScrollOffsets(layout: WorkspacePageLayout) throws {
        let tasks = PageObservation()
        let domains = PageObservation()
        let chrome = ChromeObservation()
        let server = UUID()

        func pages(_ visited: [AppDestination], selection: AppDestination, server: UUID) -> some View {
            WorkspacePages(destinations: visited, selection: selection) { destination in
                StatefulListPage(
                    destination: destination,
                    observation: destination == .tasks ? tasks : domains,
                    layout: layout
                )
            }
            .id(server)
            .onPreferenceChange(WorkspaceNavigationTitleKey.self) { chrome.title = $0?.title }
            .transaction { $0.disablesAnimations = true }
        }

        let host = NSHostingView(rootView: pages([.tasks], selection: .tasks, server: server))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        host.layoutSubtreeIfNeeded()
        let identity = try #require(tasks.identity)
        #expect(domains.identity == nil, "Unvisited pages must not be constructed")
        let configureTasks = try #require(tasks.configure)
        configureTasks(true, 80)
        host.layoutSubtreeIfNeeded()
        let taskScroll = try #require(scrollViews(in: host).first)
        taskScroll.contentView.scroll(to: NSPoint(x: 0, y: 320))
        taskScroll.reflectScrolledClipView(taskScroll.contentView)
        let taskOffset = taskScroll.contentView.bounds.origin
        #expect(taskOffset.y > 0)

        host.rootView = pages([.tasks, .domains], selection: .domains, server: server)
        host.layoutSubtreeIfNeeded()
        #expect(tasks.isActive == false)
        #expect(tasks.isEnabled == false)
        #expect(domains.isActive == true)
        #expect(chrome.title == "Domains")
        let configureDomains = try #require(domains.configure)
        configureDomains(false, 81)
        host.layoutSubtreeIfNeeded()
        let domainScroll = try #require(scrollViews(in: host).first { $0 !== taskScroll })
        domainScroll.contentView.scroll(to: NSPoint(x: 0, y: 480))
        domainScroll.reflectScrolledClipView(domainScroll.contentView)
        let domainOffset = domainScroll.contentView.bounds.origin
        #expect(domainOffset.y > 0)

        host.rootView = pages([.tasks, .domains], selection: .tasks, server: server)
        host.layoutSubtreeIfNeeded()
        #expect(tasks.identity == identity)
        #expect(tasks.filterEven == true)
        #expect(tasks.selectedRow == 80)
        #expect(tasks.isActive == true)
        #expect(tasks.isEnabled == true)
        #expect(chrome.title == "Tasks")
        #expect(scrollViews(in: host).contains { $0 === taskScroll })
        #expect(taskScroll.contentView.bounds.origin == taskOffset)

        host.rootView = pages([.tasks, .domains], selection: .domains, server: server)
        host.layoutSubtreeIfNeeded()
        #expect(domains.filterEven == false)
        #expect(domains.selectedRow == 81)
        #expect(domainScroll.contentView.bounds.origin == domainOffset)

        host.rootView = pages([.tasks], selection: .tasks, server: UUID())
        host.layoutSubtreeIfNeeded()
        #expect(tasks.identity != identity, "Server changes must discard retained page instances")
        #expect(tasks.selectedRow == nil)
        #expect(tasks.filterEven == false)
    }

    @Test
    func deeperActiveTitlesWinAndDormantTitlesCannotReplaceThem() {
        var title: WorkspaceNavigationTitle?
        WorkspaceNavigationTitleKey.reduce(value: &title) { .init(title: "Tasks", depth: 0) }
        WorkspaceNavigationTitleKey.reduce(value: &title) { .init(title: "Example Task", depth: 1) }
        WorkspaceNavigationTitleKey.reduce(value: &title) { nil }
        WorkspaceNavigationTitleKey.reduce(value: &title) { .init(title: "Tasks", depth: 0) }
        #expect(title == WorkspaceNavigationTitle(title: "Example Task", depth: 1))
    }

    @Test
    func retainedNavigationStacksKeepTheirDetailsAndPublishOnlyTheActiveTitle() {
        let history = NavigationHistory()
        let chrome = ChromeObservation()
        history.visit(NavigationLocation(destination: .tasks, details: [80]))

        func pages() -> some View {
            WorkspacePages(
                destinations: history.visitedDestinations,
                selection: history.current.destination
            ) { destination in
                RetainedStackPage(destination: destination)
            }
            .environment(\.navigationHistory, history)
            .onPreferenceChange(WorkspaceNavigationTitleKey.self) { chrome.title = $0?.title }
            .transaction { $0.disablesAnimations = true }
        }

        let host = NSHostingView(rootView: pages())
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        host.layoutSubtreeIfNeeded()
        #expect(chrome.title == "Tasks 80")
        history.activate(.edge)
        history.visit(NavigationLocation(destination: .domains, details: [81]))
        host.rootView = pages()
        host.layoutSubtreeIfNeeded()
        #expect(chrome.title == "Domains 81")
        #expect(history.location(for: .tasks).details == [80])
        history.activate(.runtime)
        host.rootView = pages()
        host.layoutSubtreeIfNeeded()
        #expect(history.current == NavigationLocation(destination: .tasks, details: [80]))
        #expect(chrome.title == "Tasks 80")
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }
}

@MainActor
private final class PageObservation {
    var identity: UUID?
    var filterEven: Bool?
    var selectedRow: Int?
    var isActive: Bool?
    var isEnabled: Bool?
    var configure: ((Bool, Int) -> Void)?
}

@MainActor
private final class ChromeObservation {
    var title: String?
}

private struct RetainedStackPage: View {
    let destination: AppDestination
    @NavigationDetailPath private var path: [Int]

    init(destination: AppDestination) {
        self.destination = destination
        _path = NavigationDetailPath(destination)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Text(destination.title)
                .workspaceNavigationTitle(destination.title)
                .managementDestination(for: Int.self) { id in
                    Text("Example \(id)")
                        .workspaceNavigationTitle("\(destination.title) \(id)")
                }
        }
    }
}

private struct StatefulListPage: View {
    let destination: AppDestination
    let observation: PageObservation
    let layout: WorkspacePageLayout
    @Environment(\.isWorkspacePageActive) private var isActive
    @Environment(\.isEnabled) private var isEnabled
    @State private var identity = UUID()
    @State private var filterEven = false
    @State private var selectedRow: Int?

    private var rows: [Int] {
        Array(0..<200).filter { !filterEven || $0.isMultiple(of: 2) }
    }

    var body: some View {
        observation.identity = identity
        observation.filterEven = filterEven
        observation.selectedRow = selectedRow
        observation.isActive = isActive
        observation.isEnabled = isEnabled
        observation.configure = { filter, row in
            filterEven = filter
            selectedRow = row
        }
        return content.workspaceNavigationTitle(destination.title)
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .list:
            List(selection: $selectedRow) {
                ForEach(rows, id: \.self) { row in
                    Text("Example row \(row)").tag(row)
                }
            }
        case .cards:
            ManagementDetailLayout {
                ForEach(rows, id: \.self) { row in
                    Text("Example row \(row)").frame(height: 32)
                }
            }
        }
    }
}
#endif
