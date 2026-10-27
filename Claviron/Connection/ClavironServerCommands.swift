#if os(macOS)
import SwiftUI

struct ConnectionCommandAvailability: Equatable {
    let canConnect: Bool
    let canReconnect: Bool
    let canDisconnect: Bool

    init(
        canConnect: Bool,
        canReconnect: Bool,
        canDisconnect: Bool
    ) {
        self.canConnect = canConnect
        self.canReconnect = canReconnect
        self.canDisconnect = canDisconnect
    }

    init(state: ServerConnectionState) {
        switch state {
        case .disconnected:
            canConnect = true
            canReconnect = false
            canDisconnect = false
        case .connected, .failed:
            canConnect = false
            canReconnect = true
            canDisconnect = true
        case .connecting, .refreshing:
            canConnect = false
            canReconnect = false
            canDisconnect = false
        }
    }
}

struct ClavironConnectionCommandActions {
    let availability: ConnectionCommandAvailability
    let connect: () -> Void
    let reconnect: () -> Void
    let disconnect: () -> Void
}

private struct ClavironConnectionCommandsKey: FocusedValueKey {
    typealias Value = ClavironConnectionCommandActions
}

extension FocusedValues {
    var clavironConnectionCommands: ClavironConnectionCommandActions? {
        get { self[ClavironConnectionCommandsKey.self] }
        set { self[ClavironConnectionCommandsKey.self] = newValue }
    }
}

struct ClavironServerCommands: Commands {
    @FocusedValue(\.clavironConnectionCommands) private var actions
    @FocusedValue(\.clavironPageRefreshCommands) private var pageRefresh

    var body: some Commands {
        CommandMenu("Server") {
            Button("Connect") {
                actions?.connect()
            }
            .disabled(actions?.availability.canConnect != true)

            Button("Refresh") {
                pageRefresh?.refresh()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(pageRefresh?.canRefresh != true)

            Toggle("Automatically Refresh This Page", isOn: pageRefresh?.automatic ?? .constant(false))
                .disabled(pageRefresh?.canAutomaticallyRefresh != true)

            Button("Reconnect") {
                actions?.reconnect()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(actions?.availability.canReconnect != true)

            Divider()

            Button("Disconnect") {
                actions?.disconnect()
            }
            .disabled(actions?.availability.canDisconnect != true)
        }
    }
}
#endif
