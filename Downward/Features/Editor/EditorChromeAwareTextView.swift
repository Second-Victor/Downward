import UIKit

class EditorChromeAwareTextView: UITextView {
    var keyboardAccessoryToolbarView: KeyboardAccessoryToolbarView?
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
        resolvedTheme: ResolvedEditorTheme,
        font: UIFont
    ) {
        self.resolvedTheme = resolvedTheme
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

    func shouldHideLineNumber(for lineRange: NSRange) -> Bool {
        guard textStorage.length > 0, lineRange.location < textStorage.length else {
            return false
        }

        let contentRange = lineContentRange(from: lineRange)
        guard contentRange.length > 0 else {
            return false
        }

        var hasHiddenSyntax = false
        textStorage.enumerateAttribute(.markdownHiddenSyntax, in: contentRange) { value, _, stop in
            guard value != nil else {
                return
            }

            hasHiddenSyntax = true
            stop.pointee = true
        }
        guard hasHiddenSyntax else {
            return false
        }

        var entireLineSuppressesNumber = true
        textStorage.enumerateAttribute(.markdownLineNumberHiddenWhenSyntaxHidden, in: contentRange) { value, _, stop in
            guard value == nil else {
                return
            }

            entireLineSuppressesNumber = false
            stop.pointee = true
        }

        return entireLineSuppressesNumber
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

    private func lineContentRange(from lineRange: NSRange) -> NSRange {
        let length = textStorage.length
        var location = min(max(lineRange.location, 0), length)
        var end = min(max(NSMaxRange(lineRange), location), length)
        let nsText = textStorage.string as NSString

        while location < end {
            let scalar = nsText.character(at: location)
            guard scalar == 0x0A || scalar == 0x0D else {
                break
            }

            location += 1
        }

        while end > location {
            let scalar = nsText.character(at: end - 1)
            guard scalar == 0x0A || scalar == 0x0D else {
                break
            }

            end -= 1
        }

        return NSRange(location: location, length: end - location)
    }
}
