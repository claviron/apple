import ClavironControlPlane
import SwiftUI

struct ConnectionStatusControl: View {
    let serverID: ServerID
    @Bindable var connectionModel: ConnectionModel
    let pageRefresh: PageRefreshCommands
    @State private var isPresented = false

    private var state: ServerConnectionState {
        connectionModel.state(for: serverID)
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            ConnectionToolbarLabel(
                title: state.isFailure ? "Connection issue" : state.title,
                systemImage: state.systemImage,
                tint: statusColor,
                isBusy: state.isBusy
            )
        }
        .buttonStyle(.plain)
        .disabled(state.isBusy)
        .accessibilityLabel("Connection: \(state.title)")
        .help(state.title)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Connection", systemImage: state.systemImage)
                    .font(.headline)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                Text(state.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                Divider()
                actions
            }
            .padding(12)
            .frame(width: 300)
            .presentationCompactAdaptation(.popover)
        }
        .onChange(of: serverID) { _, _ in isPresented = false }
    }

    private var statusColor: Color {
        switch state {
        case let .connected(snapshot):
            snapshot.coverage == .complete ? .green : .orange
        case .failed:
            .red
        case .connecting, .refreshing:
            .accentColor
        case .disconnected:
            .secondary
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch state {
        case .disconnected:
            ConnectionMenuAction("Connect", systemImage: "bolt.horizontal") {
                isPresented = false
                Task {
                    await connectionModel.connect(to: serverID)
                }
            }
        case .connected, .failed:
            ConnectionMenuAction("Refresh", systemImage: "arrow.clockwise") {
                isPresented = false
                pageRefresh.refresh()
            }
            .disabled(!pageRefresh.canRefresh)
            Toggle("Automatically Refresh This Page", isOn: pageRefresh.automatic)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .disabled(!pageRefresh.canAutomaticallyRefresh)
            Divider()
            ConnectionMenuAction("Reconnect", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
                isPresented = false
                Task {
                    await connectionModel.reconnect(serverID)
                }
            }
            ConnectionMenuAction("Disconnect", systemImage: "network.slash", tint: .red) {
                isPresented = false
                Task {
                    await connectionModel.disconnect(serverID)
                }
            }
        case .connecting, .refreshing:
            EmptyView()
        }
    }
}

struct ConnectionToolbarLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = .primary
    var isBusy = false

    var body: some View {
        HStack(spacing: 9) {
            if isBusy {
                ProgressView().controlSize(.small).frame(width: 20)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 20)
            }
#if os(macOS)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 180, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
#endif
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
#if os(macOS)
        .frame(minHeight: 36)
#else
        .frame(minHeight: 44)
#endif
        .contentShape(.rect)
        .background(Color.primary.opacity(0.04), in: .capsule)
        .overlay { Capsule().strokeBorder(Color.primary.opacity(0.1)) }
    }
}

private struct ConnectionMenuAction: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    let action: () -> Void
    @State private var isHovered = false

    init(_ title: LocalizedStringKey, systemImage: String, tint: Color = .primary, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage).font(.system(size: 17)).frame(width: 22)
                Text(title).font(.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color.primary.opacity(0.06) : .clear, in: .rect(cornerRadius: 8))
        .onHover { isHovered = $0 }
    }
}

private extension ServerConnectionState {
    var isFailure: Bool {
        if case .failed = self { true } else { false }
    }
}
