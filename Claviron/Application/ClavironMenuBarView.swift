#if os(macOS)
import AppKit
import SwiftUI

enum ClavironWindow {
    static let mainID = "main"
}

struct ClavironMenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    let presentation: MacApplicationPresentation

    var body: some View {
        Button("Open Claviron", systemImage: "macwindow") {
            presentation.showMainWindow()
            openWindow(id: ClavironWindow.mainID)
        }
        .keyboardShortcut("o", modifiers: .command)

        Divider()

        Button("Quit Claviron", systemImage: "power") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
#endif
