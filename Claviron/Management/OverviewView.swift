import ClavironControlPlane
import SwiftUI

/// The connection's landing page. Runtime inventories have their own dashboard.
struct OverviewView: View {
    let server: ServerProfile
    let tlsProfile: TLSProfile?
    @Bindable var connectionModel: ConnectionModel

    private var state: ServerConnectionState {
        connectionModel.state(for: server.id)
    }

    private var brandTitle: String {
        guard let name = connectionModel.serverInfo(for: server.id)?.name,
              !name.isEmpty else { return "Claviron" }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    var body: some View {
        ManagementDetailLayout {
            ManagementDetailCard(tint: .indigo) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(brandTitle)
                            .font(.largeTitle.weight(.bold))
                        Text("Control Plane Overview")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(server.name)
                            .font(.headline)
                            .padding(.top, 7)
                        Text(server.address)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 16)
                    Image("ClavironLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 104, height: 104)
                        .accessibilityHidden(true)
                }
            }

            ManagementDetailCard("Connection", systemImage: state.systemImage, tint: connectionTint) {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Server", value: server.name)
                    LabeledContent("Endpoint", value: server.address)
                    LabeledContent("State", value: state.title)
                    LabeledContent("TLS Profile", value: tlsProfile?.name ?? "Not configured")
                    LabeledContent("Transport", value: "gRPC · mTLS")

                    if case let .failed(failure, _) = state {
                        Text(failure.localizedDescription)
                            .foregroundStyle(.red)
                            .copyableMessage(failure.localizedDescription)
                    }
                    connectionActions
                }
            }
        }
        .workspaceNavigationTitle("Overview")
        .pageRefreshable(every: .seconds(2)) { await connectionModel.refreshServerInfo(for: server.id) }
    }

    @ViewBuilder
    private var connectionActions: some View {
        switch state {
        case .disconnected:
            Button("Connect", systemImage: "bolt.horizontal") {
                Task { await connectionModel.connect(to: server.id) }
            }
        case .failed:
            Button("Reconnect", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
                Task { await connectionModel.reconnect(server.id) }
            }
        case .connecting, .refreshing:
            ProgressView().controlSize(.small)
        case .connected:
            Button("Disconnect", systemImage: "network.slash") {
                Task { await connectionModel.disconnect(server.id) }
            }
        }
    }

    private var connectionTint: Color {
        switch state {
        case .connected: .green
        case .connecting, .refreshing: .blue
        case .failed: .red
        case .disconnected: .secondary
        }
    }
}
