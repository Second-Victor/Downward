import SwiftUI
import UIKit

extension MarkdownEditorTextView {
#if DEBUG
    enum RenderWork: Equatable {
        case fullDocument(characterCount: Int)
        case currentLine(characterCount: Int)
        case hiddenSyntaxVisibility(characterCount: Int)
        case deferredFullDocumentRerenderScheduled(characterCount: Int)
    }
#endif

    @MainActor
    /// Owns the `UITextView` bridge: text syncing, selection, viewport, keyboard accessory, and
    /// render scheduling. Push file/session state to `EditorViewModel` and markdown semantics to
    /// renderer/scanner/style collaborators before adding more bridge logic.
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        nonisolated static let deferredRerenderDelay: Duration = .milliseconds(120)
        typealias ViewportInsetsSnapshot = EditorKeyboardGeometryController.ViewportInsetsSnapshot
        private struct TextMutationContext {
            let changedRangeBeforeEdit: NSRange
            let touchedLineBreaks: Bool
        }

        @Binding private var text: String
        private let onEditorFocusChange: @MainActor (Bool) -> Void
        private let onUndoRedoAvailabilityChange: @MainActor (Bool, Bool) -> Void
        private let onSavedDateHeaderPullDistanceChange: @MainActor (CGFloat) -> Void
        private let renderer = MarkdownStyledTextRenderer()
        private let keyboardGeometryController = EditorKeyboardGeometryController()
        private var configuration: Configuration?
        private var isApplyingProgrammaticChange = false
        private var lastRevealedLineRange: NSRange?
        private var lastHandledUndoCommandToken: Int?
        private var lastHandledRedoCommandToken: Int?
        private var lastHandledDismissKeyboardCommandToken: Int?
        private weak var activeTextView: EditorChromeAwareTextView?
        private var pendingTextMutationContext: TextMutationContext?
        private var lastTextChangeTouchedLineBreaks = false
        private(set) var hasPendingFullDocumentRerender = false
        private var deferredRerenderTask: Task<Void, Never>?
        private var deferredRerenderGeneration = 0
        private var viewportResetTask: Task<Void, Never>?
        private var viewportResetGeneration = 0
        private weak var taskToggleTapGesture: UITapGestureRecognizer?
        private var pendingTaskToggleRange: NSRange?
        private weak var linkTapGesture: UITapGestureRecognizer?
        private var pendingLinkDestination: MarkdownLinkDestination?
        private var savedDateHeaderPullDistance: CGFloat = 0
        private let openExternalURL: @MainActor (URL) -> Void
        private let openLocalMarkdownLink: @MainActor (String) -> Void
        private let taskToggleFeedback = UIImpactFeedbackGenerator(style: .light)

        var hasPendingDeferredRerender: Bool {
            deferredRerenderTask != nil
        }

#if DEBUG
        private(set) var lastRenderWork: RenderWork?

        var hasPendingViewportReset: Bool {
            viewportResetTask != nil
        }
#endif

        init(
            text: Binding<String>,
            onEditorFocusChange: @escaping @MainActor (Bool) -> Void,
            onUndoRedoAvailabilityChange: @escaping @MainActor (Bool, Bool) -> Void,
            onSavedDateHeaderPullDistanceChange: @escaping @MainActor (CGFloat) -> Void = { _ in },
            openExternalURL: @escaping @MainActor (URL) -> Void = { url in
                UIApplication.shared.open(url)
            },
            openLocalMarkdownLink: @escaping @MainActor (String) -> Void = { _ in }
        ) {
            _text = text
            self.onEditorFocusChange = onEditorFocusChange
            self.onUndoRedoAvailabilityChange = onUndoRedoAvailabilityChange
            self.onSavedDateHeaderPullDistanceChange = onSavedDateHeaderPullDistanceChange
            self.openExternalURL = openExternalURL
            self.openLocalMarkdownLink = openLocalMarkdownLink
        }

        deinit {
            deferredRerenderTask?.cancel()
            viewportResetTask?.cancel()
        }

        func apply(
            configuration: Configuration,
            undoCommandToken: Int,
            redoCommandToken: Int,
            dismissKeyboardCommandToken: Int,
            to textView: UITextView,
            force: Bool
        ) {
            let previousConfiguration = self.configuration
            let previousIdentity = previousConfiguration?.documentIdentity
            let resetsViewportToDocumentStart = previousIdentity != nil && previousIdentity != configuration.documentIdentity
            let liveText = textView.text ?? ""
            textView.isEditable = configuration.isEditable
            textView.isSelectable = true
            textView.accessibilityLabel = "Document Text"
            textView.accessibilityHint = "Edits the current text document."
            applyResolvedTheme(configuration.resolvedTheme, to: textView)
            applyChromeColorScheme(configuration.chromeColorScheme, to: textView)
            updateTypingAttributes(for: textView, font: configuration.font, resolvedTheme: configuration.resolvedTheme)

            if let textView = textView as? EditorChromeAwareTextView {
                activeTextView = textView
                textView.applyLineNumberConfiguration(
                    showLineNumbers: configuration.showLineNumbers,
                    lineNumberOpacity: configuration.lineNumberOpacity,
                    resolvedTheme: configuration.resolvedTheme,
                    font: configuration.font
                )
                configureTaskToggleGesture(for: textView, isEnabled: configuration.tapToToggleTasks)
                configureLinkOpeningGesture(for: textView)
                configureKeyboardAccessory(for: textView, resolvedTheme: configuration.resolvedTheme)
                keyboardGeometryController.attach(
                    to: textView,
                    onKeyboardFrameApplied: { [weak self, weak textView] in
                        guard let self, let textView else {
                            return
                        }

                        self.publishUndoRedoAvailability(for: textView)
                        self.updateKeyboardAccessoryState(for: textView)
                    },
                    onKeyboardHideApplied: { [weak self, weak textView] in
                        guard let self, let textView else {
                            return
                        }

                        self.publishUndoRedoAvailability(for: textView)
                        self.updateKeyboardAccessoryState(for: textView)
                    }
                )
            }

            if previousIdentity != configuration.documentIdentity {
                cancelDeferredRerender()
                cancelViewportReset()
                textView.selectedRange = NSRange(location: 0, length: 0)
                lastRevealedLineRange = nil
                hasPendingFullDocumentRerender = false
                lastHandledUndoCommandToken = undoCommandToken
                lastHandledRedoCommandToken = redoCommandToken
                lastHandledDismissKeyboardCommandToken = dismissKeyboardCommandToken
                updateSavedDateHeaderPullDistance(0)
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
                    resolvedTheme: configuration.resolvedTheme,
                    chromeColorScheme: configuration.chromeColorScheme,
                    syntaxMode: configuration.syntaxMode,
                    showLineNumbers: configuration.showLineNumbers,
                    lineNumberOpacity: configuration.lineNumberOpacity,
                    largerHeadingText: configuration.largerHeadingText,
                    tapToToggleTasks: configuration.tapToToggleTasks,
                    isEditable: configuration.isEditable
                )
                handlePendingEditorCommands(
                    in: textView,
                    undoCommandToken: undoCommandToken,
                    redoCommandToken: redoCommandToken,
                    dismissKeyboardCommandToken: dismissKeyboardCommandToken
                )
                publishUndoRedoAvailability(for: textView)
                updateKeyboardAccessoryState(for: textView)
                return
            }

            guard force || needsRefresh(previousConfiguration: previousConfiguration, in: textView, for: configuration) else {
                self.configuration = configuration
                handlePendingEditorCommands(
                    in: textView,
                    undoCommandToken: undoCommandToken,
                    redoCommandToken: redoCommandToken,
                    dismissKeyboardCommandToken: dismissKeyboardCommandToken
                )
                publishUndoRedoAvailability(for: textView)
                updateKeyboardAccessoryState(for: textView)
                return
            }

