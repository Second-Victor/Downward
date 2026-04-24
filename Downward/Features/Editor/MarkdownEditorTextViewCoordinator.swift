import SwiftUI
import UIKit

extension MarkdownEditorTextView {
    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        nonisolated static let deferredRerenderDelay: Duration = .milliseconds(120)
        typealias ViewportInsetsSnapshot = EditorKeyboardGeometryController.ViewportInsetsSnapshot
        private struct TextMutationContext {
            let changedRangeBeforeEdit: NSRange
            let touchedLineBreaks: Bool
        }

        @Binding private var text: String
        private let onEditorFocusChange: @MainActor (Bool) -> Void
        private let onUndoRedoAvailabilityChange: @MainActor (Bool, Bool) -> Void
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

        var hasPendingDeferredRerender: Bool {
            deferredRerenderTask != nil
        }

        init(
            text: Binding<String>,
            onEditorFocusChange: @escaping @MainActor (Bool) -> Void,
            onUndoRedoAvailabilityChange: @escaping @MainActor (Bool, Bool) -> Void
        ) {
            _text = text
            self.onEditorFocusChange = onEditorFocusChange
            self.onUndoRedoAvailabilityChange = onUndoRedoAvailabilityChange
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
            updateTypingAttributes(for: textView, font: configuration.font, resolvedTheme: configuration.resolvedTheme)

            if let textView = textView as? EditorChromeAwareTextView {
                activeTextView = textView
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
                    syntaxMode: configuration.syntaxMode,
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

        private func updateTypingAttributes(
            for textView: UITextView,
            font: UIFont,
            resolvedTheme: ResolvedEditorTheme
        ) {
            textView.typingAttributes = [
                .font: font,
                .foregroundColor: resolvedTheme.primaryText
            ]
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            let currentText = (textView.text ?? "") as NSString
            let removedRange = safeRange(range, forTextLength: currentText.length)
            let removedText = currentText.substring(with: removedRange)
            pendingTextMutationContext = TextMutationContext(
                changedRangeBeforeEdit: removedRange,
                touchedLineBreaks: removedText.containsLineBreak || text.containsLineBreak
            )
            return true
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

            guard let configuration else {
                return
            }

            let updatedConfiguration = Configuration(
                text: updatedText,
                documentIdentity: configuration.documentIdentity,
                font: configuration.font,
                resolvedTheme: configuration.resolvedTheme,
                syntaxMode: configuration.syntaxMode,
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
            guard
                isApplyingProgrammaticChange == false,
                let configuration,
                configuration.syntaxMode == .hiddenOutsideCurrentLine,
                textView.markedTextRange == nil
            else {
                return
            }

            let selectedRange = textView.selectedRange
            let revealedLineRange = renderer.revealedLineRange(
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
                syntaxMode: configuration.syntaxMode,
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

        func textViewDidBeginEditing(_ textView: UITextView) {
            if let textView = textView as? EditorChromeAwareTextView {
                activeTextView = textView
            }
            onEditorFocusChange(true)
            publishUndoRedoAvailability(for: textView)
            updateKeyboardAccessoryState(for: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
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
                return true
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
            let revealedLineRange = renderer.revealedLineRange(
                for: selectedRange,
                in: configuration.text
            )
            let attributedText = renderer.render(
                configuration: .init(
                    text: configuration.text,
                    baseFont: configuration.font,
                    resolvedTheme: configuration.resolvedTheme,
                    syntaxMode: configuration.syntaxMode,
                    revealedRange: configuration.syntaxMode == .hiddenOutsideCurrentLine
                        ? revealedLineRange
                        : nil
                )
            )

            isApplyingProgrammaticChange = true
            applyAttributedTextInPlace(attributedText, to: textView)
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
            updateTypingAttributes(for: textView, font: configuration.font, resolvedTheme: configuration.resolvedTheme)
            textView.selectedRange = safeRange(selectedRange, forTextLength: textView.textStorage.length)
            textView.setContentOffset(contentOffset, animated: false)
            isApplyingProgrammaticChange = false
            lastRevealedLineRange = revealedLineRange
            hasPendingFullDocumentRerender = false
            self.configuration = configuration
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
                        : nil
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
                        syntaxMode: latestConfiguration.syntaxMode,
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

        func configureKeyboardAccessory(for textView: EditorChromeAwareTextView, resolvedTheme: ResolvedEditorTheme) {
            if textView.keyboardAccessoryToolbarView == nil {
                let accessoryView = KeyboardAccessoryToolbarView(
                    target: self,
                    undoAction: #selector(handleAccessoryUndo),
                    redoAction: #selector(handleAccessoryRedo),
                    dismissAction: #selector(handleAccessoryDismissKeyboard),
                    resolvedTheme: resolvedTheme
                )
                textView.keyboardAccessoryToolbarView = accessoryView
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

            updateKeyboardAccessoryState(for: textView)
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
        }

        func isNearDocumentStart(in textView: UITextView, tolerance: CGFloat = 1) -> Bool {
            textView.contentOffset.y <= tolerance
                && textView.contentOffset.x <= tolerance
        }

        private func scheduleViewportResetToDocumentStart(
            in textView: UITextView,
            documentIdentity: URL
        ) {
            cancelViewportReset()
            viewportResetTask = Task { @MainActor [weak self, weak textView] in
                await Task.yield()
                guard
                    let self,
                    let textView,
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
