import SwiftUI

struct ManagementResourceStatus {
    let title: String
    let color: Color

    static let unknown = ManagementResourceStatus(title: "Unknown", color: .secondary)
    static let mixed = ManagementResourceStatus(title: "Mixed", color: .secondary)
    static let degraded = ManagementResourceStatus(title: "Degraded", color: .orange)

    static func aggregate<State: Equatable>(
        _ states: [State],
        display: (State) -> ManagementResourceStatus,
        isFailure: (State) -> Bool
    ) -> ManagementResourceStatus {
        guard let first = states.first else {
            return .unknown
        }
        if states.allSatisfy({ $0 == first }) {
            return display(first)
        }
        return states.contains(where: isFailure) ? .degraded : .mixed
    }
}

nonisolated enum ManagementResourceName {
    static func title(_ rawName: String, fallback: String) -> String {
        let words = rawName
            .split { character in
                character == "_" || character == "-" || character.isWhitespace
            }
            .map { word in
                word.prefix(1).uppercased() + String(word.dropFirst())
            }
        return words.isEmpty ? fallback : words.joined(separator: " ")
    }
}

struct ManagementResourceRow: View {
    let name: String
    let systemImage: String
    var assetImage: String? = nil
    var assetIsTemplate = false
    var iconTint: Color? = nil
    var detail: String? = nil
    var tags: [String] = []
    var warningBadge: String? = nil
    let status: String
    let statusColor: Color
    var quickActionTitle: String? = nil
    var quickActionSystemImage = "play.fill"
    var quickActionDisabled = false
    var quickAction: () -> Void = {}
    var isSelected = false
    var select: () -> Void = {}
    var open: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                select()
                open()
            } label: {
                resourceLabel
                    .padding(.vertical, 7)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(name)")
            .accessibilityIdentifier("management-resource-open")
            .help("Open \(name)")
#if os(macOS)
            .pointerStyle(.link)
#endif

            if let quickActionTitle {
                Button(action: quickAction) {
                    Label(quickActionTitle, systemImage: quickActionSystemImage)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(quickActionDisabled)
                .padding(.trailing, 8)
            }
        }
        .textSelection(.disabled)
        .background(rowBackground, in: .rect(cornerRadius: 7))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .listRowSeparator(.visible)
        .listRowSeparatorTint(Color.secondary.opacity(0.18))
        .accessibilityElement(children: .contain)
    }

    private var resourceLabel: some View {
        HStack(spacing: 12) {
            Group {
                if let assetImage {
                    Image(assetImage)
                        .resizable()
                        .renderingMode(assetIsTemplate ? .template : .original)
                        .scaledToFit()
                } else {
                    Image(systemName: systemImage)
                        .font(.body.weight(.medium))
                }
            }
            .foregroundStyle(iconTint ?? Color.accentColor)
            .frame(width: 22, height: 22)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let warningBadge {
                    ManagementWarningBadge(title: warningBadge)
                }
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if !tags.isEmpty {
                    ManagementResourceTags(tags: tags)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        if isHovered {
            return Color.accentColor.opacity(0.06)
        }
        return .clear
    }
}

/// Informational tags, never inferred capabilities or execution policy.
struct ManagementResourceTags: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                Text(tag)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: .capsule)
            }
        }
    }
}

#Preview {
    List {
        ManagementResourceRow(
            name: "HTTP Server",
            systemImage: "server.rack",
            status: "Running",
            statusColor: .green
        )
        ManagementResourceRow(
            name: "PHP Runtime",
            systemImage: "chevron.left.forwardslash.chevron.right",
            status: "Degraded",
            statusColor: .orange
        )
    }
    .frame(width: 420, height: 180)
}

struct ManagementWarningBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.yellow.opacity(0.25), in: .capsule)
            .overlay(Capsule().stroke(.yellow.opacity(0.65), lineWidth: 1))
    }
}
