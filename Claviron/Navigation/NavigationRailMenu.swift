#if os(macOS)
import SwiftUI

struct NavigationRailMenu: View {
    @Binding var selection: AppDestination?
    @Binding var storedPins: String
    let openGroup: (NavigationGroup) -> Void
    @State private var isPresented = false
    @State private var isHovered = false

    private var pins: NavigationPins { NavigationPins(storedValue: storedPins) }
    private var selectedGroup: NavigationGroup { (selection ?? .overview).group }
    private var isSelected: Bool {
        isPresented || (NavigationGroup.primaryGroups.contains(selectedGroup) && !pins.contains(selectedGroup))
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 22))
                .foregroundStyle(isSelected || isHovered ? Color.primary : Color.secondary.opacity(0.8))
                .frame(width: 36, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(background, in: .rect(cornerRadius: 8))
        .onHover { isHovered = $0 }
        .help("Sections and Pins")
        .accessibilityLabel("Sections and Pins")
        .accessibilityIdentifier("navigation-sections")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            VStack(spacing: 2) {
                ForEach(NavigationGroup.primaryGroups) { group in
                    NavigationSectionRow(
                        group: group,
                        isSelected: selectedGroup == group,
                        isPinned: pins.contains(group),
                        open: {
                            openGroup(group)
                            isPresented = false
                        },
                        togglePin: {
                            var updated = pins
                            updated.toggle(group)
                            storedPins = updated.storedValue
                        }
                    )
                }
            }
            .padding(8)
            .frame(width: 250)
        }
    }

    private var background: Color {
        if isSelected { Color.primary.opacity(0.085) }
        else if isHovered { Color.primary.opacity(0.045) }
        else { .clear }
    }
}

private struct NavigationSectionRow: View {
    let group: NavigationGroup
    let isSelected: Bool
    let isPinned: Bool
    let open: () -> Void
    let togglePin: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: open) {
                Label {
                    Text(group.title)
                        .fontWeight(isSelected ? .medium : .regular)
                } icon: {
                    Image(systemName: group.systemImage)
                        .frame(width: 24)
                }
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .contentShape(.rect)
            }
            .accessibilityIdentifier("sections.\(group.rawValue)")
            Button(action: togglePin) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(isPinned ? Color.primary : Color.secondary)
                    .frame(width: 28, height: 32)
                    .contentShape(.rect)
            }
            .disabled(group == .overview)
            .help(group == .overview ? "Overview always stays visible" : "\(isPinned ? "Unpin" : "Pin") \(group.title)")
            .accessibilityLabel("\(isPinned ? "Unpin" : "Pin") \(group.title)")
            .accessibilityIdentifier("pin.\(group.rawValue)")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .background(
            Color.primary.opacity(isSelected ? 0.085 : isHovered ? 0.045 : 0),
            in: .rect(cornerRadius: 8)
        )
        .onHover { isHovered = $0 }
    }
}
#endif
