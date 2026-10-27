import SwiftUI

struct ConnectionStatusControl: View {
    let serverID: ServerID
    @Bindable var connectionModel: ConnectionModel
    let pageRefresh: PageRefreshCommands

    private var state: ServerConnectionState {
        connectionModel.state(for: serverID)
    }

    var body: some View {
        Group {
            if state.isBusy {
                HStack(spacing: 8) {
                    Label(state.title, systemImage: state.systemImage)
                        .lineLimit(1)
                    ProgressView()
                        .controlSize(.small)
                }
            } else {
                Menu {
                    actions
                } label: {
                    Label(state.title, systemImage: state.systemImage)
                        .lineLimit(1)
                }
                .accessibilityLabel("Connection: \(state.title)")
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch state {
        case .disconnected:
            Button("Connect", systemImage: "bolt.horizontal") {
                Task {
                    await connectionModel.connect(to: serverID)
                }
            }
        case .connected, .failed:
            Button("Refresh", systemImage: "arrow.clockwise") {
                pageRefresh.refresh()
            }
            .disabled(!pageRefresh.canRefresh)
            Toggle("Automatically Refresh This Page", isOn: pageRefresh.automatic)
                .disabled(!pageRefresh.canAutomaticallyRefresh)
            Button("Reconnect", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
                Task {
                    await connectionModel.reconnect(serverID)
                }
            }
            Divider()
            Button("Disconnect", systemImage: "network.slash") {
                Task {
                    await connectionModel.disconnect(serverID)
                }
            }
        case .connecting, .refreshing:
            EmptyView()
        }
    }
}
