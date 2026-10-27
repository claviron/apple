#if os(macOS)
import SwiftUI

/// Collapsing navigation changes only its allocated width. Both view trees
/// stay mounted, retaining selection, scroll position, and detail state.
struct WorkspaceView<Navigation: View, Detail: View>: View {
    let density: SidebarDensity
    var hasNavigation = true
    @ViewBuilder let navigation: () -> Navigation
    @ViewBuilder let detail: () -> Detail
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var navigationWidth: CGFloat {
        hasNavigation ? density.workspaceWidth : 0
    }

    var body: some View {
        HStack(spacing: 0) {
            navigation()
                .frame(width: SidebarDensity.expanded.workspaceWidth)
                .overlay(alignment: .trailing) { Divider() }
                .offset(x: navigationWidth > 0 ? 0 : -SidebarDensity.expanded.workspaceWidth)
                .frame(width: navigationWidth, alignment: .leading)
                .clipped()
                .disabled(navigationWidth == 0)
                .allowsHitTesting(navigationWidth > 0)
                .accessibilityHidden(navigationWidth == 0)

            detail()
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: SidebarDensity.drawerDuration),
            value: navigationWidth
        )
        .background(.background)
        .clipShape(.rect(topLeadingRadius: 12, bottomLeadingRadius: 12))
    }
}
#endif
