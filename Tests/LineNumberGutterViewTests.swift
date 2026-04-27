import UIKit
import XCTest
@testable import Downward

final class LineNumberGutterViewTests: XCTestCase {
    @MainActor
    func testGutterHiddenByDefaultAndWhenDisabled() {
        let textView = makeTextView(text: "Hello", showLineNumbers: false)

        XCTAssertEqual(textView.textContainerInset.left, EditorTextViewLayout.horizontalInset)
        XCTAssertTrue(textView.lineNumberGutter?.isHidden ?? false)

        textView.applyLineNumberConfiguration(showLineNumbers: true, resolvedTheme: .default, font: textView.font ?? .systemFont(ofSize: 16))
        XCTAssertFalse(textView.lineNumberGutter?.isHidden ?? true)
        XCTAssertGreaterThan(textView.textContainerInset.left, EditorTextViewLayout.horizontalInset)

        textView.showLineNumbers = false
        XCTAssertTrue(textView.lineNumberGutter?.isHidden ?? false)
        XCTAssertEqual(textView.textContainerInset.left, EditorTextViewLayout.horizontalInset)
    }

    @MainActor
    func testGutterWidthGrowsWithDigitCount() {
        let nineLines = (1...9).map { "Line \($0)" }.joined(separator: "\n")
        let hundredLines = (1...100).map { "Line \($0)" }.joined(separator: "\n")

        let textView = makeTextView(text: nineLines)
        let oneDigitWidth = textView.lineNumberGutter?.gutterWidth ?? 0

        textView.text = hundredLines
        textView.notePlainTextMutation()
        textView.layoutIfNeeded()

        XCTAssertGreaterThan(textView.lineNumberGutter?.gutterWidth ?? 0, oneDigitWidth)
    }

    @MainActor
    func testEmptyFileConfiguresLineOneWithoutCrashing() {
        let textView = makeTextView(text: "")
        drawGutter(in: textView)

        XCTAssertGreaterThan(textView.lineNumberGutter?.gutterWidth ?? 0, 0)
#if DEBUG
        XCTAssertEqual(textView.lineNumberGutter?.lastDrawnLineNumbers, [1])
#endif
    }

    @MainActor
    func testFontAndThemeChangesUpdateGutterState() {
        let textView = makeTextView(text: "Line")
        let initialWidth = textView.lineNumberGutter?.gutterWidth ?? 0
        let theme = ResolvedEditorTheme.default.withEditorBackground(.systemYellow)

        textView.applyLineNumberConfiguration(
            showLineNumbers: true,
            resolvedTheme: theme,
            font: .monospacedSystemFont(ofSize: 24, weight: .regular)
        )

        XCTAssertGreaterThan(textView.lineNumberGutter?.gutterWidth ?? 0, initialWidth)
        XCTAssertEqual(textView.lineNumberGutter?.backgroundColor, theme.editorBackground)
    }

    @MainActor
    func testVisibleLineDrawingDoesNotWalkEntireLargeDocument() {
        let text = (1...1_000).map { "Line \($0)" }.joined(separator: "\n")
        let textView = makeTextView(text: text)
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        textView.contentOffset = CGPoint(x: 0, y: 4_000)

        drawGutter(in: textView)

#if DEBUG
        XCTAssertLessThan(textView.lineNumberGutter?.lastVisitedLogicalLineCount ?? 1_000, 80)
        XCTAssertNotEqual(textView.lineNumberGutter?.lastDrawnLineNumbers.first, 1)
#endif
    }

