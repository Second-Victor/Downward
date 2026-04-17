import SwiftUI
import UIKit

struct MarkdownEditorTextView: UIViewRepresentable {
    @Binding var text: String

    let documentIdentity: URL
    let font: UIFont
    let syntaxMode: MarkdownSyntaxMode
    let isEditable: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.textContainerInset = UIEdgeInsets(
            top: EditorTextViewLayout.placeholderTopPadding,
            left: EditorTextViewLayout.horizontalInset,
            bottom: 12,
            right: EditorTextViewLayout.horizontalInset
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.apply(
            configuration: .init(
                text: text,
                documentIdentity: documentIdentity,
                font: font,
                syntaxMode: syntaxMode,
                isEditable: isEditable
            ),
            to: textView,
            force: true
        )
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.apply(
            configuration: .init(
                text: text,
                documentIdentity: documentIdentity,
                font: font,
                syntaxMode: syntaxMode,
                isEditable: isEditable
            ),
            to: uiView,
            force: false
        )
    }
}

extension MarkdownEditorTextView {
    struct Configuration: Equatable {
        let text: String
        let documentIdentity: URL
        let font: UIFont
        let syntaxMode: MarkdownSyntaxMode
        let isEditable: Bool
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding private var text: String

        private let renderer = MarkdownStyledTextRenderer()
        private var configuration: Configuration?
        private var isApplyingProgrammaticChange = false
        private var lastRevealedLineRange: NSRange?

        init(text: Binding<String>) {
            _text = text
        }

        func apply(
            configuration: Configuration,
            to textView: UITextView,
            force: Bool
        ) {
            let previousConfiguration = self.configuration
            let previousIdentity = previousConfiguration?.documentIdentity
            let liveText = textView.text ?? ""
            textView.isEditable = configuration.isEditable
            textView.isSelectable = true
            textView.accessibilityLabel = "Document Text"
            textView.accessibilityHint = "Edits the current text document."

            if previousIdentity != configuration.documentIdentity {
                textView.selectedRange = NSRange(location: 0, length: 0)
                lastRevealedLineRange = nil
            }

            if
                force == false,
                textView.isFirstResponder,
                previousIdentity == configuration.documentIdentity,
                textView.markedTextRange == nil,
                liveText != configuration.text
            {
                self.configuration = Configuration(
                    text: liveText,
                    documentIdentity: configuration.documentIdentity,
                    font: configuration.font,
                    syntaxMode: configuration.syntaxMode,
                    isEditable: configuration.isEditable
                )
                return
            }

            guard force || needsRefresh(previousConfiguration: previousConfiguration, in: textView, for: configuration) else {
                self.configuration = configuration
                return
            }

            applyRenderedText(to: textView, using: configuration)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard isApplyingProgrammaticChange == false else {
                return
            }

            let updatedText = textView.text ?? ""
            if text != updatedText {
                text = updatedText
            }

            guard let configuration else {
                return
            }

            self.configuration = Configuration(
                text: updatedText,
                documentIdentity: configuration.documentIdentity,
                font: configuration.font,
                syntaxMode: configuration.syntaxMode,
                isEditable: configuration.isEditable
            )
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard
                isApplyingProgrammaticChange == false,
                let configuration,
                configuration.syntaxMode == .hiddenOutsideCurrentLine,
                textView.markedTextRange == nil
            else {
                return
            }

            let revealedLineRange = renderer.revealedLineRange(
                for: textView.selectedRange,
                in: textView.text ?? configuration.text
            )
            guard revealedLineRange != lastRevealedLineRange else {
                return
            }

            let currentText = textView.text ?? configuration.text
            let updatedConfiguration = Configuration(
                text: currentText,
                documentIdentity: configuration.documentIdentity,
                font: configuration.font,
                syntaxMode: configuration.syntaxMode,
                isEditable: configuration.isEditable
            )
            self.configuration = updatedConfiguration
            applyRenderedText(to: textView, using: updatedConfiguration)
        }

        private func needsRefresh(
            previousConfiguration: Configuration?,
            in textView: UITextView,
            for configuration: Configuration
        ) -> Bool {
            if previousConfiguration != configuration {
                return true
            }

            return textView.text != configuration.text
        }

        private func applyRenderedText(
            to textView: UITextView,
            using configuration: Configuration
        ) {
            let selectedRange = safeSelectedRange(for: textView, text: configuration.text)
            let contentOffset = textView.contentOffset
            let revealedLineRange = renderer.revealedLineRange(
                for: selectedRange,
                in: configuration.text
            )
            let attributedText = renderer.render(
                configuration: .init(
                    text: configuration.text,
                    baseFont: configuration.font,
                    syntaxMode: configuration.syntaxMode,
                    revealedRange: configuration.syntaxMode == .hiddenOutsideCurrentLine
                        ? revealedLineRange
                        : nil
                )
            )

            isApplyingProgrammaticChange = true
            textView.attributedText = attributedText
            textView.typingAttributes = [
                .font: configuration.font,
                .foregroundColor: UIColor.label
            ]
            textView.selectedRange = safeRange(selectedRange, forTextLength: textView.textStorage.length)
            textView.setContentOffset(contentOffset, animated: false)
            isApplyingProgrammaticChange = false
            lastRevealedLineRange = revealedLineRange
            self.configuration = configuration
        }

        private func safeSelectedRange(
            for textView: UITextView,
            text: String
        ) -> NSRange {
            safeRange(textView.selectedRange, forTextLength: (text as NSString).length)
        }

        private func safeRange(
            _ range: NSRange,
            forTextLength textLength: Int
        ) -> NSRange {
            let location = min(max(range.location, 0), textLength)
            let length = min(max(range.length, 0), textLength - location)
            return NSRange(location: location, length: length)
        }
    }
}
