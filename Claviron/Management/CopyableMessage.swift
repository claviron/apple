import SwiftUI

/// A status or error message the operator can select and copy whole, so a
/// server's wording reaches a ticket or a chat exactly as it was shown.
private struct CopyableMessage: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content
            .textSelection(.enabled)
            .contextMenu {
                Button("Copy Message", systemImage: "doc.on.doc") {
                    Clipboard.copy(text)
                }
            }
    }
}

extension View {
    func copyableMessage(_ text: String) -> some View {
        modifier(CopyableMessage(text: text))
    }
}
