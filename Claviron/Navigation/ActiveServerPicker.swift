import SwiftUI

struct ActiveServerPicker: View {
    @Bindable var applicationModel: ApplicationModel
    @State private var errorMessage: String?
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            ConnectionToolbarLabel(
                title: applicationModel.activeServer.map(applicationModel.configuration.connectionName)
                    ?? "Select Connection",
                systemImage: "server.rack"
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            connections
                .presentationCompactAdaptation(.popover)
        }
        .help(applicationModel.activeServer?.address ?? "No server selected")
#if os(macOS)
        .pointerStyle(.link)
#endif
        .accessibilityLabel("Active connection")
        .alert(
            "Server Not Changed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var connections: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connections")
                .font(.headline)
                .padding(.horizontal, 8)
            Divider()
            if applicationModel.configuration.servers.isEmpty {
                Text("No saved connections")
                    .foregroundStyle(.secondary)
                    .padding(8)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(applicationModel.configuration.servers) { server in
                            ConnectionProfileRow(
                                name: applicationModel.configuration.connectionName(for: server),
                                address: server.address,
                                isSelected: server.id == applicationModel.configuration.activeServerID
                            ) {
                                isPresented = false
                                select(server.id)
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(CGFloat(applicationModel.configuration.servers.count) * 64, 360))
            }
        }
        .padding(12)
        .frame(width: 340)
    }

    private func select(_ serverID: ServerID) {
        Task {
            do {
                try await applicationModel.selectActiveServer(serverID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ConnectionProfileRow: View {
    let name: String
    let address: String
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.body.weight(.medium))
                    Text(address).font(.caption).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .truncationMode(.middle)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(.horizontal, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            isHovered ? Color.primary.opacity(0.07) : isSelected ? Color.accentColor.opacity(0.08) : .clear,
            in: .rect(cornerRadius: 9)
        )
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
