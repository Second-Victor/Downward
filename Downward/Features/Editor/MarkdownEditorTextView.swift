import SwiftUI
import UIKit

struct MarkdownEditorTextView: UIViewRepresentable {
    @Binding var text: String

    let documentIdentity: URL
    let font: UIFont
    let syntaxMode: MarkdownSyntaxMode
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
        let textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = EditorChromeAwareTextView(frame: .zero, textContainer: textContainer)
        textView.backgroundColor = .clear
        textView.isOpaque = false
        textView.delegate = context.coordinator
        // Top chrome clearance is owned by the surrounding SwiftUI container. The text view keeps
        // only its own internal padding and keyboard-driven bottom scroll insets.
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
        textView.verticalScrollIndicatorInsets = .zero
        textView.horizontalScrollIndicatorInsets = .zero
        textView.keyboardDismissMode = .interactive
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        textView.setContentHuggingPriority(.defaultLow, for: .vertical)
        context.coordinator.configureKeyboardAccessory(for: textView)
        context.coordinator.apply(
            configuration: .init(
                text: text,
                documentIdentity: documentIdentity,
                font: font,
                syntaxMode: syntaxMode,
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
            context.coordinator.configureKeyboardAccessory(for: uiView)
        }

        context.coordinator.apply(
            configuration: .init(
                text: text,
                documentIdentity: documentIdentity,
                font: font,
                syntaxMode: syntaxMode,
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
        let syntaxMode: MarkdownSyntaxMode
        let isEditable: Bool
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        nonisolated static let deferredRerenderDelay: Duration = .milliseconds(120)

        struct ViewportInsetsSnapshot: Equatable {
            let keyboardOverlapInset: CGFloat
            let contentInsetBottom: CGFloat
            let verticalScrollIndicatorInsetBottom: CGFloat
        }

        @Binding private var text: String
        private let onEditorFocusChange: @MainActor (Bool) -> Void
        private let onUndoRedoAvailabilityChange: @MainActor (Bool, Bool) -> Void
        private let renderer = MarkdownStyledTextRenderer()
        private var configuration: Configuration?
        private var isApplyingProgrammaticChange = false
        private var lastRevealedLineRange: NSRange?
        private var lastHandledUndoCommandToken: Int?
        private var lastHandledRedoCommandToken: Int?
        private var lastHandledDismissKeyboardCommandToken: Int?
        private weak var activeTextView: EditorChromeAwareTextView?
        private var isObservingKeyboard = false
        private var pendingTextChangeTouchesLineBreaks = false
        private var lastTextChangeTouchedLineBreaks = false
        private var hasUnrenderedTextMutation = false
        private var deferredRerenderTask: Task<Void, Never>?
        private var deferredRerenderGeneration = 0

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
            if isObservingKeyboard {
                NotificationCenter.default.removeObserver(self)
            }
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
            let liveText = textView.text ?? ""
            textView.isEditable = configuration.isEditable
            textView.isSelectable = true
            textView.accessibilityLabel = "Document Text"
            textView.accessibilityHint = "Edits the current text document."

            if let textView = textView as? EditorChromeAwareTextView {
                activeTextView = textView
                configureKeyboardAccessory(for: textView)
                subscribeToKeyboardNotificationsIfNeeded()
            }

            if previousIdentity != configuration.documentIdentity {
                cancelDeferredRerender()
                textView.selectedRange = NSRange(location: 0, length: 0)
                lastRevealedLineRange = nil
                hasUnrenderedTextMutation = false
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
            applyRenderedText(to: textView, using: configuration)
            handlePendingEditorCommands(
                in: textView,
                undoCommandToken: undoCommandToken,
                redoCommandToken: redoCommandToken,
                dismissKeyboardCommandToken: dismissKeyboardCommandToken
            )
            publishUndoRedoAvailability(for: textView)
            updateKeyboardAccessoryState(for: textView)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            let currentText = (textView.text ?? "") as NSString
            let removedRange = safeRange(range, forTextLength: currentText.length)
            let removedText = currentText.substring(with: removedRange)
            pendingTextChangeTouchesLineBreaks = removedText.containsLineBreak || text.containsLineBreak
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard isApplyingProgrammaticChange == false else {
                return
            }

            let updatedText = textView.text ?? ""
            lastTextChangeTouchedLineBreaks = pendingTextChangeTouchesLineBreaks
            hasUnrenderedTextMutation = true
            pendingTextChangeTouchesLineBreaks = false
            text = updatedText

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
                syntaxMode: configuration.syntaxMode,
                isEditable: configuration.isEditable
            )

            if hasUnrenderedTextMutation {
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

        /// Match the prototype behavior: reserve the full keyboard overlap in the scroll view
        /// insets and let the transparent accessory simply overlay the text view content.
        func viewportInsetsSnapshot(for textView: UITextView) -> ViewportInsetsSnapshot {
            let keyboardOverlapInset = (textView as? EditorChromeAwareTextView)?.keyboardOverlapInset ?? 0
            let contentInsetBottom = max(0, keyboardOverlapInset)

            return ViewportInsetsSnapshot(
                keyboardOverlapInset: keyboardOverlapInset,
                contentInsetBottom: contentInsetBottom,
                verticalScrollIndicatorInsetBottom: contentInsetBottom
            )
        }

        func updateKeyboardBottomInsets(for textView: UITextView) {
            let viewportInsetsSnapshot = viewportInsetsSnapshot(for: textView)

            var updatedContentInset = textView.contentInset
            updatedContentInset.bottom = viewportInsetsSnapshot.contentInsetBottom
            if textView.contentInset != updatedContentInset {
                textView.contentInset = updatedContentInset
            }

            var updatedVerticalScrollIndicatorInsets = textView.verticalScrollIndicatorInsets
            updatedVerticalScrollIndicatorInsets.bottom = viewportInsetsSnapshot.verticalScrollIndicatorInsetBottom
            if textView.verticalScrollIndicatorInsets != updatedVerticalScrollIndicatorInsets {
                textView.verticalScrollIndicatorInsets = updatedVerticalScrollIndicatorInsets
            }
        }

        func applyKeyboardOverlap(_ overlap: CGFloat, to textView: UITextView) {
            if let textView = textView as? EditorChromeAwareTextView {
                textView.keyboardOverlapInset = max(0, overlap)
            }
            updateKeyboardBottomInsets(for: textView)
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
            applyAttributedTextInPlace(attributedText, to: textView)
            textView.typingAttributes = [
                .font: configuration.font,
                .foregroundColor: UIColor.label
            ]
            textView.selectedRange = safeRange(selectedRange, forTextLength: textView.textStorage.length)
            textView.setContentOffset(contentOffset, animated: false)
            isApplyingProgrammaticChange = false
            lastRevealedLineRange = revealedLineRange
            hasUnrenderedTextMutation = false
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

        /// Update the existing text storage in place so TextKit keeps its backing objects,
        /// selection, and undo state steadier than replacing `attributedText` wholesale.
        private func applyAttributedTextInPlace(
            _ attributedText: NSAttributedString,
            to textView: UITextView
        ) {
            let textStorage = textView.textStorage
            guard textStorage.isEqual(attributedText) == false else {
                return
            }

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

        /// Coalesce expensive full markdown passes so rapid typing and caret movement stay on
        /// the cheaper live TextKit path until the user briefly pauses.
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
                    self.hasUnrenderedTextMutation,
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
                        syntaxMode: latestConfiguration.syntaxMode,
                        isEditable: latestConfiguration.isEditable
                    )
                )
                self.publishUndoRedoAvailability(for: textView)
                self.updateKeyboardAccessoryState(for: textView)
            }
        }

        private func cancelDeferredRerender() {
            deferredRerenderTask?.cancel()
            deferredRerenderTask = nil
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

        func configureKeyboardAccessory(for textView: EditorChromeAwareTextView) {
            if textView.keyboardAccessoryToolbarView == nil {
                let accessoryView = KeyboardAccessoryToolbarView(
                    target: self,
                    undoAction: #selector(handleAccessoryUndo),
                    redoAction: #selector(handleAccessoryRedo),
                    dismissAction: #selector(handleAccessoryDismissKeyboard)
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

        private func subscribeToKeyboardNotificationsIfNeeded() {
            guard isObservingKeyboard == false else {
                return
            }

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillChangeFrame(_:)),
                name: UIResponder.keyboardWillChangeFrameNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillHide(_:)),
                name: UIResponder.keyboardWillHideNotification,
                object: nil
            )
            isObservingKeyboard = true
        }

        @objc
        private func keyboardWillChangeFrame(_ notification: Notification) {
            guard
                let textView = activeTextView,
                let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                let window = textView.window
            else {
                return
            }

            let keyboardFrameInView = textView.convert(endFrame, from: window.screen.coordinateSpace)
            let overlap = max(0, textView.bounds.maxY - keyboardFrameInView.minY)

            animateAlongsideKeyboard(notification) {
                self.applyKeyboardOverlap(overlap, to: textView)
            } completion: {
                self.applyKeyboardOverlap(overlap, to: textView)
                self.scrollToCaret(in: textView)
                self.updateKeyboardAccessoryState(for: textView)
            }
        }

        @objc
        private func keyboardWillHide(_ notification: Notification) {
            guard let textView = activeTextView else {
                return
            }

            animateAlongsideKeyboard(notification) {
                self.applyKeyboardOverlap(0, to: textView)
            } completion: {
                self.applyKeyboardOverlap(0, to: textView)
                self.updateKeyboardAccessoryState(for: textView)
            }
        }

        private func animateAlongsideKeyboard(
            _ notification: Notification,
            animations: @escaping () -> Void,
            completion: @escaping () -> Void = {}
        ) {
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
            let curveRaw = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 0
            let options = UIView.AnimationOptions(rawValue: curveRaw << 16)

            UIView.animate(withDuration: duration, delay: 0, options: options) {
                animations()
            } completion: { _ in
                completion()
            }
        }

        private func scrollToCaret(in textView: UITextView) {
            guard let selectedRange = textView.selectedTextRange else {
                return
            }

            let caretRect = textView.caretRect(for: selectedRange.end)
            let visibleRect = caretRect.insetBy(dx: 0, dy: -20)
            textView.scrollRectToVisible(visibleRect, animated: true)
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

class EditorChromeAwareTextView: UITextView {
    var keyboardAccessoryToolbarView: KeyboardAccessoryToolbarView?
    var undoAccessoryItem: UIBarButtonItem?
    var redoAccessoryItem: UIBarButtonItem?
    var dismissAccessoryItem: UIBarButtonItem?
    var keyboardOverlapInset: CGFloat = 0
}

final class KeyboardAccessoryToolbarView: UIView {
    static let bottomSpacing: CGFloat = 8

    let toolbar = UIToolbar()
    let undoButton: UIBarButtonItem
    let redoButton: UIBarButtonItem
    let dismissButton: UIBarButtonItem

    init(target: AnyObject, undoAction: Selector, redoAction: Selector, dismissAction: Selector) {
        undoButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.backward"),
            style: .plain,
            target: target,
            action: undoAction
        )
        undoButton.accessibilityLabel = "Undo"

        redoButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.forward"),
            style: .plain,
            target: target,
            action: redoAction
        )
        redoButton.accessibilityLabel = "Redo"

        dismissButton = UIBarButtonItem(
            image: UIImage(systemName: "keyboard.chevron.compact.down"),
            style: .plain,
            target: target,
            action: dismissAction
        )
        dismissButton.accessibilityLabel = "Dismiss Keyboard"

        super.init(frame: .zero)

        backgroundColor = .clear
        isOpaque = false
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        addSubview(toolbar)
        toolbar.backgroundColor = .clear
        toolbar.isOpaque = false
        toolbar.isTranslucent = true
        toolbar.autoresizingMask = [.flexibleWidth]
        toolbar.items = [undoButton, redoButton, .flexibleSpace(), dismissButton]
        applyTransparentToolbarAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let toolbarHeight = toolbar.sizeThatFits(CGSize(width: bounds.width, height: UIView.noIntrinsicMetric)).height
        return CGSize(width: UIView.noIntrinsicMetric, height: toolbarHeight + Self.bottomSpacing)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let toolbarHeight = toolbar.sizeThatFits(CGSize(width: size.width, height: UIView.noIntrinsicMetric)).height
        return CGSize(width: size.width, height: toolbarHeight + Self.bottomSpacing)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let toolbarHeight = toolbar.sizeThatFits(CGSize(width: bounds.width, height: UIView.noIntrinsicMetric)).height
        toolbar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: toolbarHeight)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyTransparentToolbarAppearance()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyTransparentToolbarAppearance()
    }

    func update(canUndo: Bool, canRedo: Bool, canDismiss: Bool) {
        undoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo
        dismissButton.isEnabled = canDismiss
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    /// Keep the accessory visually transparent even when the keyboard host is recreated or traits
    /// change. This is especially important once editor background colors become theme-driven.
    private func applyTransparentToolbarAppearance() {
        let appearance = UIToolbarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear

        toolbar.standardAppearance = appearance
        toolbar.compactAppearance = appearance
        toolbar.scrollEdgeAppearance = appearance
        if #available(iOS 15.0, *) {
            toolbar.compactScrollEdgeAppearance = appearance
        }

        toolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
        toolbar.setShadowImage(UIImage(), forToolbarPosition: .any)
    }
}

private extension String {
    var containsLineBreak: Bool {
        contains("\n") || contains("\r")
    }
}
