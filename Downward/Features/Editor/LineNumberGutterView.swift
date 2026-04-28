import UIKit

final class LineNumberGutterView: UIView {
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
    /// Content-coordinate rects. Keeping debug rects in content coordinates makes
    /// scroll-position tests catch line drift without coupling them to the viewport layer.
    private(set) var lastDrawnLineNumberRects: [Int: CGRect] = [:]
    private(set) var lastHighlightColor: UIColor?
    private(set) var lastHighlightedLineNumbers: [Int] = []
    private(set) var lastHighlightedLineNumberRects: [Int: CGRect] = [:]
    private(set) var lastDrawingLineNumberOpacity: Double?
    private(set) var lastInvalidatedDisplayRect: CGRect?
#endif

    init(textView: EditorChromeAwareTextView) {
        self.textView = textView
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        // Keep the gutter as a small viewport-sized layer. A content-height layer can
        // grow to tens or hundreds of thousands of points for large files, which makes
        // Core Animation backing-store reuse unreliable after fast bottom-to-top jumps.
        isOpaque = true
        clearsContextBeforeDrawing = true
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
        setNeedsVisibleDisplay()
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
        updateVisibleViewportFrame(for: textView)
        backgroundColor = textView.resolvedTheme.editorBackground
        setNeedsVisibleDisplay()
    }

    func setNeedsVisibleDisplay() {
        guard let textView else {
            setNeedsDisplay()
            return
        }

        updateVisibleViewportFrame(for: textView)
#if DEBUG
        lastInvalidatedDisplayRect = visibleContentRect(for: textView)
#endif
        // The view itself is only as tall as the viewport, so repainting all of it is
        // cheap and avoids stale/black tiles after huge scroll jumps.
        setNeedsDisplay(bounds)
    }

    override func draw(_ rect: CGRect) {
        guard
            let textView,
            let context = UIGraphicsGetCurrentContext()
        else {
            return
        }

        context.setFillColor(textView.resolvedTheme.editorBackground.cgColor)
        context.fill(bounds)

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
        let visibleRect = visibleContentRect(for: textView)
        let viewportOriginY = visibleRect.minY
#if DEBUG
        lastDrawingLineNumberOpacity = textView.lineNumberOpacity
#endif

        guard fullLength > 0, glyphCount > 0 else {
            let contentDrawRect = CGRect(
                x: 0,
                y: topInset,
                width: gutterWidth - EditorTextViewLayout.lineNumberGutterTrailingPadding,
                height: font.lineHeight
            )
            if visibleRect.intersects(contentDrawRect), textView.shouldHideLineNumber(for: NSRange(location: 0, length: 0)) == false {
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
                    viewportOriginY: viewportOriginY,
                    in: context,
                    fullLength: fullLength
                )
                let label = Self.displayLabel(for: 1)
                (label as NSString).draw(
                    in: localDrawRect(forContentRect: contentDrawRect, viewportOriginY: viewportOriginY),
                    withAttributes: attributes
                )
#if DEBUG
                lastVisitedLogicalLineCount = 1
                lastDrawnLineNumbers = [1]
                lastDrawnLineNumberLabels = [label]
                lastDrawnLineNumberRects = [1: contentDrawRect]
#endif
            }
            return
        }

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

            guard let fragmentRect = lineFragmentRect(
                for: lineRange,
                forLineStartingAt: charIndex,
                previousFragmentRect: previousFragmentRect,
                glyphCount: glyphCount,
                layoutManager: layoutManager
            ) else {
                break
            }

            guard let contentDrawRect = lineNumberDrawRect(
                fragmentRect: fragmentRect,
                topInset: topInset,
                numberFontLineHeight: font.lineHeight
            ) else {
                break
            }
            if contentDrawRect.minY > visibleRect.maxY {
                break
            }

            previousFragmentRect = fragmentRect
#if DEBUG
            lastVisitedLogicalLineCount += 1
#endif

            if contentDrawRect.maxY >= visibleRect.minY,
               textView.shouldHideLineNumber(for: lineRange) == false {
                drawSelectionHighlightIfNeeded(
                    for: lineNumber,
                    lineRange: lineRange,
                    lineFragmentRect: fragmentRect,
                    topInset: topInset,
                    viewportOriginY: viewportOriginY,
                    in: context,
                    fullLength: fullLength
                )
                let label = Self.displayLabel(for: lineNumber)
                (label as NSString).draw(
                    in: localDrawRect(forContentRect: contentDrawRect, viewportOriginY: viewportOriginY),
                    withAttributes: attributes
                )
#if DEBUG
                lastDrawnLineNumbers.append(lineNumber)
                lastDrawnLineNumberLabels.append(label)
                lastDrawnLineNumberRects[lineNumber] = contentDrawRect
#endif
            }

