import ClavironControlPlane
import SwiftUI

struct EdgeOverviewView: View {
    let serverID: ServerID
    @Bindable var connectionModel: ConnectionModel

    var body: some View {
        ManagementDetailLayout {
            metric("Sites", systemImage: "network", tint: .blue,
                   state: connectionModel.hostingObservationState(for: serverID)) { $0.vhosts.count }
            metric("DNS Zones", systemImage: "point.3.connected.trianglepath.dotted", tint: .cyan,
                   state: connectionModel.dnsZoneObservationState(for: serverID)) { $0.zones.count }
            metric("Domains", systemImage: "globe", tint: .indigo,
                   state: connectionModel.domainObservationState(for: serverID)) { $0.domains.count }
            metric("Certificates", systemImage: "checkmark.shield", tint: .mint,
                   state: connectionModel.certificateObservationState(for: serverID)) { $0.certificates.count }
        }
        .workspaceNavigationTitle("Edge Overview")
        .pageRefreshable(every: .seconds(2)) {
            await loadResources()
        }
    }

    private func loadResources() async {
        async let sites: Void = connectionModel.loadHosting(for: serverID)
        async let dns: Void = connectionModel.loadDnsZones(for: serverID)
        async let domains: Void = connectionModel.loadDomains(for: serverID)
        async let certificates: Void = connectionModel.loadCertificates(for: serverID)
        _ = await (sites, dns, domains, certificates)
    }

    private func metric<Snapshot: Equatable & Sendable>(
        _ title: String,
        systemImage: String,
        tint: Color,
        state: ResourceObservationState<Snapshot>,
        count: (Snapshot) -> Int
    ) -> some View {
        let value = state.snapshot.map(count)
        return ManagementDetailCard(title, systemImage: systemImage, tint: tint) {
            Text(value?.formatted() ?? "—")
                .font(.system(.title, design: .rounded, weight: .bold))
                .accessibilityLabel(value.map(String.init) ?? "Not reported")
            switch state {
            case let .failed(failure), let .stale(_, failure):
                if value != nil { Text("Stale").foregroundStyle(.orange) }
                Text(failure.localizedDescription)
                    .foregroundStyle(.red)
                    .copyableMessage(failure.localizedDescription)
            case .loading:
                ProgressView().controlSize(.small)
            case .disconnected:
                Text("Not connected").foregroundStyle(.secondary)
            case .empty, .loaded:
                EmptyView()
            }
        }
    }
}
