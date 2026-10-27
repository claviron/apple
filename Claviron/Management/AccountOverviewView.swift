import ClavironControlPlane
import SwiftUI

/// Navigation is available before user and authorization inventories are loaded.
struct AccountOverviewView: View {
    let group: NavigationGroup
    let serverID: ServerID
    @Bindable var connectionModel: ConnectionModel

    private var capability: String { group == .users ? "users" : "authorization" }

    var body: some View {
        ManagementDetailLayout {
            ManagementDetailCard(group.title, systemImage: group.systemImage, tint: .indigo) {
                if let info = connectionModel.serverInfo(for: serverID) {
                    if info.capabilities.contains(capability) {
                        Text("Supported by this server")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not supported by this server")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Server capabilities not reported")
                        .foregroundStyle(.secondary)
                }
                if let failure = connectionModel.serverInfoFailure(for: serverID) {
                    Text(failure.localizedDescription)
                        .foregroundStyle(.red)
                        .copyableMessage(failure.localizedDescription)
                }
            }
            if group == .users {
                unreported("Users")
            } else {
                unreported("Roles")
                unreported("Permissions")
            }
        }
        .workspaceNavigationTitle("\(group.title) Overview")
        .pageRefreshable(every: .seconds(2)) {
            await connectionModel.refreshServerInfo(for: serverID)
        }
    }

    private func unreported(_ title: String) -> some View {
        ManagementDetailCard(title) {
            Text("—")
                .font(.system(.title, design: .rounded, weight: .bold))
                .accessibilityLabel("Not reported")
            Text("Count not reported")
                .foregroundStyle(.secondary)
        }
    }
}
