#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Claviron

@MainActor
struct WorkspaceViewTests {
    @Test
    func collapseExpandsDetailWithoutReplacingEitherPane() throws {
        let sidebar = PaneObservation()
        let detail = PaneObservation()

        func workspace(_ density: SidebarDensity) -> some View {
            WorkspaceView(density: density) {
                StatefulPane(observation: sidebar)
            } detail: {
                StatefulPane(observation: detail)
            }
            .transaction { $0.disablesAnimations = true }
        }

        let host = NSHostingView(rootView: workspace(.expanded))
        host.frame = NSRect(x: 0, y: 0, width: 1_200, height: 700)
        host.layoutSubtreeIfNeeded()
        let sidebarIdentity = try #require(sidebar.identity)
        let detailIdentity = try #require(detail.identity)
        #expect(detail.width == 980)

        let selectRoom = try #require(sidebar.select)
        let selectTask = try #require(detail.select)
        selectRoom("example-room")
        selectTask("example-task")
        host.rootView = workspace(.compact)
        host.layoutSubtreeIfNeeded()
        #expect(detail.width == 1_200)
        #expect(detail.identity == detailIdentity)
        #expect(detail.selection == "example-task")

        host.rootView = workspace(.expanded)
        host.layoutSubtreeIfNeeded()
        #expect(detail.width == 980)
        #expect(sidebar.identity == sidebarIdentity)
        #expect(sidebar.selection == "example-room")
        #expect(detail.identity == detailIdentity)
        #expect(detail.selection == "example-task")
    }

    @Test
    func managementContentFillsTheExpandedDesktopArea() {
        let observation = PaneObservation()
        let host = NSHostingView(rootView: ManagementDetailLayout {
            StatefulPane(observation: observation)
                .frame(height: 40)
        })
        host.frame = NSRect(x: 0, y: 0, width: 1_300, height: 700)
        host.layoutSubtreeIfNeeded()
        #expect(observation.width == 1_260)
    }

    @Test
    func managementGroupSymbolsAreAvailable() {
        for group in [NavigationGroup.runtime, .authorization] {
            #expect(NSImage(systemSymbolName: group.systemImage, accessibilityDescription: group.title) != nil)
            #expect(group.landing.systemImage == group.systemImage)
        }
    }
}

/// A headless hosting probe: no application window or product fixture.
@MainActor
private final class PaneObservation {
    var identity: UUID?
    var selection: String?
    var width: CGFloat?
    var select: ((String) -> Void)?
}

private struct StatefulPane: View {
    let observation: PaneObservation
    @State private var identity = UUID()
    @State private var selection = "initial"

    var body: some View {
        observation.identity = identity
        observation.selection = selection
        observation.select = { selection = $0 }
        return Color.clear
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                observation.width = $0
            }
    }
}
#endif
