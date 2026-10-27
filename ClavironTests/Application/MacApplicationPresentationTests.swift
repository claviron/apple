#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Claviron

@MainActor
struct MacApplicationPresentationTests {
    @Test
    func appStartsWithRegularDockPresentation() {
        let isAgentApp = Bundle.main.object(
            forInfoDictionaryKey: "LSUIElement"
        ) as? Bool ?? false

        #expect(!isAgentApp)
        #expect(NSImage(named: NSImage.Name("MenuBarIcon")) != nil)
        #expect(ClavironWindow.mainID == "main")
    }

    @Test
    func trayStaysVisibleWhileDockFollowsWindowVisibility() {
        var policies: [NSApplication.ActivationPolicy] = []
        let presentation = MacApplicationPresentation { policy in
            policies.append(policy)
            return true
        }

        presentation.windowDidBecomeHidden()

        #expect(presentation.isMenuBarExtraInserted)
        #expect(policies == [.accessory])

        presentation.windowDidBecomeVisible()

        #expect(presentation.isMenuBarExtraInserted)
        #expect(policies == [.accessory, .regular])
    }

    @Test
    func hiddenWindowKeepsItsOnlyRestoreEntryPoint() {
        let presentation = MacApplicationPresentation { _ in true }
        presentation.windowDidBecomeHidden()

        presentation.menuBarExtraBinding.wrappedValue = false

        #expect(presentation.isMenuBarExtraInserted)
    }

    @Test
    func closeKeepsTheWindowAliveInTheTrayWithoutMiniaturizing() {
        var policies: [NSApplication.ActivationPolicy] = []
        let presentation = MacApplicationPresentation { policy in
            policies.append(policy)
            return true
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let originalDelegate = WindowDelegateFixture()
        window.delegate = originalDelegate
        window.contentView = MacWindowObservationView(presentation: presentation)
        window.orderFront(nil)

        #expect(window.delegate is MacWindowCloseDelegate)
        #expect(window.delegate?.windowShouldZoom?(window, toFrame: .zero) == false)
        #expect(originalDelegate.zoomWasForwarded)

        window.performClose(nil)

        #expect(!window.isVisible)
        #expect(!window.isMiniaturized)
        #expect(presentation.isMenuBarExtraInserted)
        #expect(policies.last == .accessory)
        #expect(window.delegate is MacWindowCloseDelegate)

        presentation.showMainWindow()

        #expect(window.isVisible)
        #expect(!window.isMiniaturized)
        #expect(presentation.isMenuBarExtraInserted)
        #expect(policies.last == .regular)
        window.orderOut(nil)
    }

    @Test
    func closeButtonStillHidesWhenSwiftUIReplacesTheDelegate() {
        let presentation = MacApplicationPresentation { _ in true }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let observer = MacWindowObservationView(presentation: presentation)
        window.contentView = observer
        window.orderFront(nil)
        let replacementDelegate = WindowDelegateFixture()
        window.delegate = replacementDelegate

        window.standardWindowButton(.closeButton)?.performClick(nil)

        #expect(!window.isVisible)
        #expect(presentation.isMenuBarExtraInserted)
        #expect(!MacApplicationDelegate().applicationShouldTerminateAfterLastWindowClosed(
            NSApplication.shared
        ))
        presentation.showMainWindow()
        #expect(window.isVisible)
        window.orderOut(nil)
    }
}

@MainActor
private final class WindowDelegateFixture: NSObject, NSWindowDelegate {
    var zoomWasForwarded = false

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        zoomWasForwarded = true
        return false
    }
}
#endif
