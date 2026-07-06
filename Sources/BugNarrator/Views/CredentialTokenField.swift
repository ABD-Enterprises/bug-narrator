import AppKit
import SwiftUI


struct CredentialTokenField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let isDisabled: Bool
    let accessibilityLabel: String
    var revealWhenNotEditing: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> CredentialTokenTextField {
        let textField = CredentialTokenTextField()
        textField.configureCredentialInput()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.setAccessibilityLabel(accessibilityLabel)
        return textField
    }

    func updateNSView(_ textField: CredentialTokenTextField, context: Context) {
        context.coordinator.parent = self
        textField.configureCredentialInput()
        textField.placeholderString = placeholder
        textField.setAccessibilityLabel(accessibilityLabel)
        textField.isEnabled = !isDisabled

        let displayValue = (context.coordinator.isEditing || revealWhenNotEditing)
            ? text
            : Self.maskedDisplayValue(for: text)
        if textField.stringValue != displayValue {
            textField.stringValue = displayValue
        }
    }

    static func maskedDisplayValue(for value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return ""
        }

        let suffix = trimmedValue.suffix(min(4, trimmedValue.count))
        return "••••••••\(suffix)"
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CredentialTokenField
        var isEditing = false

        init(_ parent: CredentialTokenField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isEditing = true
            guard let textField = notification.object as? NSTextField else {
                return
            }

            if let editor = textField.currentEditor() {
                editor.string = parent.text
                editor.selectedRange = NSRange(location: parent.text.count, length: 0)
            } else {
                textField.stringValue = parent.text
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isEditing = false
            guard let textField = notification.object as? NSTextField else {
                return
            }

            parent.text = textField.stringValue
            textField.stringValue = CredentialTokenField.maskedDisplayValue(for: parent.text)
        }
    }
}

final class CredentialTokenTextField: NSTextField {
    func configureCredentialInput() {
        isBezeled = true
        bezelStyle = .roundedBezel
        drawsBackground = true
        isEditable = true
        isSelectable = true
        usesSingleLineMode = true
        lineBreakMode = .byTruncatingMiddle
        isAutomaticTextCompletionEnabled = false

        if #available(macOS 11.0, *) {
            contentType = nil
        }

        cell?.isScrollable = true
        cell?.lineBreakMode = .byTruncatingMiddle
    }

    override func becomeFirstResponder() -> Bool {
        configureCredentialInput()
        let didBecomeFirstResponder = super.becomeFirstResponder()
        disableEditorAssistance()
        return didBecomeFirstResponder
    }

    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        disableEditorAssistance()
    }

    private func disableEditorAssistance() {
        guard let textView = currentEditor() as? NSTextView else {
            return
        }

        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
    }
}
