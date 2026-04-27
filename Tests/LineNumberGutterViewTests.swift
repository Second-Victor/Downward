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
        let twoDigitWidth = textView.lineNumberGutter?.gutterWidth ?? 0

        textView.text = hundredLines
        textView.notePlainTextMutation()
        textView.layoutIfNeeded()

        XCTAssertGreaterThan(textView.lineNumberGutter?.gutterWidth ?? 0, twoDigitWidth)
    }

    @MainActor
    func testEmptyFileConfiguresLineOneWithoutCrashing() {
        let textView = makeTextView(text: "")
        drawGutter(in: textView)

        XCTAssertGreaterThan(textView.lineNumberGutter?.gutterWidth ?? 0, 0)
#if DEBUG
        XCTAssertEqual(textView.lineNumberGutter?.lastDrawnLineNumbers, [1])
        XCTAssertEqual(textView.lineNumberGutter?.lastDrawnLineNumberLabels, ["01"])
#endif
    }

    @MainActor
    func testSingleLineWithoutTrailingNewlineDoesNotDrawPhantomFinalLine() {
        let textView = makeTextView(text: "Draft")
        drawGutter(in: textView)

#if DEBUG
        XCTAssertEqual(textView.lineNumberGutter?.lastDrawnLineNumbers, [1])
        XCTAssertEqual(textView.lineNumberGutter?.lastDrawnLineNumberLabels, ["01"])
#endif
    }

    @MainActor
    func testTrailingNewlineDrawsRealEmptyFinalLine() {
        let textView = makeTextView(text: "Draft\n")
        drawGutter(in: textView)

#if DEBUG
        XCTAssertEqual(textView.lineNumberGutter?.lastDrawnLineNumbers, [1, 2])
        XCTAssertEqual(textView.lineNumberGutter?.lastDrawnLineNumberLabels, ["01", "02"])
#endif
    }

    @MainActor
    func testSingleDigitLineNumbersAreZeroPadded() {
        let text = (1...10).map { "Line \($0)" }.joined(separator: "\n")
        let textView = makeTextView(text: text)

        drawGutter(in: textView)

#if DEBUG
        XCTAssertEqual(
            Array(textView.lineNumberGutter?.lastDrawnLineNumberLabels.prefix(10) ?? []),
            ["01", "02", "03", "04", "05", "06", "07", "08", "09", "10"]
        )
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
    func testGutterDrawsWithConfiguredOpacity() {
        let textView = makeTextView(text: "One\nTwo")
        textView.applyLineNumberConfiguration(
            showLineNumbers: true,
            lineNumberOpacity: 0.4,
            resolvedTheme: .default,
            font: textView.font ?? .systemFont(ofSize: 16)
        )

        drawGutter(in: textView)

#if DEBUG
        XCTAssertEqual(textView.lineNumberGutter?.lastDrawingLineNumberOpacity ?? -1, 0.4, accuracy: 0.001)
#endif
    }

    @MainActor
    func testGutterHighlightsCurrentCursorLineNumber() {
        let textView = makeTextView(text: "One\nTwo\nThree")
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(textView)
        window.makeKeyAndVisible()
        defer {
            textView.resignFirstResponder()
            window.isHidden = true
        }

        textView.selectedRange = NSRange(location: 4, length: 0)
        XCTAssertTrue(textView.becomeFirstResponder())

        drawGutter(in: textView)

#if DEBUG
        XCTAssertEqual(textView.lineNumberGutter?.lastHighlightedLineNumbers, [2])
        XCTAssertNotNil(textView.lineNumberGutter?.lastHighlightedLineNumberRects[2])
#endif
    }

    @MainActor
    func testGutterHighlightsLineOneWhenCursorIsAtEndOfSingleLineDocument() {
        let textView = makeTextView(text: "D")
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(textView)
        window.makeKeyAndVisible()
        defer {
            textView.resignFirstResponder()
            window.isHidden = true
        }

        textView.selectedRange = NSRange(location: 1, length: 0)
        XCTAssertTrue(textView.becomeFirstResponder())

        drawGutter(in: textView)

#if DEBUG
        XCTAssertEqual(textView.lineNumberGutter?.lastDrawnLineNumbers, [1])
        XCTAssertEqual(textView.lineNumberGutter?.lastHighlightedLineNumbers, [1])
        XCTAssertNotNil(textView.lineNumberGutter?.lastHighlightedLineNumberRects[1])
#endif
    }

    @MainActor
    func testGutterHighlightsTrailingEmptyLineInsteadOfPreviousLine() {
        let textView = makeTextView(text: "Hello\n\n")
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(textView)
        window.makeKeyAndVisible()
        defer {
            textView.resignFirstResponder()
            window.isHidden = true
        }

        textView.selectedRange = NSRange(location: (textView.text as NSString).length, length: 0)
        XCTAssertTrue(textView.becomeFirstResponder())

        drawGutter(in: textView)

#if DEBUG
        XCTAssertEqual(textView.lineNumberGutter?.lastDrawnLineNumbers, [1, 2, 3])
        XCTAssertEqual(textView.lineNumberGutter?.lastHighlightedLineNumbers, [3])
        XCTAssertNotNil(textView.lineNumberGutter?.lastHighlightedLineNumberRects[3])
#endif
    }

    @MainActor
    func testGutterCurrentLineHighlightUsesThemeTextBackgroundAndOpacity() throws {
        let textView = makeTextView(text: "One\nTwo\nThree")
        let theme = ResolvedEditorTheme.default.withCoreEditorColors(
            background: .white,
            primaryText: .black,
            tertiaryText: .purple
        )
        textView.applyLineNumberConfiguration(
            showLineNumbers: true,
            lineNumberOpacity: 0.5,
            resolvedTheme: theme,
            font: textView.font ?? .systemFont(ofSize: 16)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(textView)
        window.makeKeyAndVisible()
        defer {
            textView.resignFirstResponder()
            window.isHidden = true
        }

        textView.selectedRange = NSRange(location: 4, length: 0)
        XCTAssertTrue(textView.becomeFirstResponder())

        drawGutter(in: textView)

#if DEBUG
        let highlightColor = try XCTUnwrap(textView.lineNumberGutter?.lastHighlightColor)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(highlightColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(red, 0.5, accuracy: 0.01)
        XCTAssertEqual(green, 0, accuracy: 0.01)
        XCTAssertEqual(blue, 0.5, accuracy: 0.01)
        XCTAssertEqual(alpha, 0.15, accuracy: 0.01)
#endif
    }

    @MainActor
    func testGutterDoesNotHighlightLineNumberForTextSelection() {
        let textView = makeTextView(text: "One\nTwo\nThree")
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(textView)
        window.makeKeyAndVisible()
        defer {
            textView.resignFirstResponder()
            window.isHidden = true
        }

        textView.selectedRange = NSRange(location: 4, length: 3)
        XCTAssertTrue(textView.becomeFirstResponder())

        drawGutter(in: textView)

#if DEBUG
        XCTAssertEqual(textView.lineNumberGutter?.lastHighlightedLineNumbers, [])
#endif
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
    func testGutterUsesContentCoordinatesWhenTextViewScrolls() {
        let text = (1...120).map { "Line \($0)" }.joined(separator: "\n")
        let textView = makeTextView(text: text)
        textView.layoutManager.ensureLayout(for: textView.textContainer)

        textView.contentOffset = CGPoint(x: 0, y: 900)
        drawGutter(in: textView)

        XCTAssertEqual(textView.lineNumberGutter?.frame.origin.y, 0)
        XCTAssertGreaterThanOrEqual(
            textView.lineNumberGutter?.bounds.height ?? 0,
            max(textView.contentSize.height, textView.bounds.height) - 0.5
        )
#if DEBUG
        let visibleRect = CGRect(
            x: 0,
            y: textView.contentOffset.y,
            width: textView.lineNumberGutter?.bounds.width ?? 0,
            height: textView.bounds.height
        )
        XCTAssertNotEqual(textView.lineNumberGutter?.lastDrawnLineNumbers.first, 1)
        XCTAssertTrue(
            textView.lineNumberGutter?.lastDrawnLineNumberRects.values.allSatisfy { rect in
                rect.maxY >= visibleRect.minY && rect.minY <= visibleRect.maxY
            } ?? false
        )
#endif
    }

    @MainActor
    func testBlankLineBeforeHiddenMarkdownSyntaxKeepsDistinctPosition() throws {
        let text = denstoneFixture
        let textView = makeHiddenSyntaxTextView(text: text, revealedText: "Main Doors")

        drawGutter(in: textView)

#if DEBUG
        let blankLineRect = try XCTUnwrap(textView.lineNumberGutter?.lastDrawnLineNumberRects[5])
        let headingLineRect = try XCTUnwrap(textView.lineNumberGutter?.lastDrawnLineNumberRects[6])
        let drawnLineNumbers = textView.lineNumberGutter?.lastDrawnLineNumbers ?? []
        XCTAssertTrue(drawnLineNumbers.contains(5))
        XCTAssertTrue(drawnLineNumbers.contains(6))
        XCTAssertNotEqual(blankLineRect.minY, headingLineRect.minY, accuracy: 0.5)
        XCTAssertGreaterThan(headingLineRect.minY, blankLineRect.minY + blankLineRect.height * 0.5)
#endif
    }

    @MainActor
    func testNoVisibleLineNumbersShareTheSameYPosition() throws {
        let textView = makeHiddenSyntaxTextView(text: denstoneFixture, revealedText: "Main Doors")

        drawGutter(in: textView)

#if DEBUG
        let rects = textView.lineNumberGutter?.lastDrawnLineNumberRects ?? [:]
        let sortedRects = rects.sorted { $0.key < $1.key }
        for index in sortedRects.indices.dropFirst() {
            let previous = sortedRects[sortedRects.index(before: index)]
            let current = sortedRects[index]
            XCTAssertNotEqual(
                previous.value.minY,
                current.value.minY,
                accuracy: 0.5,
                "Lines \(previous.key) and \(current.key) share a y position"
            )
            XCTAssertGreaterThanOrEqual(
                current.value.minY,
                previous.value.minY,
                "Line \(current.key) moved above line \(previous.key)"
            )
        }
#endif
    }

    @MainActor
    func testVisibleBoldSyntaxLineNumberUsesTextKitPositionAfterBlankLines() throws {
        let text = """
        Backlog item


        **inProgress**
        - [ ] check boxes
        """
        let textView = makeRenderedTextView(text: text, syntaxMode: .visible)

        drawGutter(in: textView)

#if DEBUG
        let nsText = text as NSString
        let boldRange = nsText.range(of: "**inProgress**")
        let lineNumber = textView.lineMetrics.lineNumber(at: boldRange.location)
        let gutterRect = try XCTUnwrap(textView.lineNumberGutter?.lastDrawnLineNumberRects[lineNumber])
        let glyphRange = textView.layoutManager.glyphRange(
            forCharacterRange: NSRange(location: boldRange.location, length: 1),
            actualCharacterRange: nil
        )
        let fragmentRect = textView.layoutManager.lineFragmentRect(
            forGlyphAt: glyphRange.location,
            effectiveRange: nil
        )

        XCTAssertEqual(
            gutterRect.midY,
            fragmentRect.midY + textView.textContainerInset.top,
            accuracy: 0.5
        )
#endif
    }

    @MainActor
    func testLineNumberContentPositionsDoNotChangeWhenScrolled() throws {
        let textView = makeHiddenSyntaxTextView(text: denstoneFixture, revealedText: "Main Doors")

        textView.contentOffset = .zero
        drawGutter(in: textView)

#if DEBUG
        let rectsBeforeScroll = textView.lineNumberGutter?.lastDrawnLineNumberRects ?? [:]
#endif

        textView.contentOffset = CGPoint(x: 0, y: 72)
        drawGutter(in: textView)

#if DEBUG
        let rectsAfterScroll = textView.lineNumberGutter?.lastDrawnLineNumberRects ?? [:]
        let commonLineNumbers = Set(rectsBeforeScroll.keys).intersection(rectsAfterScroll.keys)
        XCTAssertFalse(commonLineNumbers.isEmpty)

        for lineNumber in commonLineNumbers {
            let before = try XCTUnwrap(rectsBeforeScroll[lineNumber])
            let after = try XCTUnwrap(rectsAfterScroll[lineNumber])
            XCTAssertEqual(after.minY, before.minY, accuracy: 0.5, "Line \(lineNumber) drifted while scrolling")
        }
#endif
    }

    @MainActor
    func testHiddenSyntaxDoesNotSuppressFenceDelimiterLineNumbers() {
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

        XCTAssertFalse(textView.shouldHideLineNumber(for: lineRange(in: text, containing: "```swift")))
        XCTAssertFalse(textView.shouldHideLineNumber(for: lineRange(in: text, containing: "```\nAfter")))
        XCTAssertFalse(textView.shouldHideLineNumber(for: lineRange(in: text, containing: "let x = 1")))

        textView.attributedText = currentLineRendered
        XCTAssertFalse(textView.shouldHideLineNumber(for: lineRange(in: text, containing: "```swift")))
    }

    @MainActor
    func testHiddenSyntaxDoesNotSuppressSetextUnderlineLineNumber() {
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

        XCTAssertFalse(textView.shouldHideLineNumber(for: lineRange(in: text, containing: "=======")))
        XCTAssertFalse(textView.shouldHideLineNumber(for: lineRange(in: text, containing: "Heading")))
    }

    @MainActor
    func testHiddenSyntaxDoesNotSuppressHorizontalRuleLineNumber() throws {
        let text = "Before\n---\nAfter"
        let textView = makeHiddenSyntaxTextView(text: text, revealedText: "After")

        drawGutter(in: textView)

        XCTAssertFalse(textView.shouldHideLineNumber(for: lineRange(in: text, containing: "---")))
#if DEBUG
        XCTAssertNotNil(textView.lineNumberGutter?.lastDrawnLineNumberRects[2])
#endif
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
    private func makeHiddenSyntaxTextView(
        text: String,
        revealedText: String
    ) -> EditorChromeAwareTextView {
        let nsText = text as NSString
        return makeRenderedTextView(
            text: text,
            syntaxMode: .hiddenOutsideCurrentLine,
            revealedRange: nsText.lineRange(for: nsText.range(of: revealedText))
        )
    }

    @MainActor
    private func makeRenderedTextView(
        text: String,
        syntaxMode: MarkdownSyntaxMode,
        revealedRange: NSRange? = nil
    ) -> EditorChromeAwareTextView {
        let renderer = MarkdownStyledTextRenderer()
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: .monospacedSystemFont(ofSize: 16, weight: .regular),
                syntaxMode: syntaxMode,
                revealedRange: revealedRange
            )
        )
        let textView = makeTextView(text: text)
        textView.attributedText = rendered
        textView.layoutManager.ensureLayout(for: textView.textContainer)
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

    private var denstoneFixture: String {
        """
        # Denstone College


        Main Doors C6734Y

        ## South Boarding
        1st floor 1835X
        2nd floor 1435X
        Alarm - 1976
        Phone - 2348
        Safe - 1067#

        ## North Boarding
        North - 1864X
        """
    }
}

@MainActor
private extension ResolvedEditorTheme {
    func withEditorBackground(_ color: UIColor) -> ResolvedEditorTheme {
        withCoreEditorColors(
            background: color,
            primaryText: primaryText,
            tertiaryText: tertiaryText
        )
    }

    func withCoreEditorColors(
        background: UIColor,
        primaryText: UIColor,
        tertiaryText: UIColor
    ) -> ResolvedEditorTheme {
        ResolvedEditorTheme(
            editorBackground: background,
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
            horizontalRuleText: horizontalRuleText,
            checkboxUnchecked: checkboxUnchecked,
            checkboxChecked: checkboxChecked
        )
    }
}