            guard charIndex < fullLength else {
                break
            }
            charIndex = NSMaxRange(lineRange)
            lineNumber += 1
        }
    }

    private func updateVisibleViewportFrame(for textView: EditorChromeAwareTextView) {
        let viewportRect = visibleContentRect(for: textView)
        let desiredFrame = CGRect(
            x: max(0, textView.contentOffset.x),
            y: viewportRect.minY,
            width: gutterWidth,
            height: max(1, viewportRect.height)
        )

        guard frame.isApproximatelyEqual(to: desiredFrame) == false else {
            return
        }
        frame = desiredFrame
    }

    private func localDrawRect(forContentRect contentRect: CGRect, viewportOriginY: CGFloat) -> CGRect {
        contentRect.offsetBy(dx: 0, dy: -viewportOriginY)
    }

    private func lineFragmentRect(
        for lineRange: NSRange,
        forLineStartingAt charIndex: Int,
        previousFragmentRect: CGRect?,
        glyphCount: Int,
        layoutManager: NSLayoutManager
    ) -> CGRect? {
        guard let textView else {
            return nil
        }

        let nsText = (textView.text ?? "") as NSString
        if charIndex < nsText.length {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
            guard glyphIndex < glyphCount else {
                return nil
            }
            let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            guard fragmentRect.isValidLineNumberFragment else {
                return nil
            }
            if fragmentRect.isAfter(previousFragmentRect) {
                return fragmentRect
            }

            if let contentFragmentRect = contentFragmentRect(
                for: lineRange,
                glyphCount: glyphCount,
                layoutManager: layoutManager
            ),
               contentFragmentRect.isAfter(previousFragmentRect) {
                return contentFragmentRect
            }

            // Hidden syntax-only lines can produce null glyphs that TextKit
            // reports on a neighboring fragment. Keep the gutter's source-line
            // rows monotonic so code fences and horizontal rules cannot overlap.
            return syntheticFragmentRect(after: previousFragmentRect, fallback: fragmentRect)
        }

        guard nsText.length > 0, nsText.character(at: nsText.length - 1).isMarkdownLineBreak else {
            return nil
        }

        let lastGlyphIndex = glyphCount - 1
        let lastFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
        guard lastFragmentRect.isValidLineNumberFragment else {
            return nil
        }
        return CGRect(
            x: lastFragmentRect.minX,
            y: lastFragmentRect.maxY,
            width: lastFragmentRect.width,
            height: lastFragmentRect.height
        )
    }

    private func contentFragmentRect(
        for lineRange: NSRange,
        glyphCount: Int,
        layoutManager: NSLayoutManager
    ) -> CGRect? {
        guard
            let visibleContentRange = firstVisibleContentCharacterRange(from: lineRange)
        else {
            return nil
        }

        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: visibleContentRange,
            actualCharacterRange: nil
        )
        guard glyphRange.location < glyphCount, glyphRange.length > 0 else {
            return nil
        }

        let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        return fragmentRect.isValidLineNumberFragment ? fragmentRect : nil
    }

    private func syntheticFragmentRect(after previousFragmentRect: CGRect?, fallback fragmentRect: CGRect) -> CGRect {
        guard let previousFragmentRect else {
            return fragmentRect
        }

        let fallbackHeight = textView?.font?.lineHeight ?? fragmentRect.height
        let height = max(fragmentRect.height, fallbackHeight, 1)
        let width = fragmentRect.width.isFinite && fragmentRect.width > 0
            ? fragmentRect.width
            : previousFragmentRect.width
        let minX = fragmentRect.minX.isFinite ? fragmentRect.minX : previousFragmentRect.minX

        return CGRect(
            x: minX,
            y: previousFragmentRect.maxY,
            width: width,
            height: height
        )
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

    private func lineContentRange(from lineRange: NSRange) -> NSRange? {
        guard let textView else {
            return nil
        }

        let nsText = (textView.text ?? "") as NSString
        var location = min(max(lineRange.location, 0), nsText.length)
        var end = min(max(NSMaxRange(lineRange), location), nsText.length)

        while location < end, nsText.character(at: location).isMarkdownLineBreak {
            location += 1
        }

        while end > location, nsText.character(at: end - 1).isMarkdownLineBreak {
            end -= 1
        }

        return NSRange(location: location, length: end - location)
    }

    private func lineNumberDrawRect(
        fragmentRect: CGRect,
        topInset: CGFloat,
        numberFontLineHeight: CGFloat
    ) -> CGRect? {
        guard fragmentRect.isValidLineNumberFragment else {
            return nil
        }

        return CGRect(
            x: 0,
            y: fragmentRect.origin.y + topInset + (fragmentRect.height - numberFontLineHeight) / 2,
            width: gutterWidth - EditorTextViewLayout.lineNumberGutterTrailingPadding,
            height: numberFontLineHeight
        )
    }

    private func drawSelectionHighlightIfNeeded(
        for lineNumber: Int,
        lineRange: NSRange,
        lineFragmentRect: CGRect,
        topInset: CGFloat,
        viewportOriginY: CGFloat,
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

        let contentHighlightRect = CGRect(
            x: 2,
            y: lineFragmentRect.minY + topInset + 1,
            width: max(0, gutterWidth - 4),
            height: max(0, lineFragmentRect.height - 2)
        )
        let highlightRect = localDrawRect(forContentRect: contentHighlightRect, viewportOriginY: viewportOriginY)
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
        lastHighlightedLineNumberRects[lineNumber] = contentHighlightRect
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
            height: max(1, textView.bounds.height)
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

private extension CGRect {
    var isValidLineNumberFragment: Bool {
        isNull == false && isInfinite == false && height.isFinite && width.isFinite
    }

    func isAfter(_ previousFragmentRect: CGRect?) -> Bool {
        guard let previousFragmentRect else {
            return true
        }

        return minY > previousFragmentRect.minY + 0.5
    }

    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance &&
            abs(origin.y - other.origin.y) <= tolerance &&
            abs(size.width - other.size.width) <= tolerance &&
            abs(size.height - other.size.height) <= tolerance
    }
}

private extension unichar {
    var isMarkdownLineBreak: Bool {
        self == 0x0A || self == 0x0D
    }
}
