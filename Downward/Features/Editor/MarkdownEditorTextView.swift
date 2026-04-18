import SwiftUI
import UIKit

struct MarkdownEditorTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var topOverlayClearance: CGFloat

    let documentIdentity: URL
    let font: UIFont
    let syntaxMode: MarkdownSyntaxMode
    let isEditable: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            topOverlayClearance: $topOverlayClearance
        )
    }

    func makeUIView(context: Context) -> UITextView {
        let textStorage = NSTextStorage()
        let layoutManager = MarkdownCodeBackgroundLayoutManager()
        let textContainer = NSTextContainer(size: .zero)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = EditorChromeAwareTextView(frame: .zero, textContainer: textContainer)
        textView.backgroundColor = .clear
        textView.isOpaque = false
        textView.delegate = context.coordinator
        textView.textContainerInset = UIEdgeInsets(
            top: EditorTextViewLayout.contentTopInset,
            left: EditorTextViewLayout.horizontalInset,
            bottom: EditorTextViewLayout.bottomInset,
            right: EditorTextViewLayout.horizontalInset
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.contentInsetAdjustmentBehavior = .never
        textView.automaticallyAdjustsScrollIndicatorInsets = false
        textView.contentInset = .zero
        textView.scrollIndicatorInsets = .zero
        textView.keyboardDismissMode = .interactive
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.onViewportChromeChange = { [weak coordinator = context.coordinator] textView in
            coordinator?.updateViewportInsets(for: textView)
        }
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
        context.coordinator.updateViewportInsets(for: textView)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if let uiView = uiView as? EditorChromeAwareTextView {
            uiView.onViewportChromeChange = { [weak coordinator = context.coordinator] textView in
                coordinator?.updateViewportInsets(for: textView)
            }
        }

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
        context.coordinator.updateViewportInsets(for: uiView)
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
        @Binding private var topOverlayClearance: CGFloat

        private let renderer = MarkdownStyledTextRenderer()
        private var configuration: Configuration?
        private var isApplyingProgrammaticChange = false
        private var lastRevealedLineRange: NSRange?

        init(
            text: Binding<String>,
            topOverlayClearance: Binding<CGFloat>
        ) {
            _text = text
            _topOverlayClearance = topOverlayClearance
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

        func updateViewportInsets(for textView: UITextView) {
            let clearance = chromeOverlapTopInset(for: textView)

            var updatedTextContainerInset = textView.textContainerInset
            updatedTextContainerInset.top = EditorTextViewLayout.contentTopInset + clearance
            updatedTextContainerInset.bottom = EditorTextViewLayout.bottomInset
            updatedTextContainerInset.left = EditorTextViewLayout.horizontalInset
            updatedTextContainerInset.right = EditorTextViewLayout.horizontalInset
            if textView.textContainerInset != updatedTextContainerInset {
                textView.textContainerInset = updatedTextContainerInset
            }

            if textView.contentInset != .zero {
                textView.contentInset = .zero
            }

            var updatedScrollIndicatorInsets = textView.scrollIndicatorInsets
            updatedScrollIndicatorInsets.top = clearance
            if textView.scrollIndicatorInsets != updatedScrollIndicatorInsets {
                textView.scrollIndicatorInsets = updatedScrollIndicatorInsets
            }

            if abs(topOverlayClearance - clearance) > 0.5 {
                topOverlayClearance = clearance
            }
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

        private func chromeOverlapTopInset(for textView: UITextView) -> CGFloat {
            guard let window = textView.window else {
                return 0
            }

            let textViewFrameInWindow = textView.convert(textView.bounds, to: window)

            if
                let navigationBar = textView.nearestViewController?.navigationController?.navigationBar,
                navigationBar.isHidden == false,
                navigationBar.window === window
            {
                let navigationBarFrameInWindow = navigationBar.convert(navigationBar.bounds, to: window)
                return max(0, ceil(navigationBarFrameInWindow.maxY - textViewFrameInWindow.minY))
            }

            return max(0, ceil(window.safeAreaInsets.top - textViewFrameInWindow.minY))
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

private final class EditorChromeAwareTextView: UITextView {
    var onViewportChromeChange: ((UITextView) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onViewportChromeChange?(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onViewportChromeChange?(self)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        onViewportChromeChange?(self)
    }
}

private extension UIView {
    var nearestViewController: UIViewController? {
        var responder: UIResponder? = self

        while let currentResponder = responder {
            if let viewController = currentResponder as? UIViewController {
                return viewController
            }

            responder = currentResponder.next
        }

        return nil
    }
}
