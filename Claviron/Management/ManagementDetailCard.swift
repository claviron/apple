import SwiftUI

struct ManagementDetailCard<Content: View>: View {
    let title: String?
    let systemImage: String?
    let tint: Color?
    @ViewBuilder let content: () -> Content

    init(
        _ title: String? = nil,
        systemImage: String? = nil,
        tint: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Label(title, systemImage: systemImage ?? "square")
                    .font(.headline)
                    .foregroundStyle(tint ?? Color.primary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .overlay {
                    if let tint {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(tint.opacity(0.055))
                    }
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(tint?.opacity(0.22) ?? Color.secondary.opacity(0.16))
        }
    }
}

struct ManagementResourceHeaderCard<Actions: View>: View {
    let kind: String
    let name: String
    let systemImage: String
    var assetImage: String? = nil
    var assetIsTemplate = false
    var iconTint: Color? = nil
    var warningBadge: String? = nil
    let status: String
    let statusColor: Color
    let actionsDisabled: Bool
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        ManagementDetailCard(tint: statusColor) {
            Text(kind.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                Group {
                    if let assetImage {
                        Image(assetImage)
                            .resizable()
                            .renderingMode(assetIsTemplate ? .template : .original)
                            .scaledToFit()
                    } else {
                        Image(systemName: systemImage)
                            .font(.title2.weight(.semibold))
                    }
                }
                .foregroundStyle(iconTint ?? Color.accentColor)
                .frame(width: 30, height: 30)

                Text(name)
                    .font(.title.weight(.semibold))
                    .lineLimit(2)
                    .textSelection(.enabled)
                if let warningBadge {
                    ManagementWarningBadge(title: warningBadge)
                }

                Spacer(minLength: 16)

                HStack(spacing: 7) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(status)
                        .foregroundStyle(.secondary)
                }

                Menu {
                    actions()
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
                .disabled(actionsDisabled)
                .accessibilityLabel("Actions for \(kind.lowercased()) \(name)")
            }
        }
    }
}

struct ManagementDetailLayout<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                content()
            }
#if os(macOS)
            .frame(maxWidth: .infinity, alignment: .leading)
#else
            .frame(maxWidth: 820)
#endif
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .textSelection(.enabled)
        .background(Color.secondary.opacity(0.035))
    }
}