            cancelDeferredRerender()
            applyRenderedText(
                to: textView,
                using: configuration,
                preserveViewport: resetsViewportToDocumentStart == false
            )
            handlePendingEditorCommands(
                in: textView,
                undoCommandToken: undoCommandToken,
                redoCommandToken: redoCommandToken,
                dismissKeyboardCommandToken: dismissKeyboardCommandToken
            )
            publishUndoRedoAvailability(for: textView)
            updateKeyboardAccessoryState(for: textView)
        }

        func applyTopViewportInset(_ topViewportInset: CGFloat, to textView: UITextView) {
            let wasAtDocumentStart = isNearDocumentStart(in: textView)
            var updatedTextContainerInset = textView.textContainerInset
            let resolvedTopInset = EditorTextViewLayout.effectiveTopInset(topViewportInset: topViewportInset)
            guard updatedTextContainerInset.top != resolvedTopInset else {
                return
            }

            updatedTextContainerInset.top = resolvedTopInset
            textView.textContainerInset = updatedTextContainerInset
            if wasAtDocumentStart {
                normalizeViewportToDocumentStart(in: textView)
            }
            updateSavedDateHeaderPullDistance(for: textView)
        }

        private func applyResolvedTheme(_ resolvedTheme: ResolvedEditorTheme, to textView: UITextView) {
            textView.backgroundColor = resolvedTheme.editorBackground
            textView.isOpaque = true
            textView.tintColor = resolvedTheme.accent
            if let layoutManager = textView.layoutManager as? MarkdownCodeBackgroundLayoutManager {
                layoutManager.resolvedTheme = resolvedTheme
            }
            if let textView = textView as? EditorChromeAwareTextView {
                textView.keyboardAccessoryToolbarView?.applyResolvedTheme(resolvedTheme)
            }
        }

        private func applyChromeColorScheme(_ colorScheme: ColorScheme?, to textView: UITextView) {
            guard let textView = textView as? EditorChromeAwareTextView else {
                return
            }

            textView.applyEditorChromeInterfaceStyle(colorScheme.editorUserInterfaceStyle)
        }

        private func updateTypingAttributes(
            for textView: UITextView,
            font: UIFont,
            resolvedTheme: ResolvedEditorTheme
        ) {
            textView.typingAttributes = [
                .font: font,
                .foregroundColor: resolvedTheme.primaryText
            ]
            if textView.font != font {
                textView.font = font
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            let currentText = (textView.text ?? "") as NSString
            let removedRange = safeRange(range, forTextLength: currentText.length)
            if let plan = TaskListContinuationPlan.make(
                in: currentText,
                editedRange: removedRange,
                replacementText: text
            ) {
                applyTaskListContinuation(plan, in: textView)
                return false
            }

            let removedText = currentText.substring(with: removedRange)
            pendingTextMutationContext = TextMutationContext(
                changedRangeBeforeEdit: removedRange,
                touchedLineBreaks: removedText.containsLineBreak || text.containsLineBreak
            )
            return true
        }

        private func applyTaskListContinuation(
            _ plan: TaskListContinuationPlan,
            in textView: UITextView
        ) {
            applyProgrammaticTextReplacement(
                plan.replacement,
                in: plan.replacementRange,
                selectionAfter: plan.selectionAfter,
                textView: textView,
                actionName: "Continue Task List",
                touchedLineBreaks: true
            )
        }

        func textViewDidChange(_ textView: UITextView) {
            guard isApplyingProgrammaticChange == false else {
                return
            }

            let updatedText = textView.text ?? ""
            let hadPendingFullDocumentRerender = hasPendingFullDocumentRerender
            let mutationContext = pendingTextMutationContext
            lastTextChangeTouchedLineBreaks = mutationContext?.touchedLineBreaks ?? false
            pendingTextMutationContext = nil
            text = updatedText
            if let textView = textView as? EditorChromeAwareTextView {
                textView.notePlainTextMutation()
            }

            guard let configuration else {
                return
            }

            let updatedConfiguration = Configuration(
                text: updatedText,
                documentIdentity: configuration.documentIdentity,
                font: configuration.font,
                resolvedTheme: configuration.resolvedTheme,
                chromeColorScheme: configuration.chromeColorScheme,
                syntaxMode: configuration.syntaxMode,
                showLineNumbers: configuration.showLineNumbers,
                lineNumberOpacity: configuration.lineNumberOpacity,
                largerHeadingText: configuration.largerHeadingText,
                tapToToggleTasks: configuration.tapToToggleTasks,
                isEditable: configuration.isEditable
            )
            self.configuration = updatedConfiguration

            if
                hadPendingFullDocumentRerender == false,
                let mutationContext,
                applyIncrementalLineRestyleIfPossible(
                    in: textView,
                    using: updatedConfiguration,
                    mutationContext: mutationContext
                )
            {
                publishUndoRedoAvailability(for: textView)
                updateKeyboardAccessoryState(for: textView)
                return
            }

            hasPendingFullDocumentRerender = true
            publishUndoRedoAvailability(for: textView)
            updateKeyboardAccessoryState(for: textView)
            scheduleDeferredRerender(in: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if let textView = textView as? EditorChromeAwareTextView {
                textView.setNeedsLineNumberDisplay()
            }

            guard
                isApplyingProgrammaticChange == false,
                textView.isFirstResponder,
                let configuration,
                configuration.syntaxMode == .hiddenOutsideCurrentLine,
                textView.markedTextRange == nil
            else {
                return
            }

            let selectedRange = textView.selectedRange
            let revealedLineRange = renderer.revealedSyntaxRange(
                for: selectedRange,
                in: textView.text ?? configuration.text
            )
            guard shouldRefreshRevealedLine(
                previousRange: lastRevealedLineRange,
                currentRange: revealedLineRange,
                selectionRange: selectedRange,
                textChangeTouchedLineBreaks: lastTextChangeTouchedLineBreaks
            ) else {
                lastRevealedLineRange = revealedLineRange
                lastTextChangeTouchedLineBreaks = false
                return
            }
            lastTextChangeTouchedLineBreaks = false

            let currentText = textView.text ?? configuration.text
            let updatedConfiguration = Configuration(
                text: currentText,
                documentIdentity: configuration.documentIdentity,
                font: configuration.font,
                resolvedTheme: configuration.resolvedTheme,
                chromeColorScheme: configuration.chromeColorScheme,
                syntaxMode: configuration.syntaxMode,
                showLineNumbers: configuration.showLineNumbers,
                lineNumberOpacity: configuration.lineNumberOpacity,
                largerHeadingText: configuration.largerHeadingText,
                tapToToggleTasks: configuration.tapToToggleTasks,
                isEditable: configuration.isEditable
            )

            if hasPendingFullDocumentRerender {
                self.configuration = updatedConfiguration
                scheduleDeferredRerender(in: textView)
            } else {
                updateRevealedSyntax(
                    in: textView,
                    using: updatedConfiguration,
                    previousRevealedRange: lastRevealedLineRange,
                    revealedLineRange: revealedLineRange
                )
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let textView = scrollView as? EditorChromeAwareTextView else {
                return
            }

            textView.setNeedsLineNumberDisplay()
            updateSavedDateHeaderPullDistance(for: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if let textView = textView as? EditorChromeAwareTextView {
                activeTextView = textView
                textView.setNeedsLineNumberDisplay()
            }
            textViewDidChangeSelection(textView)
            onEditorFocusChange(true)
            publishUndoRedoAvailability(for: textView)
            updateKeyboardAccessoryState(for: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if let textView = textView as? EditorChromeAwareTextView {
                textView.setNeedsLineNumberDisplay()
            }
            hideRevealedSyntaxIfNeeded(in: textView)
            onEditorFocusChange(false)
            publishUndoRedoAvailability(for: textView)
            updateKeyboardAccessoryState(for: textView)
        }

        func viewportInsetsSnapshot(for textView: UITextView) -> ViewportInsetsSnapshot {
            keyboardGeometryController.viewportInsetsSnapshot(for: textView)
        }

        func applyKeyboardOverlap(_ overlap: CGFloat, to textView: UITextView) {
            keyboardGeometryController.applyKeyboardOverlap(overlap, to: textView)
        }

        func shouldRefreshRevealedLine(
            previousRange: NSRange?,
            currentRange: NSRange?,
            selectionRange: NSRange,
            textChangeTouchedLineBreaks: Bool
        ) -> Bool {
            guard let currentRange else {
                return previousRange != nil
            }

            guard let previousRange else {
                return true
            }

            guard currentRange != previousRange else {
                return false
            }

            guard selectionRange.length == 0, textChangeTouchedLineBreaks == false else {
                return true
            }

            return previousRange.location != currentRange.location
        }

        private func needsRefresh(
            previousConfiguration: Configuration?,
            in textView: UITextView,
            for configuration: Configuration
        ) -> Bool {
            if previousConfiguration != configuration {
                return previousConfiguration?.text != configuration.text
                    || previousConfiguration?.documentIdentity != configuration.documentIdentity
                    || previousConfiguration?.font != configuration.font
                    || previousConfiguration?.resolvedTheme != configuration.resolvedTheme
                    || previousConfiguration?.syntaxMode != configuration.syntaxMode
                    || previousConfiguration?.largerHeadingText != configuration.largerHeadingText
            }

            return textView.text != configuration.text
        }

        private func applyRenderedText(
            to textView: UITextView,
            using configuration: Configuration,
            preserveViewport: Bool
        ) {
            let selectedRange = safeSelectedRange(for: textView, text: configuration.text)
            let preservedContentOffset = textView.contentOffset
            let revealedLineRange = revealedLineRange(
                in: textView,
                selectionRange: selectedRange,
                text: configuration.text
            )
            let attributedText = renderer.render(
                configuration: .init(
                    text: configuration.text,
                    baseFont: configuration.font,
                    resolvedTheme: configuration.resolvedTheme,
                    syntaxMode: configuration.syntaxMode,
                    revealedRange: configuration.syntaxMode == .hiddenOutsideCurrentLine
                        ? revealedLineRange
                        : nil,
                    largerHeadingText: configuration.largerHeadingText
                )
            )

            isApplyingProgrammaticChange = true
            applyAttributedTextInPlace(attributedText, to: textView)
            if let textView = textView as? EditorChromeAwareTextView {
                textView.notePlainTextMutation()
            }
            updateTypingAttributes(for: textView, font: configuration.font, resolvedTheme: configuration.resolvedTheme)
            textView.selectedRange = safeRange(selectedRange, forTextLength: textView.textStorage.length)
            if preserveViewport {
                textView.setContentOffset(preservedContentOffset, animated: false)
            } else {
                // A newly opened document should start from the resting top position instead of
                // inheriting whatever scroll offset the previous document or layout pass used.
                normalizeViewportToDocumentStart(in: textView)
                scheduleViewportResetToDocumentStart(
                    in: textView,
                    documentIdentity: configuration.documentIdentity
                )
            }
            isApplyingProgrammaticChange = false
            lastRevealedLineRange = revealedLineRange
            hasPendingFullDocumentRerender = false
            self.configuration = configuration
#if DEBUG
            lastRenderWork = .fullDocument(characterCount: (configuration.text as NSString).length)
#endif
        }

        private func revealedLineRange(
            in textView: UITextView,
            selectionRange: NSRange,
            text: String
        ) -> NSRange? {
            // UITextView seeds selectedRange at the document start before focus; only a real cursor
            // should reveal hidden markdown syntax for the current line.
            guard textView.isFirstResponder else {
                return nil
            }

            return renderer.revealedSyntaxRange(
                for: selectionRange,
                in: text
            )
        }

        private func hideRevealedSyntaxIfNeeded(in textView: UITextView) {
            guard
                isApplyingProgrammaticChange == false,
                configuration?.syntaxMode == .hiddenOutsideCurrentLine,
                lastRevealedLineRange != nil
            else {
                return
            }

            renderer.updateHiddenSyntaxVisibility(
                in: textView.textStorage,
                previousRevealedRange: lastRevealedLineRange,
                revealedRange: nil
            )
            lastRevealedLineRange = nil
        }

        private func updateRevealedSyntax(
            in textView: UITextView,
            using configuration: Configuration,
            previousRevealedRange: NSRange?,
            revealedLineRange: NSRange?
        ) {
            let selectedRange = safeSelectedRange(for: textView, text: configuration.text)
            let contentOffset = textView.contentOffset

            isApplyingProgrammaticChange = true
            renderer.updateHiddenSyntaxVisibility(
                in: textView.textStorage,
                previousRevealedRange: previousRevealedRange,
                revealedRange: revealedLineRange
            )
            if let textView = textView as? EditorChromeAwareTextView {
                textView.setNeedsLineNumberDisplay()
            }
            updateTypingAttributes(for: textView, font: configuration.font, resolvedTheme: configuration.resolvedTheme)
            textView.selectedRange = safeRange(selectedRange, forTextLength: textView.textStorage.length)
            textView.setContentOffset(contentOffset, animated: false)
            isApplyingProgrammaticChange = false
            lastRevealedLineRange = revealedLineRange
            hasPendingFullDocumentRerender = false
            self.configuration = configuration
#if DEBUG
            let affectedRange: NSRange
            switch (previousRevealedRange, revealedLineRange) {
            case let (previous?, current?):
                affectedRange = NSUnionRange(previous, current)
            case let (previous?, nil):
                affectedRange = previous
            case let (nil, current?):
                affectedRange = current
            case (nil, nil):
                affectedRange = NSRange(location: NSNotFound, length: 0)
            }
            lastRenderWork = .hiddenSyntaxVisibility(
                characterCount: affectedRange.location == NSNotFound ? 0 : affectedRange.length
            )
#endif
        }

        /// Update the existing text storage in place so TextKit keeps its backing objects,
        /// selection, and undo state steadier than replacing `attributedText` wholesale.
        private func applyAttributedTextInPlace(
            _ attributedText: NSAttributedString,
            to textView: UITextView
        ) {
            let textStorage = textView.textStorage
            textStorage.beginEditing()
            if textStorage.string == attributedText.string {
                // Preserve the live character buffer when only markdown presentation changed.
                // Replacing the whole attributed string here can reset UITextView undo availability.
                let fullRange = NSRange(location: 0, length: attributedText.length)
                textStorage.setAttributes(nil, range: fullRange)
                attributedText.enumerateAttributes(in: fullRange) { attributes, range, _ in
                    textStorage.setAttributes(attributes, range: range)
                }
            } else {
                textStorage.setAttributedString(attributedText)
            }
            textStorage.endEditing()
        }

        /// Same-line inline edits can restyle just the current line immediately instead of paying
        /// for a whole-document markdown pass. Broader-context edits still fall back to the
        /// deferred full rerender path below.
        private func applyIncrementalLineRestyleIfPossible(
            in textView: UITextView,
            using configuration: Configuration,
            mutationContext: TextMutationContext
        ) -> Bool {
            guard
                mutationContext.touchedLineBreaks == false,
                textView.markedTextRange == nil
            else {
                return false
            }

            let selectionRange = safeSelectedRange(for: textView, text: configuration.text)
            guard
                selectionRange.length == 0,
                let previousRevealedLineRange = lastRevealedLineRange,
                let currentLineRange = renderer.revealedLineRange(for: selectionRange, in: configuration.text),
                previousRevealedLineRange.location == currentLineRange.location
            else {
                return false
            }

            let currentText = configuration.text as NSString
            guard
                incrementalLineRestyleIsSafe(
                    for: currentLineRange,
                    in: textView.textStorage,
                    text: currentText
                )
            else {
                return false
            }

            let lineText = currentText.substring(with: currentLineRange)
            let localLineLength = (lineText as NSString).length
            let renderedLine = renderer.render(
                configuration: .init(
                    text: lineText,
                    baseFont: configuration.font,
                    resolvedTheme: configuration.resolvedTheme,
                    syntaxMode: configuration.syntaxMode,
                    revealedRange: configuration.syntaxMode == .hiddenOutsideCurrentLine
                        ? NSRange(location: 0, length: localLineLength)
                        : nil,
                    largerHeadingText: configuration.largerHeadingText
                )
            )

            let clampedLineRange = safeRange(currentLineRange, forTextLength: textView.textStorage.length)
            guard clampedLineRange.length == renderedLine.length else {
                return false
            }

            let preservedContentOffset = textView.contentOffset
            isApplyingProgrammaticChange = true
            applyAttributedFragmentInPlace(renderedLine, to: textView.textStorage, at: clampedLineRange)
            updateTypingAttributes(for: textView, font: configuration.font, resolvedTheme: configuration.resolvedTheme)
            textView.selectedRange = safeRange(selectionRange, forTextLength: textView.textStorage.length)
            textView.setContentOffset(preservedContentOffset, animated: false)
            isApplyingProgrammaticChange = false

            cancelDeferredRerender()
            lastRevealedLineRange = currentLineRange
            hasPendingFullDocumentRerender = false
            self.configuration = configuration
#if DEBUG
            lastRenderWork = .currentLine(characterCount: localLineLength)
#endif
            return true
        }

        private func applyAttributedFragmentInPlace(
            _ attributedText: NSAttributedString,
            to textStorage: NSTextStorage,
            at characterRange: NSRange
        ) {
            guard
                characterRange.length == attributedText.length,
                textStorage.attributedSubstring(from: characterRange).isEqual(attributedText) == false
            else {
                return
            }

            textStorage.beginEditing()
            textStorage.setAttributes(nil, range: characterRange)
            let localRange = NSRange(location: 0, length: attributedText.length)
            attributedText.enumerateAttributes(in: localRange) { attributes, range, _ in
                textStorage.setAttributes(
                    attributes,
                    range: NSRange(location: characterRange.location + range.location, length: range.length)
                )
            }
            textStorage.endEditing()
        }

        private func incrementalLineRestyleIsSafe(
            for lineRange: NSRange,
            in textStorage: NSTextStorage,
            text: NSString
        ) -> Bool {
            let trimmedCurrentLine = trimmedLineText(in: lineRange, text: text)
            guard
                lineContainsFenceDelimiter(trimmedCurrentLine) == false,
                isSetextUnderlineLine(trimmedCurrentLine) == false,
                lineContainsSetextUnderlineAttributes(in: lineRange, textStorage: textStorage) == false,
                isHorizontalRuleLine(trimmedCurrentLine) == false,
                lineStartsBlockquote(trimmedCurrentLine) == false,
                lineContainsBlockquoteAttributes(in: lineRange, textStorage: textStorage) == false,
                lineContainsBlockCodeBackground(in: lineRange, textStorage: textStorage) == false
            else {
                return false
            }

            if let nextLineRange = nextLineRange(after: lineRange, text: text) {
                let trimmedNextLine = trimmedLineText(in: nextLineRange, text: text)
                if isSetextUnderlineLine(trimmedNextLine) || lineContainsFenceDelimiter(trimmedNextLine) {
                    return false
                }
            }

            return true
        }

        private func trimmedLineText(
            in lineRange: NSRange,
            text: NSString
        ) -> String {
            var end = NSMaxRange(lineRange)
            while end > lineRange.location {
                let scalar = text.character(at: end - 1)
                guard scalar == 10 || scalar == 13 else {
                    break
                }
                end -= 1
            }

            return text.substring(with: NSRange(location: lineRange.location, length: end - lineRange.location))
        }

        private func nextLineRange(
            after lineRange: NSRange,
            text: NSString
        ) -> NSRange? {
            let nextLocation = NSMaxRange(lineRange)
            guard nextLocation < text.length else {
                return nil
            }

            return text.lineRange(for: NSRange(location: nextLocation, length: 0))
        }

        private func lineStartsBlockquote(_ lineText: String) -> Bool {
            lineText.trimmingCharacters(in: .whitespaces).hasPrefix(">")
        }

        private func lineContainsFenceDelimiter(_ lineText: String) -> Bool {
            let trimmed = lineText.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("```")
        }

        private func isSetextUnderlineLine(_ lineText: String) -> Bool {
            let compact = lineText.filter { $0.isWhitespace == false }
            guard compact.count >= 3, let marker = compact.first else {
                return false
            }

            return (marker == "=" || marker == "-") && Set(compact).count == 1
        }

        private func isHorizontalRuleLine(_ lineText: String) -> Bool {
            let compact = lineText.filter { $0.isWhitespace == false }
            guard compact.count >= 3, let marker = compact.first else {
                return false
            }

            return (marker == "*" || marker == "-" || marker == "_") && Set(compact).count == 1
        }

        private func lineContainsSetextUnderlineAttributes(
            in lineRange: NSRange,
            textStorage: NSTextStorage
        ) -> Bool {
            var containsSetextUnderline = false
            textStorage.enumerateAttribute(.markdownSetextHeadingUnderline, in: lineRange) { value, _, stop in
                guard value != nil else {
                    return
                }

                containsSetextUnderline = true
                stop.pointee = true
            }
            return containsSetextUnderline
        }

        private func lineContainsBlockquoteAttributes(
            in lineRange: NSRange,
            textStorage: NSTextStorage
        ) -> Bool {
            var containsBlockquote = false
            textStorage.enumerateAttribute(.markdownBlockquoteGroupID, in: lineRange) { value, _, stop in
                guard value != nil else {
                    return
                }

                containsBlockquote = true
                stop.pointee = true
            }
            return containsBlockquote
        }

        private func lineContainsBlockCodeBackground(
            in lineRange: NSRange,
            textStorage: NSTextStorage
        ) -> Bool {
            var containsBlockCode = false
            textStorage.enumerateAttribute(.markdownCodeBackgroundKind, in: lineRange) { value, _, stop in
                guard
                    let rawValue = value as? Int,
                    rawValue == MarkdownCodeBackgroundKind.block.rawValue
                else {
                    return
                }

                containsBlockCode = true
                stop.pointee = true
            }
            return containsBlockCode
        }

        /// Coalesce expensive full markdown passes so rapid typing and caret movement stay on the
        /// cheaper live TextKit path until the user briefly pauses.
        private func scheduleDeferredRerender(in textView: UITextView) {
            guard let configuration else {
                return
            }

            deferredRerenderTask?.cancel()
            deferredRerenderGeneration += 1
            let generation = deferredRerenderGeneration
            let documentIdentity = configuration.documentIdentity
#if DEBUG
            lastRenderWork = .deferredFullDocumentRerenderScheduled(
                characterCount: (configuration.text as NSString).length
            )
#endif

            deferredRerenderTask = Task { @MainActor [weak self, weak textView] in
                do {
                    try await Task.sleep(for: Self.deferredRerenderDelay)
                } catch {
                    return
                }

                guard
                    let self,
                    let textView,
                    self.deferredRerenderGeneration == generation,
                    self.hasPendingFullDocumentRerender,
                    textView.markedTextRange == nil,
                    let latestConfiguration = self.configuration,
                    latestConfiguration.documentIdentity == documentIdentity
                else {
                    return
                }

                self.deferredRerenderTask = nil
                let currentText = textView.text ?? latestConfiguration.text
                self.applyRenderedText(
                    to: textView,
                    using: Configuration(
                        text: currentText,
                        documentIdentity: latestConfiguration.documentIdentity,
                        font: latestConfiguration.font,
                        resolvedTheme: latestConfiguration.resolvedTheme,
                        chromeColorScheme: latestConfiguration.chromeColorScheme,
                        syntaxMode: latestConfiguration.syntaxMode,
                        showLineNumbers: latestConfiguration.showLineNumbers,
                        lineNumberOpacity: latestConfiguration.lineNumberOpacity,
                        largerHeadingText: latestConfiguration.largerHeadingText,
                        tapToToggleTasks: latestConfiguration.tapToToggleTasks,
                        isEditable: latestConfiguration.isEditable
                    ),
                    preserveViewport: true
                )
                self.publishUndoRedoAvailability(for: textView)
                self.updateKeyboardAccessoryState(for: textView)
            }
        }

        private func cancelDeferredRerender() {
            deferredRerenderTask?.cancel()
            deferredRerenderTask = nil
        }

        private func cancelViewportReset() {
            viewportResetTask?.cancel()
            viewportResetTask = nil
            viewportResetGeneration += 1
        }

        private func handlePendingEditorCommands(
            in textView: UITextView,
            undoCommandToken: Int,
            redoCommandToken: Int,
            dismissKeyboardCommandToken: Int
        ) {
            if let lastHandledUndoCommandToken {
                if undoCommandToken != lastHandledUndoCommandToken, textView.undoManager?.canUndo == true {
                    textView.undoManager?.undo()
                }
            } else {
                lastHandledUndoCommandToken = undoCommandToken
            }
            lastHandledUndoCommandToken = undoCommandToken

            if let lastHandledRedoCommandToken {
                if redoCommandToken != lastHandledRedoCommandToken, textView.undoManager?.canRedo == true {
                    textView.undoManager?.redo()
                }
            } else {
                lastHandledRedoCommandToken = redoCommandToken
            }
            lastHandledRedoCommandToken = redoCommandToken

            if let lastHandledDismissKeyboardCommandToken {
                if dismissKeyboardCommandToken != lastHandledDismissKeyboardCommandToken, textView.isFirstResponder {
                    textView.resignFirstResponder()
                }
            } else {
                lastHandledDismissKeyboardCommandToken = dismissKeyboardCommandToken
            }
            lastHandledDismissKeyboardCommandToken = dismissKeyboardCommandToken
        }

        private func publishUndoRedoAvailability(for textView: UITextView) {
            onUndoRedoAvailabilityChange(
                textView.isEditable && (textView.undoManager?.canUndo ?? false),
                textView.isEditable && (textView.undoManager?.canRedo ?? false)
            )
        }

        private func configureTaskToggleGesture(
            for textView: EditorChromeAwareTextView,
            isEnabled: Bool
        ) {
            if let existingGesture = taskToggleTapGesture, existingGesture.view !== textView {
                existingGesture.view?.removeGestureRecognizer(existingGesture)
                taskToggleTapGesture = nil
            }

            guard isEnabled else {
                taskToggleTapGesture?.isEnabled = false
                pendingTaskToggleRange = nil
                return
            }

            let gesture: UITapGestureRecognizer
            if let existingGesture = taskToggleTapGesture {
                gesture = existingGesture
            } else {
                gesture = UITapGestureRecognizer(target: self, action: #selector(handleTaskToggleTap(_:)))
                gesture.delegate = self
                gesture.cancelsTouchesInView = true
                textView.addGestureRecognizer(gesture)
                taskToggleTapGesture = gesture
            }
            gesture.isEnabled = true
        }

        private func configureLinkOpeningGesture(for textView: EditorChromeAwareTextView) {
            if let existingGesture = linkTapGesture, existingGesture.view !== textView {
                existingGesture.view?.removeGestureRecognizer(existingGesture)
                linkTapGesture = nil
            }

            let gesture: UITapGestureRecognizer
            if let existingGesture = linkTapGesture {
                gesture = existingGesture
            } else {
                gesture = UITapGestureRecognizer(target: self, action: #selector(handleMarkdownLinkTap(_:)))
                gesture.delegate = self
                gesture.cancelsTouchesInView = true
                textView.addGestureRecognizer(gesture)
                linkTapGesture = gesture
            }
            gesture.isEnabled = true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if
                gestureRecognizer === linkTapGesture,
                let textView = gestureRecognizer.view as? UITextView
            {
                pendingLinkDestination = resolvedMarkdownLinkDestination(
                    at: gestureRecognizer.location(in: textView),
                    in: textView
                )
                return pendingLinkDestination != nil
            }

            guard
                gestureRecognizer === taskToggleTapGesture,
                let textView = gestureRecognizer.view as? UITextView
            else {
                return true
            }

            let point = gestureRecognizer.location(in: textView)
            pendingTaskToggleRange = resolvedTaskCheckboxRange(at: point, in: textView)
            return pendingTaskToggleRange != nil
        }

        @objc
        private func handleMarkdownLinkTap(_ gesture: UITapGestureRecognizer) {
            guard
                gesture.state == .ended,
                let textView = gesture.view as? UITextView
            else {
                pendingLinkDestination = nil
                return
            }

            let destination = pendingLinkDestination
                ?? resolvedMarkdownLinkDestination(at: gesture.location(in: textView), in: textView)
            pendingLinkDestination = nil

            guard let destination else {
                return
            }

            switch destination {
            case let .external(url):
                openExternalURL(url)
            case let .local(rawDestination):
                openLocalMarkdownLink(rawDestination)
            }
        }

        @objc
        private func handleTaskToggleTap(_ gesture: UITapGestureRecognizer) {
            guard
                gesture.state == .ended,
                let textView = gesture.view as? UITextView
            else {
                pendingTaskToggleRange = nil
                return
            }

            let checkboxRange = pendingTaskToggleRange
                ?? resolvedTaskCheckboxRange(at: gesture.location(in: textView), in: textView)
            pendingTaskToggleRange = nil

            guard let checkboxRange else {
                return
            }

            toggleTaskCheckbox(in: checkboxRange, textView: textView)
        }

        private func resolvedMarkdownLinkDestination(
            at point: CGPoint,
            in textView: UITextView
        ) -> MarkdownLinkDestination? {
            guard textView.textStorage.length > 0 else {
                return nil
            }

            let textContainerPoint = CGPoint(
                x: point.x - textView.textContainerInset.left,
                y: point.y - textView.textContainerInset.top
            )
            var fraction: CGFloat = 0
            let rawCharacterIndex = textView.layoutManager.characterIndex(
                for: textContainerPoint,
                in: textView.textContainer,
                fractionOfDistanceBetweenInsertionPoints: &fraction
            )
            let characterIndex = min(max(rawCharacterIndex, 0), textView.textStorage.length - 1)
            var linkRange = NSRange(location: NSNotFound, length: 0)
            if let destination = textView.textStorage.attribute(
                .markdownLinkDestination,
                at: characterIndex,
                longestEffectiveRange: &linkRange,
                in: NSRange(location: 0, length: textView.textStorage.length)
            ) as? URL,
               pointHitsCharacterRange(linkRange, at: textContainerPoint, in: textView) {
                return .external(destination)
            }

            if let rawDestination = textView.textStorage.attribute(
                .markdownLinkRawDestination,
                at: characterIndex,
                longestEffectiveRange: &linkRange,
                in: NSRange(location: 0, length: textView.textStorage.length)
            ) as? String,
               pointHitsCharacterRange(linkRange, at: textContainerPoint, in: textView) {
                return .local(rawDestination)
            }

            return nil
        }

        private func resolvedTaskCheckboxRange(
            at point: CGPoint,
            in textView: UITextView
        ) -> NSRange? {
            guard
                configuration?.tapToToggleTasks == true,
                textView.isEditable,
                textView.textStorage.length > 0
            else {
                return nil
            }

            let textContainerPoint = CGPoint(
                x: point.x - textView.textContainerInset.left,
                y: point.y - textView.textContainerInset.top
            )
            var fraction: CGFloat = 0
            let rawCharacterIndex = textView.layoutManager.characterIndex(
                for: textContainerPoint,
                in: textView.textContainer,
                fractionOfDistanceBetweenInsertionPoints: &fraction
            )
            let characterIndex = min(max(rawCharacterIndex, 0), textView.textStorage.length - 1)
            let nsText = textView.textStorage.string as NSString
            guard
                let checkboxRange = taskCheckboxRange(in: nsText, near: characterIndex),
                textStorageHasTaskCheckboxAttribute(in: checkboxRange, textStorage: textView.textStorage),
                pointHitsCharacterRange(checkboxRange, at: textContainerPoint, in: textView)
            else {
                return nil
            }

            return checkboxRange
        }

        private func toggleTaskCheckbox(in checkboxRange: NSRange, textView: UITextView) {
            let safeCheckboxRange = safeRange(checkboxRange, forTextLength: textView.textStorage.length)
            guard safeCheckboxRange.length == 3 else {
                return
            }

            let stateLocation = safeCheckboxRange.location + 1
            let currentState = (textView.textStorage.string as NSString).character(at: stateLocation)
            let replacement: String
            if currentState == 0x20 || currentState == 0x2F {
                replacement = "x"
            } else if currentState == 0x78 || currentState == 0x58 {
                replacement = " "
            } else {
                return
            }

            let selectedRange = textView.selectedRange
            applyProgrammaticTextReplacement(
                replacement,
                in: NSRange(location: stateLocation, length: 1),
                selectionAfter: selectedRange,
                textView: textView,
                actionName: "Toggle Task",
                touchedLineBreaks: false,
                afterMutation: { [weak self] textView in
                    self?.applyTaskCheckboxPresentation(in: safeCheckboxRange, textView: textView)
                }
            )
            taskToggleFeedback.impactOccurred()
        }

        private func applyTaskCheckboxPresentation(in checkboxRange: NSRange, textView: UITextView) {
            guard
                let configuration,
                checkboxRange.location + checkboxRange.length <= textView.textStorage.length
            else {
                return
            }

            let state = (textView.textStorage.string as NSString).character(at: checkboxRange.location + 1)
            textView.textStorage.addAttributes(
                [
                    .foregroundColor: state == 0x78 || state == 0x58 || state == 0x2F
                        ? configuration.resolvedTheme.checkboxChecked
                        : configuration.resolvedTheme.checkboxUnchecked,
                    .markdownTaskCheckbox: true
                ],
                range: checkboxRange
            )
            textView.layoutManager.invalidateDisplay(forCharacterRange: checkboxRange)
        }

        private func taskCheckboxRange(in text: NSString, near characterIndex: Int) -> NSRange? {
            let lineRange = text.lineRange(
                for: NSRange(location: min(max(characterIndex, 0), text.length), length: 0)
            )
            var index = lineRange.location
            var end = NSMaxRange(lineRange)
            while end > index, text.character(at: end - 1).isMarkdownLineBreak {
                end -= 1
            }

            while index < end, text.character(at: index).isMarkdownHorizontalWhitespace {
                index += 1
            }

            guard index < end else {
                return nil
            }

            let marker = text.character(at: index)
            if marker == 0x2A || marker == 0x2B || marker == 0x2D {
                index += 1
            } else {
                let numberStart = index
                while index < end, text.character(at: index).isMarkdownDigit {
                    index += 1
                }
                guard index > numberStart, index < end, text.character(at: index) == 0x2E else {
                    return nil
                }
                index += 1
            }

            guard index < end, text.character(at: index).isMarkdownHorizontalWhitespace else {
                return nil
            }
            while index < end, text.character(at: index).isMarkdownHorizontalWhitespace {
                index += 1
            }

            guard index + 2 < end else {
                return nil
            }

            let openBracket = text.character(at: index)
            let state = text.character(at: index + 1)
            let closeBracket = text.character(at: index + 2)
            guard
                openBracket == 0x5B,
                closeBracket == 0x5D,
                state == 0x20 || state == 0x78 || state == 0x58 || state == 0x2F
            else {
                return nil
            }

            return NSRange(location: index, length: 3)
        }

        private func textStorageHasTaskCheckboxAttribute(
            in checkboxRange: NSRange,
            textStorage: NSTextStorage
        ) -> Bool {
            var hasAttribute = false
            textStorage.enumerateAttribute(.markdownTaskCheckbox, in: checkboxRange) { value, _, stop in
                guard value != nil else {
                    return
                }

                hasAttribute = true
                stop.pointee = true
            }
            return hasAttribute
        }

        private func pointHitsCharacterRange(
            _ range: NSRange,
            at point: CGPoint,
            in textView: UITextView
        ) -> Bool {
            textView.layoutManager.ensureLayout(for: textView.textContainer)
            let glyphRange = textView.layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            guard glyphRange.length > 0 else {
                return false
            }

            var didHit = false
            textView.layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textView.textContainer
            ) { rect, _ in
                if rect.insetBy(dx: -8, dy: -6).contains(point) {
                    didHit = true
                }
            }
            return didHit
        }

#if DEBUG
        func resolvedTaskCheckboxRangeForTesting(at point: CGPoint, in textView: UITextView) -> NSRange? {
            resolvedTaskCheckboxRange(at: point, in: textView)
        }

        func toggleTaskCheckboxForTesting(in checkboxRange: NSRange, textView: UITextView) {
            toggleTaskCheckbox(in: checkboxRange, textView: textView)
        }

        func resolvedMarkdownLinkDestinationForTesting(at point: CGPoint, in textView: UITextView) -> MarkdownLinkDestination? {
            resolvedMarkdownLinkDestination(at: point, in: textView)
        }

        func openMarkdownLinkForTesting(at point: CGPoint, in textView: UITextView) {
            guard let destination = resolvedMarkdownLinkDestination(at: point, in: textView) else {
                return
            }

            switch destination {
            case let .external(url):
                openExternalURL(url)
            case let .local(rawDestination):
                openLocalMarkdownLink(rawDestination)
            }
        }

        func applyInlineMarkdownFormatForTesting(marker: String, in textView: UITextView) {
            applyInlineMarkdownFormat(marker: marker, in: textView)
        }

        func applyCodeBlockMarkdownFormatForTesting(in textView: UITextView) {
            applyCodeBlockMarkdownFormat(in: textView)
        }

        func applyLineMarkdownPrefixForTesting(_ prefix: String, in textView: UITextView) {
            applyLineMarkdownPrefix(prefix, in: textView)
        }

        func insertMarkdownLinkForTesting(in textView: UITextView) {
            insertMarkdownLink(in: textView)
        }

        func insertMarkdownImageForTesting(in textView: UITextView) {
            insertMarkdownImage(in: textView)
        }
#endif

        func configureKeyboardAccessory(for textView: EditorChromeAwareTextView, resolvedTheme: ResolvedEditorTheme) {
            if textView.keyboardAccessoryToolbarView == nil {
                let accessoryView = KeyboardAccessoryToolbarView(
                    target: self,
                    undoAction: #selector(handleAccessoryUndo),
                    redoAction: #selector(handleAccessoryRedo),
                    dismissAction: #selector(handleAccessoryDismissKeyboard),
                    resolvedTheme: resolvedTheme,
                    formatMenu: makeFormattingMenu()
                )
                textView.keyboardAccessoryToolbarView = accessoryView
                textView.formatAccessoryItem = accessoryView.formatButton
                textView.undoAccessoryItem = accessoryView.undoButton
                textView.redoAccessoryItem = accessoryView.redoButton
                textView.dismissAccessoryItem = accessoryView.dismissButton
                textView.inputAccessoryView = accessoryView

                let assistantItem = textView.inputAssistantItem
                assistantItem.leadingBarButtonGroups = []
                assistantItem.trailingBarButtonGroups = []

                if textView.isFirstResponder {
                    textView.reloadInputViews()
                }
            }

            textView.keyboardAccessoryToolbarView?.applyResolvedTheme(resolvedTheme)
            textView.keyboardAccessoryToolbarView?.applyChromeInterfaceStyle(textView.overrideUserInterfaceStyle)

            updateKeyboardAccessoryState(for: textView)
        }

        private func makeFormattingMenu() -> UIMenu {
            // UIKit presents nested keyboard menus from the anchor upward; keep the prototype's
            // order by listing the top visual item last inside each menu.
            UIMenu(children: [
                UIAction(title: "Image", image: UIImage(systemName: "photo")) { [weak self] _ in
                    self?.insertMarkdownImage()
                },
                UIAction(title: "Link", image: UIImage(systemName: "link")) { [weak self] _ in
                    self?.insertMarkdownLink()
                },
                UIMenu(
                    title: "Code",
                    image: UIImage(systemName: "chevron.left.forwardslash.chevron.right"),
                    children: [
                        UIAction(title: "Code Block", image: UIImage(systemName: "curlybraces")) { [weak self] _ in
                            self?.applyCodeBlockMarkdownFormat()
                        },
                        UIAction(title: "Code Line", image: UIImage(systemName: "chevron.left.forwardslash.chevron.right")) { [weak self] _ in
                            self?.applyInlineMarkdownFormat(marker: "`")
                        },
                    ]
                ),
                UIAction(title: "Task", image: UIImage(systemName: "checklist")) { [weak self] _ in
                    self?.applyLineMarkdownPrefix("- [ ] ")
                },
                UIAction(title: "Strikethrough", image: UIImage(systemName: "strikethrough")) { [weak self] _ in
                    self?.applyInlineMarkdownFormat(marker: "~~")
                },
                UIAction(title: "Italic", image: UIImage(systemName: "italic")) { [weak self] _ in
                    self?.applyInlineMarkdownFormat(marker: "*")
                },
                UIAction(title: "Bold", image: UIImage(systemName: "bold")) { [weak self] _ in
                    self?.applyInlineMarkdownFormat(marker: "**")
                },
                UIMenu(
                    title: "Header",
                    image: UIImage(systemName: "textformat.size"),
                    children: (1...6).reversed().map { level in
                        UIAction(title: "H\(level)", image: UIImage(systemName: "\(level).square")) { [weak self] _ in
                            self?.applyLineMarkdownPrefix(String(repeating: "#", count: level) + " ")
                        }
                    }
                ),
            ])
        }

        private func updateKeyboardAccessoryState(for textView: UITextView) {
            guard let textView = textView as? EditorChromeAwareTextView else {
                return
            }

            textView.keyboardAccessoryToolbarView?.update(
                canUndo: textView.isEditable && (textView.undoManager?.canUndo ?? false),
                canRedo: textView.isEditable && (textView.undoManager?.canRedo ?? false),
                canDismiss: textView.isFirstResponder
            )
        }

        @objc
        private func handleAccessoryUndo() {
            guard let textView = activeTextView else {
                return
            }

            if textView.isEditable, textView.undoManager?.canUndo == true {
                textView.undoManager?.undo()
            }
            publishUndoRedoAvailability(for: textView)
            updateKeyboardAccessoryState(for: textView)
        }

        @objc
        private func handleAccessoryRedo() {
            guard let textView = activeTextView else {
                return
            }

            if textView.isEditable, textView.undoManager?.canRedo == true {
                textView.undoManager?.redo()
            }
            publishUndoRedoAvailability(for: textView)
            updateKeyboardAccessoryState(for: textView)
        }

        @objc
        private func handleAccessoryDismissKeyboard() {
            guard let textView = activeTextView else {
                return
            }

            if textView.isFirstResponder {
                textView.resignFirstResponder()
            }
            publishUndoRedoAvailability(for: textView)
            updateKeyboardAccessoryState(for: textView)
        }

        private func applyInlineMarkdownFormat(marker: String) {
            guard let textView = activeTextView else {
                return
            }

            applyInlineMarkdownFormat(marker: marker, in: textView)
        }

        private func applyInlineMarkdownFormat(marker: String, in textView: UITextView) {
            guard
                textView.isEditable,
                let currentText = textView.text as NSString?
            else {
                return
            }

            let selectedRange = safeRange(textView.selectedRange, forTextLength: currentText.length)
            let markerLength = (marker as NSString).length

            if selectedRange.length > 0,
               selectedRange.location >= markerLength,
               selectedRange.location + selectedRange.length + markerLength <= currentText.length {
                let before = currentText.substring(
                    with: NSRange(location: selectedRange.location - markerLength, length: markerLength)
                )
                let after = currentText.substring(
                    with: NSRange(location: NSMaxRange(selectedRange), length: markerLength)
                )
                if before == marker, after == marker {
                    let expandedRange = NSRange(
                        location: selectedRange.location - markerLength,
                        length: selectedRange.length + markerLength * 2
                    )
                    let content = currentText.substring(with: selectedRange)
                    applyProgrammaticTextReplacement(
                        content,
                        in: expandedRange,
                        selectionAfter: NSRange(
                            location: selectedRange.location - markerLength,
                            length: selectedRange.length
                        ),
                        textView: textView,
                        actionName: "Markdown Format"
                    )
                    return
                }
            }

            let selectedText = currentText.substring(with: selectedRange)
            let plan = MarkdownInlineFormatPlan.make(marker: marker, selectedText: selectedText)
            applyProgrammaticTextReplacement(
                plan.replacement,
                in: selectedRange,
                selectionAfter: NSRange(
                    location: selectedRange.location + plan.selectedRangeInReplacement.location,
                    length: plan.selectedRangeInReplacement.length
                ),
                textView: textView,
                actionName: "Markdown Format"
            )
        }

        private func applyCodeBlockMarkdownFormat() {
            guard let textView = activeTextView else {
                return
            }

            applyCodeBlockMarkdownFormat(in: textView)
        }

        private func applyCodeBlockMarkdownFormat(in textView: UITextView) {
            guard
                textView.isEditable,
                let currentText = textView.text as NSString?
            else {
                return
            }

            let selectedRange = safeRange(textView.selectedRange, forTextLength: currentText.length)
            let selectedText = currentText.substring(with: selectedRange)
            let plan = MarkdownCodeBlockPlan.make(selectedText: selectedText)
            applyProgrammaticTextReplacement(
                plan.replacement,
                in: selectedRange,
                selectionAfter: NSRange(
                    location: selectedRange.location + plan.selectedRangeInReplacement.location,
                    length: plan.selectedRangeInReplacement.length
                ),
                textView: textView,
                actionName: "Markdown Format"
            )
        }

        private func applyLineMarkdownPrefix(_ prefix: String) {
            guard let textView = activeTextView else {
                return
            }

            applyLineMarkdownPrefix(prefix, in: textView)
        }

        private func applyLineMarkdownPrefix(_ prefix: String, in textView: UITextView) {
            guard
                textView.isEditable,
                let currentText = textView.text as NSString?
            else {
                return
            }

            let selectedRange = safeRange(textView.selectedRange, forTextLength: currentText.length)
            let targetRange = expandedLineRange(in: currentText, for: selectedRange)
            let selectedRangeInTarget = NSRange(
                location: max(0, selectedRange.location - targetRange.location),
                length: selectedRange.length
            )
            let selectedText = currentText.substring(with: targetRange)
            let plan = MarkdownLinePrefixPlan.make(
                prefix: prefix,
                selectedText: selectedText,
                selectedRangeInSelectedText: selectedRangeInTarget
            )
            let prefixLength = (prefix as NSString).length
            let replacementLength = (plan.replacement as NSString).length
            let selectionAfter: NSRange

            if selectedRange.length == 0 {
                if let selectedRangeInReplacement = plan.selectedRangeInReplacement {
                    selectionAfter = NSRange(
                        location: targetRange.location + selectedRangeInReplacement.location,
                        length: selectedRangeInReplacement.length
                    )
                } else {
                    selectionAfter = NSRange(
                        location: min(targetRange.location + prefixLength, targetRange.location + replacementLength),
                        length: 0
                    )
                }
            } else {
                selectionAfter = NSRange(location: targetRange.location, length: replacementLength)
            }

            applyProgrammaticTextReplacement(
                plan.replacement,
                in: targetRange,
                selectionAfter: selectionAfter,
                textView: textView,
                actionName: "Markdown Format"
            )
        }

        private func insertMarkdownLink() {
            guard let textView = activeTextView else {
                return
            }

            insertMarkdownLink(in: textView)
        }

        private func insertMarkdownLink(in textView: UITextView) {
            guard
                textView.isEditable,
                let currentText = textView.text as NSString?
            else {
                return
            }

            let selectedRange = safeRange(textView.selectedRange, forTextLength: currentText.length)
            let selectedText = currentText.substring(with: selectedRange)
            let plan = MarkdownLinkInsertionPlan.make(forSelectedText: selectedText)
            applyProgrammaticTextReplacement(
                plan.replacement,
                in: selectedRange,
                selectionAfter: NSRange(
                    location: selectedRange.location + plan.selectedRangeInReplacement.location,
                    length: plan.selectedRangeInReplacement.length
                ),
                textView: textView,
                actionName: "Markdown Format"
            )
        }

        private func insertMarkdownImage() {
            guard let textView = activeTextView else {
                return
            }

            insertMarkdownImage(in: textView)
        }

        private func insertMarkdownImage(in textView: UITextView) {
            guard
                textView.isEditable,
                let currentText = textView.text as NSString?
            else {
                return
            }

            let selectedRange = safeRange(textView.selectedRange, forTextLength: currentText.length)
            let selectedText = currentText.substring(with: selectedRange)
            let plan = MarkdownImageInsertionPlan.make(forSelectedText: selectedText)
            applyProgrammaticTextReplacement(
                plan.replacement,
                in: selectedRange,
                selectionAfter: NSRange(
                    location: selectedRange.location + plan.selectedRangeInReplacement.location,
                    length: plan.selectedRangeInReplacement.length
                ),
                textView: textView,
                actionName: "Markdown Format"
            )
        }

        private func applyProgrammaticTextReplacement(
            _ replacement: String,
            in range: NSRange,
            selectionAfter: NSRange,
            textView: UITextView,
            actionName: String,
            registersUndo: Bool = true,
            touchedLineBreaks: Bool? = nil,
            afterMutation: ((UITextView) -> Void)? = nil
        ) {
            guard let currentText = textView.text as NSString? else {
                return
            }

            let safeReplacementRange = safeRange(range, forTextLength: currentText.length)
            let originalText = currentText.substring(with: safeReplacementRange)
            let originalSelection = safeRange(textView.selectedRange, forTextLength: currentText.length)
            let replacementLength = (replacement as NSString).length
            let undoReplacementRange = NSRange(location: safeReplacementRange.location, length: replacementLength)
            let safeSelectionAfter = safeRange(
                selectionAfter,
                forTextLength: currentText.length - safeReplacementRange.length + replacementLength
            )
            guard currentText.substring(with: safeReplacementRange) != replacement
                || originalSelection != safeSelectionAfter
            else {
                return
            }

            if registersUndo, let undoManager = textView.undoManager {
                undoManager.registerUndo(withTarget: self) { target in
                    target.applyProgrammaticTextReplacement(
                        originalText,
                        in: undoReplacementRange,
                        selectionAfter: originalSelection,
                        textView: textView,
                        actionName: actionName,
                        touchedLineBreaks: touchedLineBreaks,
                        afterMutation: afterMutation
                    )
                }
                undoManager.setActionName(actionName)
            }

            let removedText = currentText.substring(with: safeReplacementRange)
            pendingTextMutationContext = TextMutationContext(
                changedRangeBeforeEdit: safeReplacementRange,
                touchedLineBreaks: touchedLineBreaks
                    ?? (replacement.containsLineBreak || removedText.containsLineBreak)
            )
            textView.textStorage.replaceCharacters(in: safeReplacementRange, with: replacement)
            afterMutation?(textView)
            textView.selectedRange = safeSelectionAfter
            textViewDidChange(textView)
            textViewDidChangeSelection(textView)
            publishUndoRedoAvailability(for: textView)
            updateKeyboardAccessoryState(for: textView)
        }

        private func expandedLineRange(in text: NSString, for selectedRange: NSRange) -> NSRange {
            guard text.length > 0 else {
                return NSRange(location: 0, length: 0)
            }

            if selectedRange.length == 0,
               selectedRange.location == text.length,
               text.character(at: text.length - 1) == 0x0A {
                return NSRange(location: text.length, length: 0)
            }

            let safeLocation = min(selectedRange.location, max(text.length - 1, 0))
            let startLine = text.lineRange(for: NSRange(location: safeLocation, length: 0))

            if selectedRange.length == 0 {
                return startLine
            }

            let endLocation = min(NSMaxRange(selectedRange) - 1, text.length - 1)
            let endLine = text.lineRange(for: NSRange(location: endLocation, length: 0))
            return NSRange(
                location: startLine.location,
                length: NSMaxRange(endLine) - startLine.location
            )
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

        func normalizeViewportToDocumentStart(in textView: UITextView) {
            textView.layoutIfNeeded()
            textView.setContentOffset(.zero, animated: false)
            updateSavedDateHeaderPullDistance(0)
        }

        func isNearDocumentStart(in textView: UITextView, tolerance: CGFloat = 1) -> Bool {
            textView.contentOffset.y <= tolerance
                && textView.contentOffset.x <= tolerance
        }

        private func updateSavedDateHeaderPullDistance(for scrollView: UIScrollView) {
            updateSavedDateHeaderPullDistance(max(0, -scrollView.contentOffset.y))
        }

        private func updateSavedDateHeaderPullDistance(_ pullDistance: CGFloat) {
            guard abs(savedDateHeaderPullDistance - pullDistance) > 0.5 else {
                return
            }

            savedDateHeaderPullDistance = pullDistance
            onSavedDateHeaderPullDistanceChange(pullDistance)
        }

        private func scheduleViewportResetToDocumentStart(
            in textView: UITextView,
            documentIdentity: URL
        ) {
            cancelViewportReset()
            let generation = viewportResetGeneration
            viewportResetTask = Task { @MainActor [weak self, weak textView] in
                await Task.yield()
                guard
                    let self,
                    let textView,
                    Task.isCancelled == false,
                    self.viewportResetGeneration == generation,
                    self.configuration?.documentIdentity == documentIdentity
                else {
                    return
                }

                self.normalizeViewportToDocumentStart(in: textView)
                self.viewportResetTask = nil
            }
        }
    }
}

private extension String {
    var containsLineBreak: Bool {
        contains("\n") || contains("\r")
    }
}

private extension Optional where Wrapped == ColorScheme {
    var editorUserInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .none:
            .unspecified
        case let .some(colorScheme):
            switch colorScheme {
            case .dark:
                .dark
            case .light:
                .light
            @unknown default:
                .unspecified
            }
        }
    }
}

private extension unichar {
    var isMarkdownDigit: Bool {
        self >= 0x30 && self <= 0x39
    }

    var isMarkdownHorizontalWhitespace: Bool {
        self == 0x20 || self == 0x09
    }

    var isMarkdownLineBreak: Bool {
        self == 0x0A || self == 0x0D
    }
}
