import SwiftUI

extension EnvironmentValues {
    @Entry var isWorkspacePageActive = true
    @Entry var workspaceNavigationDepth = 0
}

/// A title from the visible page, with pushed details taking precedence.
struct WorkspaceNavigationTitle: Equatable {
    let title: String
    let depth: Int
}

struct WorkspaceNavigationTitleKey: PreferenceKey {
    static let defaultValue: WorkspaceNavigationTitle? = nil

    static func reduce(value: inout WorkspaceNavigationTitle?, nextValue: () -> WorkspaceNavigationTitle?) {
        guard let next = nextValue() else { return }
        if let current = value, current.depth > next.depth { return }
        value = next
    }
}

extension View {
    func workspaceNavigationTitle(_ title: String) -> some View {
        modifier(WorkspaceNavigationTitleModifier(title: title))
    }
}

private struct WorkspaceNavigationTitleModifier: ViewModifier {
    let title: String
    @Environment(\.isWorkspacePageActive) private var isActive
    @Environment(\.workspaceNavigationDepth) private var depth

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .preference(
                key: WorkspaceNavigationTitleKey.self,
                value: isActive ? WorkspaceNavigationTitle(title: title, depth: depth) : nil
            )
    }
}

#if os(macOS)
/// Pages are created on first visit and remain mounted at the same size.
/// Hiding a page leaves its native scroll view and local state intact.
struct WorkspacePages<Page: View>: View {
    let destinations: [AppDestination]
    let selection: AppDestination
    @ViewBuilder let page: (AppDestination) -> Page

    var body: some View {
        ZStack {
            ForEach(destinations) { destination in
                let isActive = destination == selection
                page(destination)
                    .environment(\.isWorkspacePageActive, isActive)
                    .opacity(isActive ? 1 : 0)
                    .disabled(!isActive)
                    .allowsHitTesting(isActive)
                    .accessibilityHidden(!isActive)
                    .zIndex(isActive ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
