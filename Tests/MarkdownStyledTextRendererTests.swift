import UIKit
import XCTest
@testable import Downward

final class MarkdownStyledTextRendererTests: XCTestCase {
    private let renderer = MarkdownStyledTextRenderer()
    private let baseFont = UIFont.systemFont(ofSize: 16)

    @MainActor
    func testVisibleModeKeepsSyntaxVisibleAndStylesMarkdownContent() {
        let rendered = renderer.render(
            configuration: .init(
                text: "This is **Bold** and _italic_.",
                baseFont: baseFont,
                syntaxMode: .visible,
                revealedRange: nil
            )
        )

        let nsString = rendered.string as NSString
        let boldRange = nsString.range(of: "Bold")
        let italicRange = nsString.range(of: "italic")
        let openingBoldRange = nsString.range(of: "**")

        let boldFont = rendered.attribute(.font, at: boldRange.location, effectiveRange: nil) as? UIFont
        let italicFont = rendered.attribute(.font, at: italicRange.location, effectiveRange: nil) as? UIFont
        let syntaxColor = rendered.attribute(.foregroundColor, at: openingBoldRange.location, effectiveRange: nil) as? UIColor

        XCTAssertEqual(rendered.string, "This is **Bold** and _italic_.")
        XCTAssertTrue(boldFont?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        XCTAssertFalse(boldFont?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
        XCTAssertTrue(italicFont?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
        XCTAssertFalse(italicFont?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        XCTAssertEqual(syntaxColor, .secondaryLabel)
    }

    @MainActor
    func testTripleMarkerSyntaxRendersBoldItalicWithoutFallingBackToSingleMode() {
        let rendered = renderer.render(
            configuration: .init(
                text: "This is ***Both*** text.",
                baseFont: baseFont,
                syntaxMode: .visible,
                revealedRange: nil
            )
        )

        let nsString = rendered.string as NSString
        let contentRange = nsString.range(of: "Both")
        let font = rendered.attribute(.font, at: contentRange.location, effectiveRange: nil) as? UIFont

        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
    }

    @MainActor
    func testNestedStrongThenEmphasisSyntaxRendersBoldItalic() {
        let rendered = renderer.render(
            configuration: .init(
                text: "This is __*Both*__ text.",
                baseFont: baseFont,
                syntaxMode: .visible,
                revealedRange: nil
            )
        )

        let nsString = rendered.string as NSString
        let contentRange = nsString.range(of: "Both")
        let font = rendered.attribute(.font, at: contentRange.location, effectiveRange: nil) as? UIFont

        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
    }

    @MainActor
    func testNestedStrongThenUnderscoreEmphasisSyntaxRendersBoldItalic() {
        let rendered = renderer.render(
            configuration: .init(
                text: "This is **_Both_** text.",
                baseFont: baseFont,
                syntaxMode: .visible,
                revealedRange: nil
            )
        )

        let nsString = rendered.string as NSString
        let contentRange = nsString.range(of: "Both")
        let font = rendered.attribute(.font, at: contentRange.location, effectiveRange: nil) as? UIFont

        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
    }

    @MainActor
    func testHiddenSyntaxModeConcealsMarkersOutsideCurrentLine() {
        let text = """
        Hidden **bold**
        Revealed _italic_
        """
        let revealedRange = renderer.revealedLineRange(
            for: NSRange(location: (text as NSString).range(of: "Revealed").location, length: 0),
            in: text
        )
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                syntaxMode: .hiddenOutsideCurrentLine,
                revealedRange: revealedRange
            )
        )

        let nsString = rendered.string as NSString
        let hiddenMarkerRange = nsString.range(of: "**")
        let revealedMarkerRange = nsString.range(of: "_italic_")
        let hiddenMarkerIsSyntaxToken = rendered.attribute(.markdownSyntaxToken, at: hiddenMarkerRange.location, effectiveRange: nil) as? Bool
        let hiddenMarkerIsHidden = rendered.attribute(.markdownHiddenSyntax, at: hiddenMarkerRange.location, effectiveRange: nil) as? Bool
        let revealedMarkerIsHidden = rendered.attribute(.markdownHiddenSyntax, at: revealedMarkerRange.location, effectiveRange: nil) as? Bool

        XCTAssertEqual(hiddenMarkerIsSyntaxToken, true)
        XCTAssertEqual(hiddenMarkerIsHidden, true)
        XCTAssertNil(revealedMarkerIsHidden)
    }

    @MainActor
    func testLargeHiddenSyntaxMarksMarkersWithoutFontOrKerningCompaction() {
        let text = "Hidden **bold**\n" + String(repeating: "x", count: 120_001)
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                syntaxMode: .hiddenOutsideCurrentLine,
                revealedRange: nil
            )
        )

        let nsString = rendered.string as NSString
        let markerRange = nsString.range(of: "**")
        let markerIsHidden = rendered.attribute(.markdownHiddenSyntax, at: markerRange.location, effectiveRange: nil) as? Bool
        let markerFont = rendered.attribute(.font, at: markerRange.location, effectiveRange: nil) as? UIFont
        let markerKerning = rendered.attribute(.kern, at: NSMaxRange(markerRange) - 1, effectiveRange: nil)

        XCTAssertGreaterThan(nsString.length, 120_000)
        XCTAssertEqual(markerIsHidden, true)
        XCTAssertEqual(markerFont?.pointSize, baseFont.pointSize)
        XCTAssertNil(markerKerning)
    }

