import UIKit

class EditorChromeAwareTextView: UITextView {
    var keyboardAccessoryToolbarView: KeyboardAccessoryToolbarView?
    var formatAccessoryItem: UIBarButtonItem?
    var undoAccessoryItem: UIBarButtonItem?
    var redoAccessoryItem: UIBarButtonItem?
    var dismissAccessoryItem: UIBarButtonItem?
    var keyboardOverlapInset: CGFloat = 0
    var resolvedTheme: ResolvedEditorTheme = .default {
        didSet {
            guard oldValue != resolvedTheme else {
                return
            }

            lineNumberGutterView.invalidateDrawingAttributes()
            lineNumberGutterView.updateGutter()
        }
    }
    var showLineNumbers = false {
        didSet {
            guard oldValue != showLineNumbers else {
                return
            }

            updateLineNumberVisibility()
        }
    }
    var lineNumberOpacity = EditorAppearancePreferences.defaultLineNumberOpacity {
        didSet {
            let clampedValue = min(max(lineNumberOpacity, 0), 1)
            if abs(clampedValue - lineNumberOpacity) > 0.001 {
                lineNumberOpacity = clampedValue
                return
            }

            guard abs(oldValue - lineNumberOpacity) > 0.001 else {
                return
            }

            lineNumberGutterView.invalidateDrawingAttributes()
            lineNumberGutterView.updateGutter()
        }
    }

    private var cachedLineMetrics = TextLineMetrics(text: "")
    private var needsLineMetricsRefresh = true
    private var lineNumberFontSize: CGFloat = UIFont.systemFontSize {
        didSet {
            guard abs(oldValue - lineNumberFontSize) > 0.1 else {
                return
            }

            lineNumberGutterView.invalidateDrawingAttributes()
            lineNumberGutterView.updateGutter()
        }
    }

    private lazy var lineNumberGutterView = LineNumberGutterView(textView: self)

    var lineMetrics: TextLineMetrics {
        if needsLineMetricsRefresh {
            cachedLineMetrics = TextLineMetrics(text: text ?? "")
            needsLineMetricsRefresh = false
        }

        return cachedLineMetrics
    }

    var editorLineNumberFontSize: CGFloat {
        lineNumberFontSize
    }

    var lineNumberGutter: LineNumberGutterView? {
        lineNumberGutterView
    }

    override var text: String! {
        didSet {
            textContentDidChange(from: oldValue, to: text)
        }
    }

    override var attributedText: NSAttributedString! {
        didSet {
            textContentDidChange(from: oldValue?.string, to: attributedText?.string)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if showLineNumbers {
            lineNumberGutterView.updateGutter()
        }
    }

    func applyLineNumberConfiguration(
        showLineNumbers: Bool,
        lineNumberOpacity: Double = EditorAppearancePreferences.defaultLineNumberOpacity,
        resolvedTheme: ResolvedEditorTheme,
        font: UIFont
    ) {
        self.resolvedTheme = resolvedTheme
        self.lineNumberOpacity = lineNumberOpacity
        lineNumberFontSize = font.pointSize
        self.showLineNumbers = showLineNumbers

        if showLineNumbers {
            lineNumberGutterView.updateGutter()
        }
    }

    func updateLineNumberTextInset(gutterWidth: CGFloat) {
        guard showLineNumbers else {
            return
        }

        let desiredLeftInset = gutterWidth + EditorTextViewLayout.lineNumberGutterGap
        guard abs(textContainerInset.left - desiredLeftInset) > 0.5 else {
            return
        }

        var updatedInset = textContainerInset
        updatedInset.left = desiredLeftInset
        textContainerInset = updatedInset
    }

    func notePlainTextMutation() {
        needsLineMetricsRefresh = true
        if showLineNumbers {
            lineNumberGutterView.updateGutter()
        }
    }

    func setNeedsLineNumberDisplay() {
        guard showLineNumbers else {
            return
        }

        lineNumberGutterView.setNeedsDisplay()
    }

    func shouldHideLineNumber(for _: NSRange) -> Bool {
        false
    }

    private func updateLineNumberVisibility() {
        if showLineNumbers {
            if lineNumberGutterView.superview == nil {
                addSubview(lineNumberGutterView)
            }
            lineNumberGutterView.isHidden = false
            lineNumberGutterView.updateGutter()
        } else {
            lineNumberGutterView.isHidden = true
            var updatedInset = textContainerInset
            updatedInset.left = EditorTextViewLayout.horizontalInset
            textContainerInset = updatedInset
        }
    }

    private func textContentDidChange(from oldText: String?, to newText: String?) {
        guard oldText != newText else {
            return
        }

        notePlainTextMutation()
    }

}
