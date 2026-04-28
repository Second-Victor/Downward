import SwiftUI
import UIKit

struct MarkdownEditorTextView: UIViewRepresentable {
    @Binding var text: String

    let documentIdentity: URL
    let topViewportInset: CGFloat
    let font: UIFont
    let resolvedTheme: ResolvedEditorTheme
    let chromeColorScheme: ColorScheme?
    let syntaxMode: MarkdownSyntaxMode
    let showLineNumbers: Bool
    let lineNumberOpacity: Double
    let largerHeadingText: Bool
    let tapToToggleTasks: Bool
    let isEditable: Bool
    let undoCommandToken: Int
    let redoCommandToken: Int
    let dismissKeyboardCommandToken: Int
    let onEditorFocusChange: @MainActor (Bool) -> Void
    let onUndoRedoAvailabilityChange: @MainActor (Bool, Bool) -> Void
    let onSavedDateHeaderPullDistanceChange: @MainActor (CGFloat) -> Void
    let onOpenExternalURL: @MainActor (URL) -> Void
    let onOpenLocalMarkdownLink: @MainActor (String) -> Void

    init(
        text: Binding<String>,
        documentIdentity: URL,
        topViewportInset: CGFloat,
        font: UIFont,
        resolvedTheme: ResolvedEditorTheme,
        chromeColorScheme: ColorScheme? = nil,
        syntaxMode: MarkdownSyntaxMode,
        showLineNumbers: Bool,
        lineNumberOpacity: Double,
        largerHeadingText: Bool,
        tapToToggleTasks: Bool,
        isEditable: Bool,
        undoCommandToken: Int,
        redoCommandToken: Int,
        dismissKeyboardCommandToken: Int,
        onEditorFocusChange: @escaping @MainActor (Bool) -> Void,
        onUndoRedoAvailabilityChange: @escaping @MainActor (Bool, Bool) -> Void,
        onSavedDateHeaderPullDistanceChange: @escaping @MainActor (CGFloat) -> Void = { _ in },
        onOpenExternalURL: @escaping @MainActor (URL) -> Void = { url in
            UIApplication.shared.open(url)
        },
        onOpenLocalMarkdownLink: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        _text = text
        self.documentIdentity = documentIdentity
        self.topViewportInset = topViewportInset
        self.font = font
        self.resolvedTheme = resolvedTheme
        self.chromeColorScheme = chromeColorScheme
        self.syntaxMode = syntaxMode
        self.showLineNumbers = showLineNumbers
        self.lineNumberOpacity = lineNumberOpacity
        self.largerHeadingText = largerHeadingText
        self.tapToToggleTasks = tapToToggleTasks
        self.isEditable = isEditable
        self.undoCommandToken = undoCommandToken
        self.redoCommandToken = redoCommandToken
        self.dismissKeyboardCommandToken = dismissKeyboardCommandToken
        self.onEditorFocusChange = onEditorFocusChange
        self.onUndoRedoAvailabilityChange = onUndoRedoAvailabilityChange
        self.onSavedDateHeaderPullDistanceChange = onSavedDateHeaderPullDistanceChange
        self.onOpenExternalURL = onOpenExternalURL
        self.onOpenLocalMarkdownLink = onOpenLocalMarkdownLink
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onEditorFocusChange: onEditorFocusChange,
            onUndoRedoAvailabilityChange: onUndoRedoAvailabilityChange,
            onSavedDateHeaderPullDistanceChange: onSavedDateHeaderPullDistanceChange,
            openExternalURL: onOpenExternalURL,
            openLocalMarkdownLink: onOpenLocalMarkdownLink
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
                chromeColorScheme: chromeColorScheme,
                syntaxMode: syntaxMode,
                showLineNumbers: showLineNumbers,
                lineNumberOpacity: lineNumberOpacity,
                largerHeadingText: largerHeadingText,
                tapToToggleTasks: tapToToggleTasks,
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
                chromeColorScheme: chromeColorScheme,
                syntaxMode: syntaxMode,
                showLineNumbers: showLineNumbers,
                lineNumberOpacity: lineNumberOpacity,
                largerHeadingText: largerHeadingText,
                tapToToggleTasks: tapToToggleTasks,
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
        let chromeColorScheme: ColorScheme?
        let syntaxMode: MarkdownSyntaxMode
        let showLineNumbers: Bool
        let lineNumberOpacity: Double
        let largerHeadingText: Bool
        let tapToToggleTasks: Bool
        let isEditable: Bool

        init(
            text: String,
            documentIdentity: URL,
            font: UIFont,
            resolvedTheme: ResolvedEditorTheme = .default,
            chromeColorScheme: ColorScheme? = nil,
            syntaxMode: MarkdownSyntaxMode,
            showLineNumbers: Bool = false,
            lineNumberOpacity: Double = EditorAppearancePreferences.defaultLineNumberOpacity,
            largerHeadingText: Bool = false,
            tapToToggleTasks: Bool = true,
            isEditable: Bool
        ) {
            self.text = text
            self.documentIdentity = documentIdentity
            self.font = font
            self.resolvedTheme = resolvedTheme
            self.chromeColorScheme = chromeColorScheme
            self.syntaxMode = syntaxMode
            self.showLineNumbers = showLineNumbers
            self.lineNumberOpacity = lineNumberOpacity
            self.largerHeadingText = largerHeadingText
            self.tapToToggleTasks = tapToToggleTasks
            self.isEditable = isEditable
        }
    }
}