    @MainActor
    func testHiddenSyntaxVisibilityCanMoveBetweenLinesWithoutFullRerender() {
        let text = "Hidden **bold**\nRevealed _italic_"
        let firstLineRange = renderer.revealedLineRange(
            for: NSRange(location: (text as NSString).range(of: "Hidden").location, length: 0),
            in: text
        )
        let secondLineRange = renderer.revealedLineRange(
            for: NSRange(location: (text as NSString).range(of: "Revealed").location, length: 0),
            in: text
        )
        let rendered = NSTextStorage(
            attributedString: renderer.render(
                configuration: .init(
                    text: text,
                    baseFont: baseFont,
                    syntaxMode: .hiddenOutsideCurrentLine,
                    revealedRange: firstLineRange
                )
            )
        )

        renderer.updateHiddenSyntaxVisibility(
            in: rendered,
            previousRevealedRange: firstLineRange,
            revealedRange: secondLineRange
        )

        let nsString = rendered.string as NSString
        let firstLineMarkerRange = nsString.range(of: "**")
        let secondLineMarkerRange = nsString.range(of: "_italic_")
        let firstLineMarkerIsHidden = rendered.attribute(.markdownHiddenSyntax, at: firstLineMarkerRange.location, effectiveRange: nil) as? Bool
        let secondLineMarkerIsHidden = rendered.attribute(.markdownHiddenSyntax, at: secondLineMarkerRange.location, effectiveRange: nil) as? Bool

        XCTAssertEqual(firstLineMarkerIsHidden, true)
        XCTAssertNil(secondLineMarkerIsHidden)
    }

