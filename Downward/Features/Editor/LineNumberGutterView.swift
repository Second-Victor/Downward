import UIKit

final class LineNumberGutterView: UIView {
    private weak var textView: EditorChromeAwareTextView?
    private var cachedFont: UIFont?
    private var cachedAttributes: [NSAttributedString.Key: Any]?
    private var cachedTheme: ResolvedEditorTheme?
    private var cachedFontSize: CGFloat?

    private(set) var gutterWidth: CGFloat = 0
#if DEBUG
    private(set) var lastVisitedLogicalLineCount = 0
    private(set) var lastDrawnLineNumbers: [Int] = []
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
        setNeedsDisplay()
    }

    static func width(lineCount: Int, fontSize: CGFloat) -> CGFloat {
        let digitCount = max(1, String(max(1, lineCount)).count)
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
#endif

        let nsText = (textView.text ?? "") as NSString
        let fullLength = nsText.length
        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        let glyphCount = layoutManager.numberOfGlyphs
        let topInset = textView.textContainerInset.top
        let (font, attributes) = drawingAttributes()

        guard fullLength > 0, glyphCount > 0 else {
            let drawRect = CGRect(
                x: 0,
                y: topInset,
                width: gutterWidth - EditorTextViewLayout.lineNumberGutterTrailingPadding,
                height: font.lineHeight
            )
            if visibleContentRect(for: textView).intersects(drawRect), textView.shouldHideLineNumber(for: NSRange(location: 0, length: 0)) == false {
                ("1" as NSString).draw(in: drawRect, withAttributes: attributes)
#if DEBUG
                lastVisitedLogicalLineCount = 1
                lastDrawnLineNumbers = [1]
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

        while charIndex <= fullLength {
            let lineRange = charIndex < fullLength
                ? nsText.lineRange(for: NSRange(location: charIndex, length: 0))
                : NSRange(location: fullLength, length: 0)

            guard let firstFragment = firstVisualFragmentRect(
                forLogicalLineStartingAt: charIndex,
                fullLength: fullLength,
                glyphCount: glyphCount,
                layoutManager: layoutManager
            ) else {
                break
            }

            let lineTop = firstFragment.origin.y + topInset
            let drawRect = CGRect(
                x: 0,
                y: lineTop + (firstFragment.height - font.lineHeight) / 2,
                width: gutterWidth - EditorTextViewLayout.lineNumberGutterTrailingPadding,
                height: font.lineHeight
            )

            if drawRect.minY > visibleRect.maxY {
                break
            }

#if DEBUG
            lastVisitedLogicalLineCount += 1
#endif

            if drawRect.maxY >= visibleRect.minY,
               textView.shouldHideLineNumber(for: lineRange) == false {
                ("\(lineNumber)" as NSString).draw(in: drawRect, withAttributes: attributes)
#if DEBUG
                lastDrawnLineNumbers.append(lineNumber)
#endif
            }

            guard charIndex < fullLength else {
                break
            }
            charIndex = NSMaxRange(lineRange)
            lineNumber += 1
        }
    }

    private func firstVisualFragmentRect(
        forLogicalLineStartingAt charIndex: Int,
        fullLength: Int,
        glyphCount: Int,
        layoutManager: NSLayoutManager
    ) -> CGRect? {
        if charIndex < fullLength {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
            guard glyphIndex < glyphCount else {
                return nil
            }

            return layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        }

        guard fullLength > 0, glyphCount > 0 else {
            return nil
        }

        let nsText = (textView?.text ?? "") as NSString
        let previousScalar = nsText.character(at: fullLength - 1)
        guard previousScalar == 0x0A || previousScalar == 0x0D else {
            return nil
        }

        let lastRect = layoutManager.lineFragmentRect(forGlyphAt: glyphCount - 1, effectiveRange: nil)
        return CGRect(x: lastRect.minX, y: lastRect.maxY, width: lastRect.width, height: lastRect.height)
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

        if let cachedFont,
           let cachedAttributes,
           cachedTheme == resolvedTheme,
           cachedFontSize == fontSize {
            return (cachedFont, cachedAttributes)
        }

        let font = UIFont.monospacedDigitSystemFont(ofSize: fontSize * 0.85, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: resolvedTheme.tertiaryText.withAlphaComponent(0.85),
            .paragraphStyle: paragraphStyle
        ]

        cachedFont = font
        cachedAttributes = attributes
        cachedTheme = resolvedTheme
        cachedFontSize = fontSize
        return (font, attributes)
    }
}
