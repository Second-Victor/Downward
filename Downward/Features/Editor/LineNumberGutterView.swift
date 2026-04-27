import UIKit

final class LineNumberGutterView: UIView {
    private struct LogicalLineLayout {
        var lineNumber: Int
        var lineRange: NSRange
        var drawRect: CGRect
        var fragmentRect: CGRect
    }

    private weak var textView: EditorChromeAwareTextView?
    private var cachedFont: UIFont?
    private var cachedAttributes: [NSAttributedString.Key: Any]?
    private var cachedTheme: ResolvedEditorTheme?
    private var cachedFontSize: CGFloat?
    private var cachedOpacity: Double?

    private(set) var gutterWidth: CGFloat = 0
#if DEBUG
    private(set) var lastVisitedLogicalLineCount = 0
    private(set) var lastDrawnLineNumbers: [Int] = []
    private(set) var lastDrawnLineNumberLabels: [String] = []
    private(set) var lastDrawnLineNumberRects: [Int: CGRect] = [:]
    private(set) var lastHighlightColor: UIColor?
    private(set) var lastHighlightedLineNumbers: [Int] = []
    private(set) var lastHighlightedLineNumberRects: [Int: CGRect] = [:]
    private(set) var lastDrawingLineNumberOpacity: Double?
#endif

    init(textView: EditorChromeAwareTextView) {
        self.textView = textView
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isOpaque = true
        isHidden = true
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        nil
    }

    func invalidateDrawingAttributes() {
        cachedFont = nil
        cachedAttributes = nil
        cachedTheme = nil
        cachedFontSize = nil
        cachedOpacity = nil
        setNeedsDisplay()
    }

    static func width(lineCount: Int, fontSize: CGFloat) -> CGFloat {
        let digitCount = max(2, String(max(1, lineCount)).count)
        let sampleString = String(repeating: "8", count: digitCount) as NSString
        let font = UIFont.monospacedDigitSystemFont(ofSize: fontSize * 0.85, weight: .regular)
        let numberWidth = sampleString.size(withAttributes: [.font: font]).width
        return ceil(numberWidth + EditorTextViewLayout.lineNumberGutterHorizontalPadding * 2)
    }

    func updateGutter() {
        guard let textView else {
            return
        }

        let fontSize = textView.editorLineNumberFontSize
        let newGutterWidth = Self.width(
            lineCount: textView.lineMetrics.lineCount,
            fontSize: fontSize
        )

        if abs(newGutterWidth - gutterWidth) > 0.5 {
            gutterWidth = newGutterWidth
        }
        textView.updateLineNumberTextInset(gutterWidth: gutterWidth)

        let contentHeight = max(textView.contentSize.height, textView.bounds.height)
        frame = CGRect(x: 0, y: 0, width: gutterWidth, height: contentHeight)
        backgroundColor = textView.resolvedTheme.editorBackground
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard
            let textView,
            let context = UIGraphicsGetCurrentContext()
        else {
            return
        }

        context.setFillColor(textView.resolvedTheme.editorBackground.cgColor)
        context.fill(rect)

#if DEBUG
        lastVisitedLogicalLineCount = 0
        lastDrawnLineNumbers = []
        lastDrawnLineNumberLabels = []
        lastDrawnLineNumberRects = [:]
        lastHighlightColor = nil
        lastHighlightedLineNumbers = []
        lastHighlightedLineNumberRects = [:]
        lastDrawingLineNumberOpacity = nil
#endif

        let nsText = (textView.text ?? "") as NSString
        let fullLength = nsText.length
        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        let glyphCount = layoutManager.numberOfGlyphs
        let topInset = textView.textContainerInset.top
        let (font, attributes) = drawingAttributes()
#if DEBUG
        lastDrawingLineNumberOpacity = textView.lineNumberOpacity
#endif

        guard fullLength > 0, glyphCount > 0 else {
            let drawRect = CGRect(
                x: 0,
                y: topInset,
                width: gutterWidth - EditorTextViewLayout.lineNumberGutterTrailingPadding,
                height: font.lineHeight
            )
            if visibleContentRect(for: textView).intersects(drawRect), textView.shouldHideLineNumber(for: NSRange(location: 0, length: 0)) == false {
                drawSelectionHighlightIfNeeded(
                    for: 1,
                    lineRange: NSRange(location: 0, length: 0),
                    lineFragmentRect: CGRect(
                        x: 0,
                        y: 0,
                        width: textView.textContainer.size.width,
                        height: font.lineHeight
                    ),
                    topInset: topInset,
                    in: context,
                    fullLength: fullLength
                )
                let label = Self.displayLabel(for: 1)
                (label as NSString).draw(in: drawRect, withAttributes: attributes)
#if DEBUG
                lastVisitedLogicalLineCount = 1
                lastDrawnLineNumbers = [1]
                lastDrawnLineNumberLabels = [label]
                lastDrawnLineNumberRects = [1: drawRect]
#endif
            }
            return
        }

        let visibleRect = visibleContentRect(for: textView)
        let visibleTextContainerRect = CGRect(
            x: 0,
            y: max(0, visibleRect.minY - topInset),
            width: textContainer.size.width,
            height: visibleRect.height
        )
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleTextContainerRect,
            in: textContainer
        )
        guard visibleGlyphRange.length > 0 else {
            return
        }

