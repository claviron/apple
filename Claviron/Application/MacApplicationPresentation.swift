#if os(macOS)
import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class MacApplicationPresentation {
    typealias ActivationPolicySetter = @MainActor (NSApplication.ActivationPolicy) -> Bool

    private(set) var isMenuBarExtraInserted = true

    @ObservationIgnored
    private let setActivationPolicy: ActivationPolicySetter

    @ObservationIgnored
    private weak var mainWindow: NSWindow?

    init(
        setActivationPolicy: @escaping ActivationPolicySetter = {
            NSApplication.shared.setActivationPolicy($0)
        }
    ) {
        self.setActivationPolicy = setActivationPolicy
    }

    var menuBarExtraBinding: Binding<Bool> {
        Binding(
            get: { self.isMenuBarExtraInserted },
            set: { self.menuBarExtraInsertionChanged($0) }
        )
    }

    func observe(window: NSWindow) {
        mainWindow = window

        if window.isVisible && !window.isMiniaturized {
            windowDidBecomeVisible()
        }
    }

    func windowDidBecomeHidden() {
        isMenuBarExtraInserted = true
        _ = setActivationPolicy(.accessory)
    }

    func windowDidBecomeVisible() {
        _ = setActivationPolicy(.regular)
    }

    func hideMainWindow(_ window: NSWindow) {
        mainWindow = window
        window.orderOut(nil)
        windowDidBecomeHidden()
    }

    func showMainWindow() {
        windowDidBecomeVisible()

        if mainWindow?.isMiniaturized == true {
            mainWindow?.deminiaturize(nil)
        }
        mainWindow?.makeKeyAndOrderFront(nil)

        NSApplication.shared.activate()
    }

    private func menuBarExtraInsertionChanged(_: Bool) {
        // Keep a permanent restore entry point, even while the window is open.
        isMenuBarExtraInserted = true
    }
}

struct MacWindowPresentationObserver: NSViewRepresentable {
    let presentation: MacApplicationPresentation

    func makeNSView(context: Context) -> MacWindowObservationView {
        MacWindowObservationView(presentation: presentation)
    }

    func updateNSView(_ view: MacWindowObservationView, context: Context) {
        view.presentation = presentation
        view.installCloseHandling()
    }
}

final class MacWindowObservationView: NSView {
    weak var presentation: MacApplicationPresentation? {
        didSet { closeDelegate?.presentation = presentation }
    }

    private weak var observedWindow: NSWindow?
    private var closeDelegate: MacWindowCloseDelegate?

    init(presentation: MacApplicationPresentation) {
        self.presentation = presentation
        super.init(frame: .zero)

        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidBecomeHidden),
            name: NSApplication.didHideNotification,
            object: NSApplication.shared
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidBecomeVisible),
            name: NSApplication.didUnhideNotification,
            object: NSApplication.shared
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        let notificationCenter = NotificationCenter.default
        if let observedWindow {
            if observedWindow.delegate === closeDelegate {
                observedWindow.delegate = closeDelegate?.originalDelegate
            }
            notificationCenter.removeObserver(
                self,
                name: NSWindow.didMiniaturizeNotification,
                object: observedWindow
            )
            notificationCenter.removeObserver(
                self,
                name: NSWindow.didDeminiaturizeNotification,
                object: observedWindow
            )
            notificationCenter.removeObserver(
                self,
                name: NSWindow.didBecomeKeyNotification,
                object: observedWindow
            )
            notificationCenter.removeObserver(
                self,
                name: NSWindow.willCloseNotification,
                object: observedWindow
            )
        }

        observedWindow = window
        closeDelegate = nil
        guard let window else {
            return
        }

        let closeDelegate = MacWindowCloseDelegate(
            presentation: presentation,
            originalDelegate: window.delegate
        )
        self.closeDelegate = closeDelegate
        window.delegate = closeDelegate
        installCloseHandling()
        presentation?.observe(window: window)
        notificationCenter.addObserver(
            self,
            selector: #selector(windowDidBecomeHidden),
            name: NSWindow.didMiniaturizeNotification,
            object: window
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(windowDidBecomeVisible),
            name: NSWindow.didDeminiaturizeNotification,
            object: window
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(windowDidBecomeVisible),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(windowDidBecomeHidden),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    @objc private func windowDidBecomeHidden() {
        presentation?.windowDidBecomeHidden()
    }

    @objc private func windowDidBecomeVisible() {
        installCloseHandling()
        presentation?.windowDidBecomeVisible()
    }

    func installCloseHandling() {
        guard let window = observedWindow else {
            return
        }
        // SwiftUI may replace its delegate after the view first attaches.
        // Bind the traffic-light button directly as well as preserving Cmd-W.
        if let closeDelegate, window.delegate !== closeDelegate {
            closeDelegate.originalDelegate = window.delegate
            window.delegate = closeDelegate
        }
        if let button = window.standardWindowButton(.closeButton) {
            button.target = self
            button.action = #selector(closeToTray)
        }
    }

    @objc private func closeToTray() {
        guard let observedWindow else {
            return
        }
        presentation?.hideMainWindow(observedWindow)
    }

    @objc private func applicationDidBecomeHidden() {
        presentation?.windowDidBecomeHidden()
    }

    @objc private func applicationDidBecomeVisible() {
        guard observedWindow?.isVisible == true,
              observedWindow?.isMiniaturized == false else {
            return
        }
        presentation?.windowDidBecomeVisible()
    }
}

final class MacApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// Keep SwiftUI's window delegate behavior, overriding only close-to-tray.
final class MacWindowCloseDelegate: NSObject, NSWindowDelegate {
    weak var presentation: MacApplicationPresentation?
    weak var originalDelegate: (any NSWindowDelegate)?

    init(
        presentation: MacApplicationPresentation?,
        originalDelegate: (any NSWindowDelegate)?
    ) {
        self.presentation = presentation
        self.originalDelegate = originalDelegate
        super.init()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let presentation else {
            return originalDelegate?.windowShouldClose?(sender) ?? true
        }
        presentation.hideMainWindow(sender)
        return false
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector)
            || (originalDelegate?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if originalDelegate?.responds(to: selector) == true {
            return originalDelegate
        }
        return super.forwardingTarget(for: selector)
    }
}
#endif
