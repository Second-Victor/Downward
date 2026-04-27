import SwiftUI
import UIKit

struct MarkdownEditorTextView: UIViewRepresentable {
    @Binding var text: String

    let documentIdentity: URL
    let topViewportInset: CGFloat
    let font: UIFont
    let resolvedTheme: ResolvedEditorTheme
    let syntaxMode: MarkdownSyntaxMode
    let showLineNumbers: Bool
    let isEditable: Bool
    let undoCommandToken: Int
    let redoCommandToken: Int
    let dismissKeyboardCommandToken: Int
    let onEditorFocusChange: @MainActor (Bool) -> Void
    let onUndoRedoAvailabilityChange: @MainActor (Bool, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onEditorFocusChange: onEditorFocusChange,
            onUndoRedoAvailabilityChange: onUndoRedoAvailabilityChange
        )
    }

    func makeUIView(context: Context) -> UITextView {
        let textStorage = NSTextStorage()
        let layoutManager = MarkdownCodeBackgroundLayoutManager()
        layoutManager.resolvedTheme = resolvedTheme
        let textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = EditorChromeAwareTextView(frame: .zero, textContainer: textContainer)
        textView.backgroundColor = resolvedTheme.editorBackground
        textView.isOpaque = true
        textView.tintColor = resolvedTheme.accent
        textView.delegate = context.coordinator
        // Keep the editor surface continuous under the top chrome, but derive the visible first
        // line from the current safe-area/navigation clearance in one place.
        textView.textContainerInset = UIEdgeInsets(
            top: EditorTextViewLayout.effectiveTopInset(topViewportInset: topViewportInset),
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
        textView.verticalScrollIndicatorInsets = .zero
        textView.horizontalScrollIndicatorInsets = .zero
        textView.keyboardDismissMode = .interactive
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        textView.setContentHuggingPriority(.defaultLow, for: .vertical)

        context.coordinator.configureKeyboardAccessory(for: textView, resolvedTheme: resolvedTheme)
        context.coordinator.apply(
            configuration: .init(
                text: text,
                documentIdentity: documentIdentity,
                font: font,
                resolvedTheme: resolvedTheme,
                syntaxMode: syntaxMode,
                showLineNumbers: showLineNumbers,
                isEditable: isEditable
            ),
            undoCommandToken: undoCommandToken,
            redoCommandToken: redoCommandToken,
            dismissKeyboardCommandToken: dismissKeyboardCommandToken,
            to: textView,
            force: true
        )
        return textView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? (uiView.bounds.width > 0 ? uiView.bounds.width : nil)
        let height = proposal.height ?? (uiView.bounds.height > 0 ? uiView.bounds.height : nil)

        guard let width, let height else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if let uiView = uiView as? EditorChromeAwareTextView {
            context.coordinator.configureKeyboardAccessory(for: uiView, resolvedTheme: resolvedTheme)
        }

        context.coordinator.applyTopViewportInset(topViewportInset, to: uiView)
        context.coordinator.apply(
            configuration: .init(
                text: text,
                documentIdentity: documentIdentity,
                font: font,
                resolvedTheme: resolvedTheme,
                syntaxMode: syntaxMode,
                showLineNumbers: showLineNumbers,
                isEditable: isEditable
            ),
            undoCommandToken: undoCommandToken,
            redoCommandToken: redoCommandToken,
            dismissKeyboardCommandToken: dismissKeyboardCommandToken,
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
        let resolvedTheme: ResolvedEditorTheme
        let syntaxMode: MarkdownSyntaxMode
        let showLineNumbers: Bool
        let isEditable: Bool

        init(
            text: String,
            documentIdentity: URL,
            font: UIFont,
            resolvedTheme: ResolvedEditorTheme = .default,
            syntaxMode: MarkdownSyntaxMode,
            showLineNumbers: Bool = false,
            isEditable: Bool
        ) {
            self.text = text
            self.documentIdentity = documentIdentity
            self.font = font
            self.resolvedTheme = resolvedTheme
            self.syntaxMode = syntaxMode
            self.showLineNumbers = showLineNumbers
            self.isEditable = isEditable
        }
    }
}
