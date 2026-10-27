#if os(macOS)
import SwiftUI

/// The controls beside the window buttons: back, forward, and the sidebar
/// toggle. One toolbar item, so their size and spacing are this view's
/// rather than the toolbar's, which spreads separate items further apart.
struct NavigationToolbarControls: View {
    @Bindable var history: NavigationHistory
    var hasWorkspaceNavigation = true
    @AppStorage(SidebarDensity.storageKey) private var storedDensity = SidebarDensity.expanded.rawValue

    var body: some View {
        let density = SidebarDensity.resolve(storedDensity)
        HStack(spacing: 18) {
            Button("Back", systemImage: "arrow.left", action: history.back)
                .disabled(!history.canGoBack)
                .foregroundStyle(history.canGoBack ? Color.primary : Color.secondary.opacity(0.35))
                .help("Back")
                .keyboardShortcut("[", modifiers: .command)
                .accessibilityIdentifier("navigation-back")
            Button("Forward", systemImage: "arrow.right", action: history.forward)
                .disabled(!history.canGoForward)
                .foregroundStyle(history.canGoForward ? Color.primary : Color.secondary.opacity(0.35))
                .help("Forward")
                .keyboardShortcut("]", modifiers: .command)
                .accessibilityIdentifier("navigation-forward")

            // Toggle only the workspace navigation; the outer rail stays put.
            Button(density.toggleTitle, systemImage: "sidebar.left") {
                storedDensity = density.toggled.rawValue
            }
            .disabled(!hasWorkspaceNavigation)
            .help(density.toggleTitle)
            .keyboardShortcut("b", modifiers: .command)
            .accessibilityIdentifier("sidebar-density-toggle")
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
    }
}
#endif
