#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Plain-text copy to the system pasteboard on every Apple platform.
enum Clipboard {
    static func copy(_ text: String) {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#else
        UIPasteboard.general.string = text
#endif
    }
}