        let visibleCharRange = layoutManager.characterRange(
            forGlyphRange: visibleGlyphRange,
            actualGlyphRange: nil
        )
        let firstVisibleLineRange = nsText.lineRange(
            for: NSRange(location: min(visibleCharRange.location, fullLength), length: 0)
        )
        var lineNumber = textView.lineMetrics.lineNumber(at: firstVisibleLineRange.location)
        var charIndex = firstVisibleLineRange.location
        var previousFragmentRect: CGRect?
        let shouldDrawTrailingEmptyLine = textView.lineMetrics.lineStartLocations.last == fullLength

        while charIndex < fullLength || (shouldDrawTrailingEmptyLine && charIndex == fullLength) {
            let lineRange = charIndex < fullLength
                ? nsText.lineRange(for: NSRange(location: charIndex, length: 0))
                : NSRange(location: fullLength, length: 0)

            guard let lineLayout = logicalLineLayout(
                lineNumber: lineNumber,
                lineRange: lineRange,
                previousFragmentRect: previousFragmentRect,
                glyphCount: glyphCount,
                layoutManager: layoutManager,
                topInset: topInset,
                numberFontLineHeight: font.lineHeight
            ) else {
                break
            }

            previousFragmentRect = lineLayout.fragmentRect
            if lineLayout.drawRect.minY > visibleRect.maxY {
                break
            }

#if DEBUG
            lastVisitedLogicalLineCount += 1
#endif

            if lineLayout.drawRect.maxY >= visibleRect.minY,
               textView.shouldHideLineNumber(for: lineRange) == false {
                drawSelectionHighlightIfNeeded(
                    for: lineLayout.lineNumber,
                    lineRange: lineRange,
                    lineFragmentRect: lineLayout.fragmentRect,
                    topInset: topInset,
                    in: context,
                    fullLength: fullLength
                )
                let label = Self.displayLabel(for: lineLayout.lineNumber)
                (label as NSString).draw(in: lineLayout.drawRect, withAttributes: attributes)
#if DEBUG
                lastDrawnLineNumbers.append(lineLayout.lineNumber)
                lastDrawnLineNumberLabels.append(label)
                lastDrawnLineNumberRects[lineLayout.lineNumber] = lineLayout.drawRect
#endif
            }

            guard charIndex < fullLength else {
                break
            }
            charIndex = NSMaxRange(lineRange)
            lineNumber += 1
        }
    }

    private func logicalLineLayout(
        lineNumber: Int,
        lineRange: NSRange,
        previousFragmentRect: CGRect?,
        glyphCount: Int,
        layoutManager: NSLayoutManager,
        topInset: CGFloat,
        numberFontLineHeight: CGFloat
    ) -> LogicalLineLayout? {
        guard let textView else {
            return nil
        }

        let fallbackLineHeight = max(textView.font?.lineHeight ?? numberFontLineHeight, numberFontLineHeight)
        guard let fragmentRect = lineFragmentRect(
            for: lineRange,
            previousFragmentRect: previousFragmentRect,
            glyphCount: glyphCount,
            layoutManager: layoutManager,
            fallbackLineHeight: fallbackLineHeight
        ) else {
            return nil
        }

        let lineTop = fragmentRect.origin.y + topInset
        let drawRect = CGRect(
            x: 0,
            y: lineTop + (fragmentRect.height - numberFontLineHeight) / 2,
            width: gutterWidth - EditorTextViewLayout.lineNumberGutterTrailingPadding,
            height: numberFontLineHeight
        )

        return LogicalLineLayout(
            lineNumber: lineNumber,
            lineRange: lineRange,
            drawRect: drawRect,
            fragmentRect: fragmentRect
        )
    }

    private func lineFragmentRect(
        for lineRange: NSRange,
        previousFragmentRect: CGRect?,
        glyphCount: Int,
        layoutManager: NSLayoutManager,
        fallbackLineHeight: CGFloat
    ) -> CGRect? {
        if let visibleRange = firstVisibleContentCharacterRange(from: lineRange) {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: visibleRange,
                actualCharacterRange: nil
            )
            if glyphRange.location < glyphCount, glyphRange.length > 0 {
                let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
                if isUsable(fragmentRect, after: previousFragmentRect) {
                    return fragmentRect
                }
            }
        }

        if let previousFragmentRect {
            return CGRect(
                x: previousFragmentRect.minX,
                y: previousFragmentRect.maxY,
                width: previousFragmentRect.width,
                height: fallbackLineHeight
            )
        }

        if let nextFragmentRect = nextVisibleFragmentRect(
            after: lineRange,
            glyphCount: glyphCount,
            layoutManager: layoutManager
        ) {
            return CGRect(
                x: nextFragmentRect.minX,
                y: max(0, nextFragmentRect.minY - fallbackLineHeight),
                width: nextFragmentRect.width,
                height: fallbackLineHeight
            )
        }

        return CGRect(
            x: 0,
            y: 0,
            width: textView?.textContainer.size.width ?? 0,
            height: fallbackLineHeight
        )
    }

    private func nextVisibleFragmentRect(
        after lineRange: NSRange,
        glyphCount: Int,
        layoutManager: NSLayoutManager
    ) -> CGRect? {
        guard let textView else {
            return nil
        }

        let nsText = (textView.text ?? "") as NSString
        var charIndex = NSMaxRange(lineRange)
        while charIndex < nsText.length {
            let nextLineRange = nsText.lineRange(for: NSRange(location: charIndex, length: 0))
            if let visibleRange = firstVisibleContentCharacterRange(from: nextLineRange) {
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: visibleRange,
                    actualCharacterRange: nil
                )
                if glyphRange.location < glyphCount, glyphRange.length > 0 {
                    return layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
                }
            }

            let nextIndex = NSMaxRange(nextLineRange)
            guard nextIndex > charIndex else {
                break
            }

            charIndex = nextIndex
        }

        return nil
    }

    private func firstVisibleContentCharacterRange(from lineRange: NSRange) -> NSRange? {
        guard
            let textView,
            let contentRange = lineContentRange(from: lineRange),
            contentRange.length > 0
        else {
            return nil
        }

        var visibleRange: NSRange?
        textView.textStorage.enumerateAttribute(.markdownHiddenSyntax, in: contentRange) { value, range, stop in
            guard value == nil, range.length > 0 else {
                return
            }

            visibleRange = NSRange(location: range.location, length: 1)
            stop.pointee = true
        }

        return visibleRange
    }

    private func isUsable(_ fragmentRect: CGRect, after previousFragmentRect: CGRect?) -> Bool {
        guard fragmentRect.isNull == false, fragmentRect.isInfinite == false else {
            return false
        }

        guard let previousFragmentRect else {
            return true
        }

        return fragmentRect.minY > previousFragmentRect.minY + 0.5
    }

    private func lineContentRange(from lineRange: NSRange) -> NSRange? {
        guard let textView else {
            return nil
        }

        let nsText = (textView.text ?? "") as NSString
        var location = min(max(lineRange.location, 0), nsText.length)
        var end = min(max(NSMaxRange(lineRange), location), nsText.length)

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

    private func drawSelectionHighlightIfNeeded(
        for lineNumber: Int,
        lineRange: NSRange,
        lineFragmentRect: CGRect,
        topInset: CGFloat,
        in context: CGContext,
        fullLength: Int
    ) {
        guard
            let textView,
            textView.isFirstResponder,
            textView.selectedRange.length == 0,
            isCursorLine(lineRange, fullLength: fullLength, selectedLocation: textView.selectedRange.location)
        else {
            return
        }

        let highlightRect = CGRect(
            x: 2,
            y: lineFragmentRect.minY + topInset + 1,
            width: max(0, gutterWidth - 4),
            height: max(0, lineFragmentRect.height - 2)
        )
        guard highlightRect.isEmpty == false else {
            return
        }

        context.saveGState()
        let highlightColor = currentLineHighlightColor(
            theme: textView.resolvedTheme,
            lineNumberOpacity: textView.lineNumberOpacity
        )
        highlightColor.setFill()
        UIBezierPath(
            roundedRect: highlightRect,
            cornerRadius: min(6, highlightRect.height / 2)
        ).fill()
        context.restoreGState()
#if DEBUG
        lastHighlightColor = highlightColor
        lastHighlightedLineNumbers.append(lineNumber)
        lastHighlightedLineNumberRects[lineNumber] = highlightRect
#endif
    }

    private func isCursorLine(
        _ lineRange: NSRange,
        fullLength: Int,
        selectedLocation: Int
    ) -> Bool {
        let clampedLocation = min(max(selectedLocation, 0), fullLength)
        if lineRange.length == 0 {
            return clampedLocation == lineRange.location
        }

        if clampedLocation == fullLength,
           clampedLocation == NSMaxRange(lineRange),
           textView?.lineMetrics.lineStartLocations.last != fullLength {
            return true
        }

        return NSLocationInRange(clampedLocation, lineRange)
    }

    private func currentLineHighlightColor(
        theme: ResolvedEditorTheme,
        lineNumberOpacity: Double
    ) -> UIColor {
        let opacity = min(max(lineNumberOpacity, 0), 1)
        return UIColor { traits in
            let background = theme.editorBackground.resolvedColor(with: traits)
            let text = theme.primaryText.resolvedColor(with: traits)
            let lineNumber = theme.tertiaryText
                .withAlphaComponent(opacity)
                .resolvedColor(with: traits)
            let contrast = text.wcagContrastRatio(against: background)
            let contrastBoost = min(max((contrast - 4.5) / 6, 0), 1) * 0.03
            let highlightAlpha = min(max(0.06 + opacity * 0.12 + contrastBoost, 0.06), 0.21)

            return lineNumber.withAlphaComponent(highlightAlpha)
        }
    }

    private func visibleContentRect(for textView: EditorChromeAwareTextView) -> CGRect {
        CGRect(
            x: 0,
            y: max(0, textView.contentOffset.y),
            width: textView.bounds.width,
            height: textView.bounds.height
        )
    }

    private func drawingAttributes() -> (UIFont, [NSAttributedString.Key: Any]) {
        let fontSize = textView?.editorLineNumberFontSize ?? UIFont.systemFontSize
        let resolvedTheme = textView?.resolvedTheme ?? .default
        let opacity = textView?.lineNumberOpacity ?? EditorAppearancePreferences.defaultLineNumberOpacity

        if let cachedFont,
           let cachedAttributes,
           cachedTheme == resolvedTheme,
           cachedFontSize == fontSize,
           cachedOpacity == opacity {
            return (cachedFont, cachedAttributes)
        }

        let font = UIFont.monospacedDigitSystemFont(ofSize: fontSize * 0.85, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: resolvedTheme.tertiaryText.withAlphaComponent(opacity),
            .paragraphStyle: paragraphStyle
        ]

        cachedFont = font
        cachedAttributes = attributes
        cachedTheme = resolvedTheme
        cachedFontSize = fontSize
        cachedOpacity = opacity
        return (font, attributes)
    }

    private static func displayLabel(for lineNumber: Int) -> String {
        String(format: "%02d", max(1, lineNumber))
    }
}
