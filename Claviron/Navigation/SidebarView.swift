import SwiftUI

struct SidebarView: View {
    @Binding var selection: AppDestination?
    var userManagementAvailable = false
    @Environment(\.navigationHistory) private var history

    var body: some View {
#if os(macOS)
        NavigationRailView(
            selection: $selection,
            userManagementAvailable: userManagementAvailable,
            openGroup: openGroup
        )
#else
        List(selection: $selection) {
            ForEach(NavigationGroup.primaryGroups) { group in
                if group == .overview {
                    NavigationLink(value: AppDestination.overview) {
                        Label(group.title, systemImage: group.systemImage)
                    }
                    .accessibilityIdentifier("destination.overview")
                } else {
                    Section {
                        ForEach(group.destinations(userManagementAvailable: userManagementAvailable)) { destination in
                            NavigationLink(value: destination) {
                                Text(destination.title)
                            }
                            .accessibilityIdentifier("destination.\(destination.rawValue)")
                        }
                    } header: {
                        Label(group.title, systemImage: group.systemImage)
                    }
                }
            }
        }
        .accessibilityIdentifier("sidebar")
        .navigationTitle("Claviron")
#endif
    }

#if os(macOS)
    private func openGroup(_ group: NavigationGroup) {
        if let history {
            history.activate(group, userManagementAvailable: userManagementAvailable)
        } else {
            selection = group.landing(userManagementAvailable: userManagementAvailable)
        }
    }
#endif
}

#if os(macOS)
/// Main groups can be pinned in the rail; every group remains in its menu.
private struct NavigationRailView: View {
    @Binding var selection: AppDestination?
    var userManagementAvailable = false
    let openGroup: (NavigationGroup) -> Void
    @State private var hoverMenu = RailHoverMenu()
    @AppStorage(NavigationPins.storageKey) private var storedPins = NavigationPins.defaultValue

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(NavigationPins(storedValue: storedPins).groups) { group in
                        entry(group)
                    }
                }
                .padding(SidebarMetrics.columnPadding)
            }
            .scrollIndicators(.hidden)
            VStack(spacing: 6) {
                NavigationRailMenu(
                    selection: $selection,
                    storedPins: $storedPins,
                    openGroup: openGroup
                )
                Divider()
                ProfileMenu(selection: $selection, userManagementAvailable: userManagementAvailable)
            }
            .padding(SidebarMetrics.columnPadding)
        }
        .frame(width: SidebarDensity.railWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlayPreferenceValue(RailMenuAnchors.self) { anchors in
            GeometryReader { geometry in
                RailHoverOverlay(
                    menu: hoverMenu,
                    triggers: anchors.mapValues { geometry[$0] },
                    railSize: geometry.size,
                    selection: $selection,
                    userManagementAvailable: userManagementAvailable
                )
            }
        }
        .accessibilityIdentifier("navigation-rail")
    }

    private func entry(_ group: NavigationGroup) -> some View {
        NavigationEntry(
            title: group.title,
            systemImage: group.systemImage,
            isSelected: (selection ?? .overview).group == group,
            identifier: "rail.\(group.rawValue)"
        ) {
            hoverMenu.dismiss()
            openGroup(group)
        }
        .anchorPreference(key: RailMenuAnchors.self, value: .bounds) { [group: $0] }
    }
}

struct WorkspaceNavigationView: View {
    @Binding var selection: AppDestination?
    var userManagementAvailable = false

    private var group: NavigationGroup { (selection ?? .overview).group }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                    .font(.headline)
                    .padding(.horizontal, SidebarMetrics.entryInset)
                    .padding(.vertical, 12)
                ForEach(group.destinations(userManagementAvailable: userManagementAvailable)) { destination in
                    NavigationEntry(
                        title: destination.title,
                        systemImage: nil,
                        isSelected: (selection ?? .overview) == destination,
                        identifier: "destination.\(destination.rawValue)"
                    ) {
                        selection = destination
                    }
                }
            }
            .padding(SidebarMetrics.columnPadding)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.background.secondary)
        .accessibilityIdentifier("workspace-navigation")
    }
}

private enum SidebarMetrics {
    static let columnPadding: CGFloat = 8
    static let entryInset: CGFloat = 8
    static let entryHeight: CGFloat = 32
}

private struct NavigationEntry: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let identifier: String
    let select: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: isSelected ? .medium : .regular))
                        .symbolVariant(isSelected ? .fill : .none)
                } else {
                    Text(title)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .padding(.horizontal, SidebarMetrics.entryInset)
                }
            }
            .foregroundStyle(foreground)
            .frame(
                minWidth: 0,
                maxWidth: .infinity,
                minHeight: systemImage == nil ? SidebarMetrics.entryHeight : 40,
                alignment: systemImage == nil ? .leading : .center
            )
            .clipped()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(background, in: .rect(cornerRadius: 8))
        .onHover { isHovered = $0 }
        .help(systemImage == nil ? "" : title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private var background: Color {
        if isSelected {
            Color.primary.opacity(0.085)
        } else if isHovered {
            Color.primary.opacity(0.045)
        } else {
            .clear
        }
    }

    private var foreground: Color {
        isSelected || isHovered ? .primary : .secondary.opacity(0.8)
    }
}
#endif

#Preview {
    @Previewable @State var selection: AppDestination? = .runtimeOverview
#if os(macOS)
    HStack(spacing: 0) {
        SidebarView(selection: $selection)
        WorkspaceNavigationView(selection: $selection)
            .frame(width: SidebarDensity.expanded.workspaceWidth)
        Divider()
        DestinationPlaceholderView(destination: selection ?? .overview)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
#else
    NavigationSplitView {
        SidebarView(selection: $selection)
    } detail: {
        DestinationPlaceholderView(destination: selection ?? .overview)
    }
#endif
}
