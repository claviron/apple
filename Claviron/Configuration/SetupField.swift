import SwiftUI
#if os(macOS)
import AppKit
typealias SetupTextContentType = NSTextContentType
#else
import UIKit
typealias SetupTextContentType = UITextContentType
#endif

struct SetupField: View {
    let title: LocalizedStringResource
    @Binding var text: String
    var prompt: String?
    var isSecure: Bool
    var contentType: SetupTextContentType?
    var showsTitle: Bool
    var alignment: TextAlignment

    @State private var isFocused = false

    init(
        _ title: LocalizedStringResource,
        text: Binding<String>,
        prompt: String? = nil,
        isSecure: Bool = false,
        contentType: SetupTextContentType? = nil,
        showsTitle: Bool = true,
        alignment: TextAlignment = .leading
    ) {
        self.title = title
        _text = text
        self.prompt = prompt
        self.isSecure = isSecure
        self.contentType = contentType
        self.showsTitle = showsTitle
        self.alignment = alignment
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9)

        VStack(alignment: .leading, spacing: 6) {
            if showsTitle {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .accessibilityHidden(true)
            }

            input
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(alignment)
                .writingDirection(strategy: .layoutBased)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityLabel(Text(title))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12)
                .background {
                    shape.fill(.background)
                        .onTapGesture { isFocused = true }
                        .accessibilityHidden(true)
                }
                .overlay {
                    shape.strokeBorder(
                        isFocused ? Color.accentColor : Color.secondary.opacity(0.3),
                        lineWidth: isFocused ? 2 : 1
                    )
                    .allowsHitTesting(false)
                }
        }
    }

    @ViewBuilder
    private var input: some View {
#if os(macOS)
        SetupNativeTextField(
            text: $text,
            isFocused: $isFocused,
            title: String(localized: title),
            prompt: prompt,
            isSecure: isSecure,
            contentType: contentType,
            alignment: alignment
        )
        .frame(height: 22)
#else
        SetupMobileTextField(
            text: $text, isFocused: $isFocused, prompt: prompt,
            isSecure: isSecure, contentType: contentType
        )
#endif
    }
}

#if os(macOS)
private struct SetupNativeTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let title: String
    let prompt: String?
    let isSecure: Bool
    let contentType: NSTextContentType?
    let alignment: TextAlignment
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> NSTextField {
        let field = isSecure ? NSSecureTextField() : NSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .preferredFont(forTextStyle: .body)
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        switch alignment {
        case .leading: field.alignment = .left
        case .center: field.alignment = .center
        case .trailing: field.alignment = .right
        }
        field.baseWritingDirection = .leftToRight
        field.placeholderString = prompt
        field.contentType = contentType
        field.isEnabled = isEnabled
        field.setAccessibilityLabel(title)
        // Leave the active editor and insertion point alone for ordinary keystrokes.
        if field.stringValue != text { field.stringValue = text }
        if let editor = field.currentEditor(), editor.alignment != field.alignment {
            editor.alignment = field.alignment
        }
        if isFocused, field.currentEditor() == nil {
            field.window?.makeFirstResponder(field)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SetupNativeTextField

        init(_ parent: SetupNativeTextField) { self.parent = parent }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            field.currentEditor()?.alignment = field.alignment
            field.currentEditor()?.baseWritingDirection = .leftToRight
            parent.isFocused = true
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }
    }
}
#else
private struct SetupMobileTextField: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    let prompt: String?
    let isSecure: Bool
    let contentType: UITextContentType?
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if isSecure {
                SecureField("", text: $text, prompt: prompt.map { Text($0) })
            } else {
                TextField("", text: $text, prompt: prompt.map { Text($0) })
            }
        }
        .textContentType(contentType)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused($focused)
        .onChange(of: focused) { _, value in isFocused = value }
        .onChange(of: isFocused) { _, value in focused = value }
    }
}
#endif
