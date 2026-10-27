import SwiftUI

struct ActiveServerPicker: View {
    @Bindable var applicationModel: ApplicationModel
    @State private var errorMessage: String?

    var body: some View {
        Menu {
            ForEach(applicationModel.configuration.servers) { server in
                Button {
                    select(server.id)
                } label: {
                    if server.id == applicationModel.configuration.activeServerID {
                        Label(server.name, systemImage: "checkmark")
                    } else {
                        Text(server.name)
                    }
                }
            }
        } label: {
            // One line, so the system can draw this as the compact capsule
            // it draws every other toolbar menu as. The address is not part
            // of the label: it made the control two lines tall, which is
            // what left it looking cramped and out of place.
            Label(
                applicationModel.activeServer?.name ?? "Select Server",
                systemImage: "server.rack"
            )
        }
        .help(applicationModel.activeServer?.address ?? "No server selected")
#if os(macOS)
        .pointerStyle(.link)
#endif
        .accessibilityLabel("Active server")
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