    @MainActor
    func testHeadingMarkersHideWhileHeadingContentKeepsStyledFont() {
        let text = "# Title"
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                syntaxMode: .hiddenOutsideCurrentLine,
                revealedRange: nil
            )
        )

        let nsString = rendered.string as NSString
        let markerRange = nsString.range(of: "#")
        let titleRange = nsString.range(of: "Title")
        let markerIsHidden = rendered.attribute(.markdownHiddenSyntax, at: markerRange.location, effectiveRange: nil) as? Bool
        let titleFont = rendered.attribute(.font, at: titleRange.location, effectiveRange: nil) as? UIFont

        XCTAssertEqual(markerIsHidden, true)
        XCTAssertGreaterThan(titleFont?.pointSize ?? 0, baseFont.pointSize)
        XCTAssertTrue(titleFont?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
    }

    @MainActor
    func testBlockquoteKeepsBodyTextReadableAndMarksQuoteDepth() {
        let text = "> Dorothy followed her through many of the beautiful rooms in her castle."
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                syntaxMode: .visible,
                revealedRange: nil
            )
        )

        let nsString = rendered.string as NSString
        let markerRange = nsString.range(of: ">")
        let contentRange = nsString.range(of: "Dorothy followed")
        let markerColor = rendered.attribute(.foregroundColor, at: markerRange.location, effectiveRange: nil) as? UIColor
        let contentFont = rendered.attribute(.font, at: contentRange.location, effectiveRange: nil) as? UIFont
        let quoteDepth = rendered.attribute(.markdownBlockquoteDepth, at: contentRange.location, effectiveRange: nil) as? Int
        let quoteGroupID = rendered.attribute(.markdownBlockquoteGroupID, at: contentRange.location, effectiveRange: nil) as? Int

        XCTAssertEqual(markerColor, .tertiaryLabel)
        XCTAssertFalse(contentFont?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
        XCTAssertEqual(quoteDepth, 1)
        XCTAssertNotNil(quoteGroupID)
    }

    @MainActor
    func testNestedBlockquotesPreserveDepthOnBlankAndNestedLines() {
        let text = """
        > Outer paragraph
        >
        >> Nested paragraph
        """
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                syntaxMode: .hiddenOutsideCurrentLine,
                revealedRange: nil
            )
        )

        let nsString = rendered.string as NSString
        let blankQuoteLineMarkerRange = nsString.range(of: ">\n")
        let nestedContentRange = nsString.range(of: "Nested paragraph")
        let outerContentRange = nsString.range(of: "Outer paragraph")
        let firstMarkerRange = nsString.range(of: ">")
        let blankQuoteDepth = rendered.attribute(.markdownBlockquoteDepth, at: blankQuoteLineMarkerRange.location, effectiveRange: nil) as? Int
        let nestedQuoteDepth = rendered.attribute(.markdownBlockquoteDepth, at: nestedContentRange.location, effectiveRange: nil) as? Int
        let outerGroupID = rendered.attribute(.markdownBlockquoteGroupID, at: outerContentRange.location, effectiveRange: nil) as? Int
        let nestedGroupID = rendered.attribute(.markdownBlockquoteGroupID, at: nestedContentRange.location, effectiveRange: nil) as? Int
        let hiddenMarkerIsHidden = rendered.attribute(.markdownHiddenSyntax, at: firstMarkerRange.location, effectiveRange: nil) as? Bool

        XCTAssertEqual(blankQuoteDepth, 1)
        XCTAssertEqual(nestedQuoteDepth, 2)
        XCTAssertEqual(outerGroupID, nestedGroupID)
        XCTAssertEqual(hiddenMarkerIsHidden, true)
    }

    @MainActor
    func testSetextHeadingStylesContentAndCanHideUnderlineSyntax() {
        let text = """
        Heading level 2
        ---------------
        """
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                syntaxMode: .hiddenOutsideCurrentLine,
                revealedRange: nil
            )
        )

        let nsString = rendered.string as NSString
        let titleRange = nsString.range(of: "Heading level 2")
        let underlineRange = nsString.range(of: "---------------")
        let titleFont = rendered.attribute(.font, at: titleRange.location, effectiveRange: nil) as? UIFont
        let underlineIsHidden = rendered.attribute(.markdownHiddenSyntax, at: underlineRange.location, effectiveRange: nil) as? Bool

        XCTAssertGreaterThan(titleFont?.pointSize ?? 0, baseFont.pointSize)
        XCTAssertTrue(titleFont?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        XCTAssertEqual(underlineIsHidden, true)
    }

    @MainActor
    func testIndentedCodeBlockUsesMonospacedFontAndDoesNotParseEmphasisInside() {
        let text = """
            **literal**
        """
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                syntaxMode: .visible,
                revealedRange: nil
            )
        )

        let nsString = rendered.string as NSString
        let markerRange = nsString.range(of: "**")
        let literalRange = nsString.range(of: "literal")
        let markerColor = rendered.attribute(.foregroundColor, at: markerRange.location, effectiveRange: nil) as? UIColor
        let codeFont = rendered.attribute(.font, at: literalRange.location, effectiveRange: nil) as? UIFont

        XCTAssertEqual(markerColor, .label)
        XCTAssertEqual(codeFont?.fontDescriptor.symbolicTraits.contains(.traitBold), false)
        XCTAssertEqual(codeFont?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace), true)
    }

    @MainActor
    func testFencedCodeBlockUsesMonospacedFontAndDoesNotParseEmphasisInside() {
        let text = """
        ```
        **literal**
        ```
        """
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                syntaxMode: .visible,
                revealedRange: nil
            )
        )

        let nsString = rendered.string as NSString
        let fenceRange = nsString.range(of: "```")
        let literalRange = nsString.range(of: "literal")
        let fenceIsHidden = rendered.attribute(.markdownHiddenSyntax, at: fenceRange.location, effectiveRange: nil) as? Bool
        let literalFont = rendered.attribute(.font, at: literalRange.location, effectiveRange: nil) as? UIFont
        let backgroundKind = rendered.attribute(.markdownCodeBackgroundKind, at: literalRange.location, effectiveRange: nil) as? Int
        let markerColor = rendered.attribute(.foregroundColor, at: nsString.range(of: "**").location, effectiveRange: nil) as? UIColor

        XCTAssertEqual(fenceIsHidden, true)
        XCTAssertEqual(literalFont?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace), true)
        XCTAssertEqual(literalFont?.fontDescriptor.symbolicTraits.contains(.traitBold), false)
        XCTAssertEqual(backgroundKind, MarkdownCodeBackgroundKind.block.rawValue)
        XCTAssertEqual(markerColor, .label)
    }

    @MainActor
    func testDoubleBacktickCodeSpanSupportsEmbeddedBackticks() {
        let text = "Use ``code `here` `` today."
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                syntaxMode: .visible,
                revealedRange: nil
            )
        )

        let nsString = rendered.string as NSString
        let openingMarkerRange = nsString.range(of: "``")
        let contentRange = nsString.range(of: "code `here` ")
        let font = rendered.attribute(.font, at: contentRange.location, effectiveRange: nil) as? UIFont
        let markerIsHidden = rendered.attribute(.markdownHiddenSyntax, at: openingMarkerRange.location, effectiveRange: nil) as? Bool
        let backgroundKind = rendered.attribute(.markdownCodeBackgroundKind, at: contentRange.location, effectiveRange: nil) as? Int

        XCTAssertEqual(font?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace), true)
        XCTAssertEqual(markerIsHidden, true)
        XCTAssertEqual(backgroundKind, MarkdownCodeBackgroundKind.inline.rawValue)
    }

    @MainActor
    func testEscapedMarkersStayLiteralInsteadOfTriggeringEmphasis() {
        let text = #"This is \*not italic\* text."#
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                syntaxMode: .visible,
                revealedRange: nil
            )
        )

        let nsString = rendered.string as NSString
        let contentRange = nsString.range(of: "not italic")
        let markerRange = nsString.range(of: #"\*"#)
        let font = rendered.attribute(.font, at: contentRange.location, effectiveRange: nil) as? UIFont
        let markerColor = rendered.attribute(.foregroundColor, at: markerRange.location, effectiveRange: nil) as? UIColor

        XCTAssertEqual(font?.fontDescriptor.symbolicTraits.contains(.traitItalic), false)
        XCTAssertEqual(markerColor, .label)
    }

    @MainActor
    func testListMarkersUseSecondaryTintWithoutHidingTheListStructure() {
        let text = "1. First item\n- Second item"
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                syntaxMode: .hiddenOutsideCurrentLine,
                revealedRange: nil
            )
        )

        let nsString = rendered.string as NSString
        let orderedMarkerRange = nsString.range(of: "1.")
        let unorderedMarkerRange = nsString.range(of: "-")
        let orderedMarkerColor = rendered.attribute(.foregroundColor, at: orderedMarkerRange.location, effectiveRange: nil) as? UIColor
        let unorderedMarkerColor = rendered.attribute(.foregroundColor, at: unorderedMarkerRange.location, effectiveRange: nil) as? UIColor

        XCTAssertEqual(orderedMarkerColor, .secondaryLabel)
        XCTAssertEqual(unorderedMarkerColor, .secondaryLabel)
    }

    @MainActor
    func testImageSyntaxCanHideMarkersWhileKeepingAltTextVisible() {
        let text = "![Mountains](/assets/mountains.jpg \"Mountain view\")"
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                syntaxMode: .hiddenOutsideCurrentLine,
                revealedRange: nil
            )
        )

        let nsString = rendered.string as NSString
        let markerRange = nsString.range(of: "![")
        let altTextRange = nsString.range(of: "Mountains")
        let sourceRange = nsString.range(of: "/assets/mountains.jpg \"Mountain view\"")
        let markerIsHidden = rendered.attribute(.markdownHiddenSyntax, at: markerRange.location, effectiveRange: nil) as? Bool
        let altTextFont = rendered.attribute(.font, at: altTextRange.location, effectiveRange: nil) as? UIFont
        let sourceIsHidden = rendered.attribute(.markdownHiddenSyntax, at: sourceRange.location, effectiveRange: nil) as? Bool

        XCTAssertEqual(markerIsHidden, true)
        XCTAssertTrue(altTextFont?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
        XCTAssertEqual(sourceIsHidden, true)
    }
}
