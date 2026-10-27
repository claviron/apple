#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Claviron

@MainActor
struct RailHoverMenuTests {
    private let triggers: [NavigationGroup: CGRect] = [
        .overview: CGRect(x: 8, y: 8, width: 36, height: 40),
        .runtime: CGRect(x: 8, y: 54, width: 36, height: 40),
        .edge: CGRect(x: 8, y: 100, width: 36, height: 40),
    ]
    private let railSize = CGSize(width: 52, height: 600)

    @Test
    func iconToMenuCrossingStaysOpenAndLeavingDismisses() {
        let menu = RailHoverMenu()
        let panel = RailHoverMenu.panelFrame(
            trigger: triggers[.runtime]!, railSize: railSize,
            panelSize: CGSize(width: 220, height: 220)
        )
        menu.move(to: CGPoint(x: 25, y: 70), triggers: triggers, panel: nil)
        #expect(menu.group == .runtime)
        menu.move(to: CGPoint(x: 48, y: 70), triggers: triggers, panel: panel)
        #expect(menu.group == .runtime)
        menu.move(to: CGPoint(x: 150, y: 220), triggers: triggers, panel: panel)
        #expect(menu.group == .runtime)
        menu.move(to: CGPoint(x: 400, y: 220), triggers: triggers, panel: panel)
        #expect(menu.group == nil)
    }

    @Test
    func anotherGroupReplacesTheMenuAndHomeDoesNotShowADuplicateSubmenu() {
        let menu = RailHoverMenu()
        menu.move(to: CGPoint(x: 25, y: 70), triggers: triggers, panel: nil)
        menu.move(to: CGPoint(x: 25, y: 120), triggers: triggers, panel: nil)
        #expect(menu.group == .edge)
        menu.move(to: CGPoint(x: 25, y: 25), triggers: triggers, panel: nil)
        #expect(menu.group == nil)
    }

    @Test
    func dismissalAndRemovedTriggersClearTheHoverState() {
        let menu = RailHoverMenu()
        menu.move(to: CGPoint(x: 25, y: 70), triggers: triggers, panel: nil)
        menu.dismiss()
        #expect(menu.group == nil)
        menu.move(to: CGPoint(x: 25, y: 70), triggers: triggers, panel: nil)
        menu.move(to: CGPoint(x: 80, y: 70), triggers: [:], panel: CGRect(x: 52, y: 54, width: 220, height: 220))
        #expect(menu.group == nil)
    }

    @Test
    func panelSitsOutsideTheRailAndFitsVertically() {
        let panel = RailHoverMenu.panelFrame(
            trigger: CGRect(x: 8, y: 570, width: 36, height: 40),
            railSize: railSize, panelSize: CGSize(width: 220, height: 220)
        )
        #expect(panel.minX == railSize.width)
        #expect(panel.maxY == railSize.height)
        #expect(panel.width == 220)
        let top = RailHoverMenu.panelFrame(
            trigger: CGRect(x: 8, y: -10, width: 36, height: 40),
            railSize: railSize, panelSize: CGSize(width: 220, height: 220)
        )
        #expect(top.minY == 0)
    }

    @Test
    func hoveringDoesNotResizeTheActiveViewOrChangeItsNavigation() {
        let menu = RailHoverMenu()
        let history = NavigationHistory()
        let location = NavigationLocation(destination: .tasks, details: ["example-task"])
        history.visit(location)
        let observation = HoverLayoutObservation()
        let selection = Binding<AppDestination?>(
            get: { history.current.destination },
            set: { if let destination = $0 { history.visit(NavigationLocation(destination: destination)) } }
        )

        func workspace() -> some View {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: railSize.width)
                    .overlay(alignment: .topLeading) {
                        RailHoverOverlay(
                            menu: menu, triggers: triggers, railSize: railSize, selection: selection
                        )
                    }
                    .zIndex(1)
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { observation.detailWidth = $0 }
            }
        }

        let host = NSHostingView(rootView: workspace())
        host.frame = NSRect(x: 0, y: 0, width: 1_200, height: 600)
        host.layoutSubtreeIfNeeded()
        let width = observation.detailWidth
        #expect(width == 1_148)
        menu.move(to: CGPoint(x: 25, y: 70), triggers: triggers, panel: nil)
        host.rootView = workspace()
        host.layoutSubtreeIfNeeded()
        #expect(menu.group == .runtime)
        #expect(observation.detailWidth == width)
        #expect(history.current == location)
        menu.dismiss()
        host.rootView = workspace()
        host.layoutSubtreeIfNeeded()
        #expect(observation.detailWidth == width)
        #expect(history.current == location)
    }
}

@MainActor
private final class HoverLayoutObservation {
    var detailWidth: CGFloat?
}
#endif