    @MainActor
    func testHiddenSyntaxSuppressesFenceDelimiterLineNumbersOnlyWhenHidden() {
        let text = "Before\n```swift\nlet x = 1\n```\nAfter"
        let renderer = MarkdownStyledTextRenderer()
        let offLineRendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: .monospacedSystemFont(ofSize: 16, weight: .regular),
                syntaxMode: .hiddenOutsideCurrentLine,
                revealedRange: (text as NSString).lineRange(for: (text as NSString).range(of: "Before"))
            )
        )
        let currentLineRendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: .monospacedSystemFont(ofSize: 16, weight: .regular),
                syntaxMode: .hiddenOutsideCurrentLine,
                revealedRange: (text as NSString).lineRange(for: (text as NSString).range(of: "```swift"))
            )
        )

        let textView = makeTextView(text: text)
        textView.attributedText = offLineRendered

        XCTAssertTrue(textView.shouldHideLineNumber(for: lineRange(in: text, containing: "```swift")))
        XCTAssertTrue(textView.shouldHideLineNumber(for: lineRange(in: text, containing: "```\nAfter")))
        XCTAssertFalse(textView.shouldHideLineNumber(for: lineRange(in: text, containing: "let x = 1")))

        textView.attributedText = currentLineRendered
        XCTAssertFalse(textView.shouldHideLineNumber(for: lineRange(in: text, containing: "```swift")))
    }

    @MainActor
    func testHiddenSyntaxSuppressesSetextUnderlineLineNumber() {
        let text = "Heading\n=======\nBody"
        let nsText = text as NSString
        let renderer = MarkdownStyledTextRenderer()
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: .monospacedSystemFont(ofSize: 16, weight: .regular),
                syntaxMode: .hiddenOutsideCurrentLine,
                revealedRange: nsText.lineRange(for: nsText.range(of: "Body"))
            )
        )
        let textView = makeTextView(text: text)
        textView.attributedText = rendered

        XCTAssertTrue(textView.shouldHideLineNumber(for: lineRange(in: text, containing: "=======")))
        XCTAssertFalse(textView.shouldHideLineNumber(for: lineRange(in: text, containing: "Heading")))
    }

    @MainActor
    private func makeTextView(
        text: String,
        showLineNumbers: Bool = true
    ) -> EditorChromeAwareTextView {
        let textStorage = NSTextStorage()
        let layoutManager = MarkdownCodeBackgroundLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = EditorChromeAwareTextView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 480),
            textContainer: textContainer
        )
        textView.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        textView.textContainerInset = UIEdgeInsets(
            top: EditorTextViewLayout.contentTopInset,
            left: EditorTextViewLayout.horizontalInset,
            bottom: EditorTextViewLayout.bottomInset,
            right: EditorTextViewLayout.horizontalInset
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.text = text
        textView.applyLineNumberConfiguration(
            showLineNumbers: showLineNumbers,
            resolvedTheme: .default,
            font: textView.font ?? .systemFont(ofSize: 16)
        )
        textView.layoutIfNeeded()
        return textView
    }

    @MainActor
    private func drawGutter(in textView: EditorChromeAwareTextView) {
        guard let gutter = textView.lineNumberGutter else {
            XCTFail("Expected line number gutter")
            return
        }

        gutter.updateGutter()
        let size = CGSize(width: max(gutter.bounds.width, 1), height: max(gutter.bounds.height, 1))
        _ = UIGraphicsImageRenderer(size: size).image { _ in
            gutter.draw(CGRect(origin: .zero, size: size))
        }
    }

    private func lineRange(in text: String, containing needle: String) -> NSRange {
        let nsText = text as NSString
        let match = nsText.range(of: needle)
        return nsText.lineRange(for: NSRange(location: match.location, length: 0))
    }
}

@MainActor
private extension ResolvedEditorTheme {
    func withEditorBackground(_ color: UIColor) -> ResolvedEditorTheme {
        ResolvedEditorTheme(
            editorBackground: color,
            keyboardAccessoryUnderlayBackground: keyboardAccessoryUnderlayBackground,
            accent: accent,
            primaryText: primaryText,
            secondaryText: secondaryText,
            tertiaryText: tertiaryText,
            headingText: headingText,
            emphasisText: emphasisText,
            strikethroughText: strikethroughText,
            syntaxMarkerText: syntaxMarkerText,
            subtleSyntaxMarkerText: subtleSyntaxMarkerText,
            linkText: linkText,
            imageAltText: imageAltText,
            inlineCodeText: inlineCodeText,
            inlineCodeBackground: inlineCodeBackground,
            codeBlockText: codeBlockText,
            codeBlockBackground: codeBlockBackground,
            blockquoteText: blockquoteText,
            blockquoteBackground: blockquoteBackground,
            blockquoteBar: blockquoteBar,
            horizontalRuleText: horizontalRuleText
        )
    }
}
