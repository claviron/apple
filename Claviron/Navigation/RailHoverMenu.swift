#if os(macOS)
import AppKit
import Observation
import SwiftUI

/// Hovering previews navigation without selecting a group or resizing a pane.
@MainActor
@Observable
final class RailHoverMenu {
    private(set) var group: NavigationGroup?

    func move(to point: CGPoint, triggers: [NavigationGroup: CGRect], panel: CGRect?) {
        if let target = triggers.first(where: { $0.value.contains(point) && $0.key != .overview }) {
            group = target.key
            return
        }
        guard let group, let trigger = triggers[group], let panel else {
            dismiss()
            return
        }
        let bridge = CGRect(
            x: trigger.minX, y: trigger.minY,
            width: panel.minX - trigger.minX, height: trigger.height
        )
        if !panel.contains(point) && !bridge.contains(point) { dismiss() }
    }

    func dismiss() { group = nil }

    static func panelFrame(trigger: CGRect, railSize: CGSize, panelSize: CGSize) -> CGRect {
        CGRect(
            x: railSize.width,
            y: max(0, min(trigger.minY, railSize.height - panelSize.height)),
            width: panelSize.width,
            height: panelSize.height
        )
    }
}

struct RailMenuAnchors: PreferenceKey {
    static let defaultValue: [NavigationGroup: Anchor<CGRect>] = [:]

    static func reduce(value: inout [NavigationGroup: Anchor<CGRect>], nextValue: () -> [NavigationGroup: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct RailHoverOverlay: View {
    @Bindable var menu: RailHoverMenu
    let triggers: [NavigationGroup: CGRect]
    let railSize: CGSize
    @Binding var selection: AppDestination?
    var userManagementAvailable = false
    @State private var panelHeight: CGFloat = 0

    private var panel: CGRect? {
        guard let group = menu.group, let trigger = triggers[group] else { return nil }
        return RailHoverMenu.panelFrame(
            trigger: trigger, railSize: railSize,
            panelSize: CGSize(width: SidebarDensity.expanded.workspaceWidth, height: panelHeight)
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RailHoverTracking(
                isPresented: menu.group != nil,
                move: { menu.move(to: $0, triggers: triggers, panel: panel) },
                dismiss: menu.dismiss
            )
            .frame(width: railSize.width, height: railSize.height)

            if let group = menu.group, let panel {
                submenu(group)
                    .frame(width: SidebarDensity.expanded.workspaceWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
                    .offset(x: panel.minX, y: panel.minY)
            }
        }
        .frame(width: railSize.width, height: railSize.height, alignment: .topLeading)
        .onChange(of: triggers) { _, triggers in
            if let group = menu.group, triggers[group] == nil { menu.dismiss() }
        }
    }

    private func submenu(_ group: NavigationGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.title)
                .font(.headline)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

            ForEach(group.destinations(userManagementAvailable: userManagementAvailable)) { destination in
                RailHoverDestination(
                    destination: destination,
                    isSelected: selection == destination
                ) {
                    menu.dismiss()
                    selection = destination
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.2))
        }
        .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(group.title) submenu")
        .accessibilityIdentifier("rail-submenu.\(group.rawValue)")
    }
}

private struct RailHoverDestination: View {
    let destination: AppDestination
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack {
                Text(destination.title)
                    .fontWeight(isSelected ? .semibold : .regular)
                Spacer(minLength: 8)
                if isSelected { Image(systemName: "checkmark").font(.caption.weight(.semibold)) }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(isHovered ? 0.075 : isSelected ? 0.045 : 0), in: .rect(cornerRadius: 7))
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("rail-submenu.destination.\(destination.rawValue)")
    }
}

/// Window-local pointer events cover the icon-to-panel gap without a timer.
/// The backing view is transparent to clicks, so the active page stays usable.
private struct RailHoverTracking: NSViewRepresentable {
    let isPresented: Bool
    let move: (CGPoint) -> Void
    let dismiss: () -> Void

    func makeNSView(context: Context) -> TrackingView { TrackingView() }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.isPresented = isPresented
        view.move = move
        view.dismiss = dismiss
    }

    static func dismantleNSView(_ view: TrackingView, coordinator: ()) { view.stop() }

    final class TrackingView: NSView {
        var isPresented = false
        var move: (CGPoint) -> Void = { _ in }
        var dismiss: () -> Void = {}
        private var monitor: Any?
        private var resignation: NSObjectProtocol?
        private var windowTracking: NSTrackingArea?
        private weak var trackedContent: NSView?

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window, let content = window.contentView else { return }
            let tracking = NSTrackingArea(
                rect: .zero,
                options: [.inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
                owner: self,
                userInfo: nil
            )
            content.addTrackingArea(tracking)
            windowTracking = tracking
            trackedContent = content
            resignation = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in self?.dismiss() }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged,
                           .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]
            ) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        override func mouseEntered(with event: NSEvent) { updatePointer(event) }
        override func mouseMoved(with event: NSEvent) { updatePointer(event) }
        override func mouseExited(with event: NSEvent) { dismiss() }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window, window.isKeyWindow else {
                dismiss()
                return event
            }
            if event.type == .keyDown {
                if isPresented && event.keyCode == 53 {
                    dismiss()
                    return nil
                }
            } else {
                updatePointer(event)
            }
            return event
        }

        private func updatePointer(_ event: NSEvent) {
            move(convert(event.locationInWindow, from: nil))
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let resignation { NotificationCenter.default.removeObserver(resignation) }
            if let windowTracking { trackedContent?.removeTrackingArea(windowTracking) }
            monitor = nil
            resignation = nil
            windowTracking = nil
            trackedContent = nil
        }
    }
}
#endif
