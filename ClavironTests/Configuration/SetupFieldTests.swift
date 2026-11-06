#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Claviron

@MainActor
struct SetupFieldTests {
    @Test
    func groupedFormKeepsTextAndPasswordInputsLeadingAndFullWidth() {
        let host = NSHostingView(rootView: Form {
            Section {
                SetupField("Server name", text: .constant("Example Server"), contentType: .organizationName)
                SetupField("Username", text: .constant("operator"), contentType: .username)
                SetupField("Password", text: .constant("example-password"), isSecure: true, contentType: .password)
            }
        }
        .formStyle(.grouped))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
        host.layoutSubtreeIfNeeded()

        let fields = textFields(in: host)
        #expect(fields.count == 3)
        #expect(fields.contains { $0 is NSSecureTextField })
        for field in fields {
            #expect(field.userInterfaceLayoutDirection == .leftToRight)
            #expect(field.alignment == .left)
            #expect(field.baseWritingDirection == .leftToRight)
            #expect(field.frame.width > host.frame.width / 2)
        }
    }

    @Test
    func unlockPasswordUsesCenteredAlignment() throws {
        let host = NSHostingView(rootView: SetupField(
            "Private key password", text: .constant("example-password"),
            isSecure: true, showsTitle: false, alignment: .center
        ))
        host.frame = NSRect(x: 0, y: 0, width: 340, height: 100)
        host.layoutSubtreeIfNeeded()
        let field = try #require(textFields(in: host).first)
        #expect(field is NSSecureTextField)
        #expect(field.alignment == .center)
        #expect(field.baseWritingDirection == .leftToRight)
    }

    @Test
    func nativeEditsUpdateTheDraftAndSwiftUIKeepsTheSameControl() throws {
        var text = ""
        func content() -> some View {
            SetupField("Username", text: Binding(get: { text }, set: { text = $0 }))
        }
        let host = NSHostingView(rootView: content())
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 100)
        host.layoutSubtreeIfNeeded()
        let field = try #require(textFields(in: host).first)

        field.stringValue = "operator"
        field.delegate?.controlTextDidChange?(
            Notification(name: NSControl.textDidChangeNotification, object: field)
        )
        #expect(text == "operator")
        host.rootView = content()
        host.layoutSubtreeIfNeeded()
        #expect(textFields(in: host).first === field)
        #expect(field.stringValue == "operator")

        text = "updated"
        host.rootView = content()
        host.layoutSubtreeIfNeeded()
        #expect(textFields(in: host).first === field)
        #expect(field.stringValue == "updated")
    }

    private func textFields(in view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] }
            ?? view.subviews.flatMap { textFields(in: $0) }
    }
}
#endif
