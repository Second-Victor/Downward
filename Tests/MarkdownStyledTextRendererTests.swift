import UIKit
import XCTest
@testable import Downward

final class MarkdownStyledTextRendererTests: XCTestCase {
    private let renderer = MarkdownStyledTextRenderer()
    private let baseFont = UIFont.systemFont(ofSize: 16)
    private let customTheme = ResolvedEditorTheme(
        editorBackground: .black,
        keyboardAccessoryUnderlayBackground: .brown,
        accent: .orange,
        primaryText: .red,
        secondaryText: .green,
        tertiaryText: .blue,
        headingText: .purple,
        emphasisText: .magenta,
        strikethroughText: .brown,
        syntaxMarkerText: .cyan,
        subtleSyntaxMarkerText: .yellow,
        linkText: .orange,
        imageAltText: .systemPink,
        inlineCodeText: .systemTeal,
        inlineCodeBackground: .darkGray,
        codeBlockText: .white,
        codeBlockBackground: .gray,
        blockquoteText: .systemMint,
        blockquoteBackground: .lightGray,
        blockquoteBar: .systemIndigo,
        horizontalRuleText: .systemGray,
        checkboxUnchecked: .systemRed,
        checkboxChecked: .systemGreen
    )

    private func syntaxVisibilityRule(
        in attributed: NSAttributedString,
        at range: NSRange
    ) -> MarkdownSyntaxVisibilityRule? {
        guard range.location != NSNotFound else {
            return nil
        }
        guard let rawValue = attributed.attribute(.markdownSyntaxToken, at: range.location, effectiveRange: nil) as? Int else {
            return nil
        }
        return MarkdownSyntaxVisibilityRule(rawValue: rawValue)
    }

    private func hiddenSyntaxValue(
        in attributed: NSAttributedString,
        at range: NSRange
    ) -> Bool? {
        guard range.location != NSNotFound else {
            return nil
        }
        return attributed.attribute(.markdownHiddenSyntax, at: range.location, effectiveRange: nil) as? Bool
    }

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
    func testRendererUsesResolvedThemeRolesForMarkdownStyling() {
        let text = """
        # Heading
        This is **bold** and ~~gone~~ and `code`.
        > Quote
        [Site](https://example.com)
        ![Alt](/image.png)
        """
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                resolvedTheme: customTheme,
                syntaxMode: .visible,
                revealedRange: nil
            )
        )

        let nsString = rendered.string as NSString
        let headingRange = nsString.range(of: "Heading")
        let headingMarkerRange = nsString.range(of: "#")
        let boldRange = nsString.range(of: "bold")
        let boldMarkerRange = nsString.range(of: "**")
        let strikethroughRange = nsString.range(of: "gone")
        let codeRange = nsString.range(of: "code")
        let quoteMarkerRange = nsString.range(of: ">")
        let quoteTextRange = nsString.range(of: "Quote")
        let linkRange = nsString.range(of: "Site")
        let imageAltRange = nsString.range(of: "Alt")

        XCTAssertEqual(rendered.attribute(.foregroundColor, at: headingRange.location, effectiveRange: nil) as? UIColor, customTheme.headingText)
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: headingMarkerRange.location, effectiveRange: nil) as? UIColor, customTheme.syntaxMarkerText)
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: boldRange.location, effectiveRange: nil) as? UIColor, customTheme.emphasisText)
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: boldMarkerRange.location, effectiveRange: nil) as? UIColor, customTheme.syntaxMarkerText)
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: strikethroughRange.location, effectiveRange: nil) as? UIColor, customTheme.strikethroughText)
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: codeRange.location, effectiveRange: nil) as? UIColor, customTheme.inlineCodeText)
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: quoteMarkerRange.location, effectiveRange: nil) as? UIColor, customTheme.subtleSyntaxMarkerText)
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: quoteTextRange.location, effectiveRange: nil) as? UIColor, customTheme.blockquoteText)
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: linkRange.location, effectiveRange: nil) as? UIColor, customTheme.linkText)
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: imageAltRange.location, effectiveRange: nil) as? UIColor, customTheme.imageAltText)
        XCTAssertEqual(
            rendered.attribute(.markdownCodeBackgroundKind, at: codeRange.location, effectiveRange: nil) as? Int,
            MarkdownCodeBackgroundKind.inline.rawValue
        )
    }

    @MainActor
    func testVisibleModeKeepsModeControlledSyntaxVisibleForHeadingsEmphasisLinksAndImages() {
        let text = """
        # Heading
        This is **bold**
        [Site](https://example.com)
        ![Alt](/image.png)
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
        let headingMarkerRange = nsString.range(of: "#")
        let emphasisMarkerRange = nsString.range(of: "**")
        let linkOpeningRange = nsString.range(of: "[Site]")
        let linkSourceRange = nsString.range(of: "https://example.com")
        let imageMarkerRange = nsString.range(of: "![")
        let imageSourceRange = nsString.range(of: "/image.png")

        XCTAssertEqual(syntaxVisibilityRule(in: rendered, at: headingMarkerRange), .followsMode)
        XCTAssertNil(hiddenSyntaxValue(in: rendered, at: headingMarkerRange))
        XCTAssertEqual(syntaxVisibilityRule(in: rendered, at: emphasisMarkerRange), .followsMode)
        XCTAssertNil(hiddenSyntaxValue(in: rendered, at: emphasisMarkerRange))
        XCTAssertEqual(syntaxVisibilityRule(in: rendered, at: linkOpeningRange), .followsMode)
        XCTAssertNil(hiddenSyntaxValue(in: rendered, at: linkOpeningRange))
        XCTAssertEqual(syntaxVisibilityRule(in: rendered, at: linkSourceRange), .followsMode)
        XCTAssertNil(hiddenSyntaxValue(in: rendered, at: linkSourceRange))
        XCTAssertEqual(syntaxVisibilityRule(in: rendered, at: imageMarkerRange), .followsMode)
        XCTAssertNil(hiddenSyntaxValue(in: rendered, at: imageMarkerRange))
        XCTAssertEqual(syntaxVisibilityRule(in: rendered, at: imageSourceRange), .followsMode)
        XCTAssertNil(hiddenSyntaxValue(in: rendered, at: imageSourceRange))
    }

    @MainActor
    func testHiddenModeHidesModeControlledSyntaxOutsideTheRevealedLineForHeadingsEmphasisLinksAndImages() {
        let text = """
        # Heading
        This is **bold**
        [Site](https://example.com)
        ![Alt](/image.png)
        """
        let revealedRange = renderer.revealedLineRange(
            for: NSRange(location: 0, length: 0),
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
        let headingMarkerRange = nsString.range(of: "#")
        let emphasisMarkerRange = nsString.range(of: "**")
        let linkOpeningRange = nsString.range(of: "[Site]")
        let linkSourceRange = nsString.range(of: "https://example.com")
        let imageMarkerRange = nsString.range(of: "![")
        let imageSourceRange = nsString.range(of: "/image.png")

        XCTAssertEqual(hiddenSyntaxValue(in: rendered, at: headingMarkerRange), nil)
        XCTAssertEqual(hiddenSyntaxValue(in: rendered, at: emphasisMarkerRange), true)
        XCTAssertEqual(hiddenSyntaxValue(in: rendered, at: linkOpeningRange), true)
        XCTAssertEqual(hiddenSyntaxValue(in: rendered, at: linkSourceRange), true)
        XCTAssertEqual(hiddenSyntaxValue(in: rendered, at: imageMarkerRange), true)
        XCTAssertEqual(hiddenSyntaxValue(in: rendered, at: imageSourceRange), true)
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
        let hiddenMarkerRule = syntaxVisibilityRule(in: rendered, at: hiddenMarkerRange)
        let hiddenMarkerIsHidden = hiddenSyntaxValue(in: rendered, at: hiddenMarkerRange)
        let revealedMarkerIsHidden = hiddenSyntaxValue(in: rendered, at: revealedMarkerRange)

        XCTAssertEqual(hiddenMarkerRule, .followsMode)
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
    func testHiddenSyntaxVisibilitySkipsNoOpInvalidation() {
        let text = "Hidden **bold**\nRevealed _italic_"
        let firstLineRange = renderer.revealedLineRange(
            for: NSRange(location: (text as NSString).range(of: "Hidden").location, length: 0),
            in: text
        )
        guard let firstLineRange else {
            return XCTFail("Expected a revealed first-line range")
        }
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
        let layoutManager = LayoutInvalidationSpy()
        rendered.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(NSTextContainer(size: CGSize(width: 320, height: 640)))

        renderer.updateHiddenSyntaxVisibility(
            in: rendered,
            previousRevealedRange: firstLineRange,
            revealedRange: firstLineRange
        )

        XCTAssertTrue(layoutManager.invalidatedLayoutRanges.isEmpty)
        XCTAssertTrue(layoutManager.invalidatedDisplayRanges.isEmpty)
    }

    @MainActor
    func testHiddenSyntaxVisibilityInvalidatesOnlyChangedSyntaxRanges() {
        let text = "Hidden **bold**\nRevealed _italic_"
        let firstLineRange = renderer.revealedLineRange(
            for: NSRange(location: (text as NSString).range(of: "Hidden").location, length: 0),
            in: text
        )
        let secondLineRange = renderer.revealedLineRange(
            for: NSRange(location: (text as NSString).range(of: "Revealed").location, length: 0),
            in: text
        )
        guard let firstLineRange, let secondLineRange else {
            return XCTFail("Expected revealed ranges for both lines")
        }
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
        let layoutManager = LayoutInvalidationSpy()
        rendered.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(NSTextContainer(size: CGSize(width: 320, height: 640)))

        renderer.updateHiddenSyntaxVisibility(
            in: rendered,
            previousRevealedRange: firstLineRange,
            revealedRange: secondLineRange
        )

        let affectedRangeLength = NSUnionRange(firstLineRange, secondLineRange).length
        XCTAssertFalse(layoutManager.invalidatedLayoutRanges.isEmpty)
        XCTAssertTrue(layoutManager.invalidatedLayoutRanges.allSatisfy { $0.length < affectedRangeLength })
        XCTAssertTrue(
            layoutManager.invalidatedLayoutRanges.allSatisfy { layoutManager.invalidatedDisplayRanges.contains($0) }
        )
    }

    @MainActor
    func testHeadingMarkersHideWhileHeadingContentKeepsStyledFont() {
        let text = "# Title"
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                syntaxMode: .hiddenOutsideCurrentLine,
                revealedRange: nil,
                largerHeadingText: true
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
    func testHeadingContentKeepsBaseSizeWhenLargerHeadingTextIsDisabled() {
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
        let titleRange = nsString.range(of: "Title")
        let titleFont = rendered.attribute(.font, at: titleRange.location, effectiveRange: nil) as? UIFont

        XCTAssertEqual(titleFont?.pointSize, baseFont.pointSize)
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
                revealedRange: nil,
                largerHeadingText: true
            )
        )

        let nsString = rendered.string as NSString
        let titleRange = nsString.range(of: "Heading level 2")
        let underlineRange = nsString.range(of: "---------------")
        let titleFont = rendered.attribute(.font, at: titleRange.location, effectiveRange: nil) as? UIFont
        let underlineIsHidden = rendered.attribute(.markdownHiddenSyntax, at: underlineRange.location, effectiveRange: nil) as? Bool
        let underlineIsMarked = rendered.attribute(.markdownSetextHeadingUnderline, at: underlineRange.location, effectiveRange: nil) as? Bool

        XCTAssertGreaterThan(titleFont?.pointSize ?? 0, baseFont.pointSize)
        XCTAssertTrue(titleFont?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        XCTAssertEqual(underlineIsHidden, true)
        XCTAssertEqual(underlineIsMarked, true)
    }

    @MainActor
    func testHorizontalRuleUsesThemeRoleAndMarksLineForDrawing() {
        let text = """
        Before

        ---

        After
        """
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                resolvedTheme: customTheme,
                syntaxMode: .visible,
                revealedRange: nil
            )
        )

        let nsString = rendered.string as NSString
        let ruleRange = nsString.range(of: "---")
        let ruleColor = rendered.attribute(.foregroundColor, at: ruleRange.location, effectiveRange: nil) as? UIColor
        let isHorizontalRule = rendered.attribute(.markdownHorizontalRule, at: ruleRange.location, effectiveRange: nil) as? Bool

        XCTAssertEqual(ruleColor, customTheme.horizontalRuleText)
        XCTAssertEqual(isHorizontalRule, true)
    }

    @MainActor
    func testHorizontalRuleSyntaxCanHideWhileKeepingDrawMarker() {
        let text = """
        Before

        ---

        After
        """
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                resolvedTheme: customTheme,
                syntaxMode: .hiddenOutsideCurrentLine,
                revealedRange: nil
            )
        )

        let nsString = rendered.string as NSString
        let ruleRange = nsString.range(of: "---")
        let isHiddenSyntax = rendered.attribute(.markdownHiddenSyntax, at: ruleRange.location, effectiveRange: nil) as? Bool
        let isHorizontalRule = rendered.attribute(.markdownHorizontalRule, at: ruleRange.location, effectiveRange: nil) as? Bool

        XCTAssertEqual(isHiddenSyntax, true)
        XCTAssertEqual(isHorizontalRule, true)
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

        XCTAssertNil(fenceIsHidden)
        XCTAssertEqual(literalFont?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace), true)
        XCTAssertEqual(literalFont?.fontDescriptor.symbolicTraits.contains(.traitBold), false)
        XCTAssertEqual(backgroundKind, MarkdownCodeBackgroundKind.block.rawValue)
        XCTAssertEqual(markerColor, .label)
    }

    @MainActor
    func testInlineCodeDelimitersFollowSyntaxModeAndRevealOnCurrentLine() {
        let text = "Use `code` today."
        let visibleRendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                syntaxMode: .visible,
                revealedRange: nil
            )
        )
        let hiddenOffLineRendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                syntaxMode: .hiddenOutsideCurrentLine,
                revealedRange: nil
            )
        )
        let hiddenRendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                syntaxMode: .hiddenOutsideCurrentLine,
                revealedRange: renderer.revealedLineRange(for: NSRange(location: 0, length: 0), in: text)
            )
        )

        let delimiterRange = (visibleRendered.string as NSString).range(of: "`")

        XCTAssertEqual(syntaxVisibilityRule(in: visibleRendered, at: delimiterRange), .followsMode)
        XCTAssertNil(hiddenSyntaxValue(in: visibleRendered, at: delimiterRange))
        XCTAssertEqual(hiddenSyntaxValue(in: hiddenOffLineRendered, at: delimiterRange), true)
        XCTAssertEqual(syntaxVisibilityRule(in: hiddenRendered, at: delimiterRange), .followsMode)
        XCTAssertNil(hiddenSyntaxValue(in: hiddenRendered, at: delimiterRange))
    }

    @MainActor
    func testFencedCodeFencesFollowSyntaxModeAndRevealOnCurrentLine() {
        let text = """
        ```
        code
        ```
        """
        let visibleRendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                syntaxMode: .visible,
                revealedRange: nil
            )
        )
        let hiddenOffLineRendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                syntaxMode: .hiddenOutsideCurrentLine,
                revealedRange: nil
            )
        )
        let hiddenRendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                syntaxMode: .hiddenOutsideCurrentLine,
                revealedRange: renderer.revealedLineRange(for: NSRange(location: 0, length: 0), in: text)
            )
        )

        let fenceRange = (visibleRendered.string as NSString).range(of: "```")

        XCTAssertEqual(syntaxVisibilityRule(in: visibleRendered, at: fenceRange), .followsMode)
        XCTAssertNil(hiddenSyntaxValue(in: visibleRendered, at: fenceRange))
        XCTAssertEqual(hiddenSyntaxValue(in: hiddenOffLineRendered, at: fenceRange), true)
        XCTAssertEqual(syntaxVisibilityRule(in: hiddenRendered, at: fenceRange), .followsMode)
        XCTAssertNil(hiddenSyntaxValue(in: hiddenRendered, at: fenceRange))
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
        XCTAssertNil(markerIsHidden)
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
    func testTaskListDashUsesAccentWhileOrdinaryListMarkerUsesSyntaxMarkerColor() {
        let text = "- [ ] Task\n- Ordinary item\n1. [x] Ordered task"
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                resolvedTheme: customTheme,
                syntaxMode: .visible,
                revealedRange: nil
            )
        )

        let nsString = rendered.string as NSString
        let taskDashRange = nsString.range(of: "- [ ]")
        let uncheckedCheckboxRange = nsString.range(of: "[ ]")
        let ordinaryDashRange = nsString.range(of: "- Ordinary")
        let orderedTaskMarkerRange = nsString.range(of: "1. [x]")
        let checkedCheckboxRange = nsString.range(of: "[x]")

        XCTAssertEqual(
            rendered.attribute(.foregroundColor, at: taskDashRange.location, effectiveRange: nil) as? UIColor,
            customTheme.accent
        )
        XCTAssertEqual(
            rendered.attribute(.foregroundColor, at: uncheckedCheckboxRange.location, effectiveRange: nil) as? UIColor,
            customTheme.checkboxUnchecked
        )
        XCTAssertEqual(
            rendered.attribute(.markdownTaskCheckbox, at: uncheckedCheckboxRange.location, effectiveRange: nil) as? Bool,
            true
        )
        XCTAssertEqual(
            rendered.attribute(.foregroundColor, at: ordinaryDashRange.location, effectiveRange: nil) as? UIColor,
            customTheme.syntaxMarkerText
        )
        XCTAssertEqual(
            rendered.attribute(.foregroundColor, at: orderedTaskMarkerRange.location, effectiveRange: nil) as? UIColor,
            customTheme.accent
        )
        XCTAssertEqual(
            rendered.attribute(.foregroundColor, at: checkedCheckboxRange.location, effectiveRange: nil) as? UIColor,
            customTheme.checkboxChecked
        )
    }

    @MainActor
    func testSlashTaskStateStylesBracketsAsCheckedAndSlashAsUnchecked() {
        let text = "- [/] Partial task"
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                resolvedTheme: customTheme,
                syntaxMode: .visible,
                revealedRange: nil
            )
        )

        let nsString = rendered.string as NSString
        let markerRange = nsString.range(of: "-")
        let openBracketRange = nsString.range(of: "[")
        let slashRange = nsString.range(of: "/")
        let closeBracketRange = nsString.range(of: "]")

        XCTAssertEqual(
            rendered.attribute(.foregroundColor, at: markerRange.location, effectiveRange: nil) as? UIColor,
            customTheme.accent
        )
        XCTAssertEqual(
            rendered.attribute(.foregroundColor, at: openBracketRange.location, effectiveRange: nil) as? UIColor,
            customTheme.checkboxChecked
        )
        XCTAssertEqual(
            rendered.attribute(.foregroundColor, at: slashRange.location, effectiveRange: nil) as? UIColor,
            customTheme.checkboxUnchecked
        )
        XCTAssertEqual(
            rendered.attribute(.foregroundColor, at: closeBracketRange.location, effectiveRange: nil) as? UIColor,
            customTheme.checkboxChecked
        )
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

    @MainActor
    func testLargeDocumentRenderPerformance() {
        let text = makeLargeMarkdownDocument(lineCount: 1_000)

        measure(metrics: [XCTClockMetric()]) {
            let rendered = renderer.render(
                configuration: .init(
                    text: text,
                    baseFont: baseFont,
                    syntaxMode: .hiddenOutsideCurrentLine,
                    revealedRange: nil
                )
            )

            XCTAssertEqual(rendered.length, (text as NSString).length)
        }
    }

    @MainActor
    func testStructuralSyntaxLinesDoNotHideLineNumbersWhenSyntaxIsHidden() {
        let text = """
        Heading
        =======

        ```swift
        let x = 1
        ```

        ---
        """
        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: baseFont,
                syntaxMode: .hiddenOutsideCurrentLine,
                revealedRange: nil
            )
        )
        let nsText = rendered.string as NSString

        XCTAssertNil(lineNumberHiddenAttribute(in: rendered, at: nsText.range(of: "=======")))
        XCTAssertNil(lineNumberHiddenAttribute(in: rendered, at: nsText.range(of: "```swift")))
        XCTAssertNil(lineNumberHiddenAttribute(in: rendered, at: nsText.range(of: "```\n\n---")))
        XCTAssertNil(lineNumberHiddenAttribute(in: rendered, at: nsText.range(of: "let x = 1")))
        XCTAssertNil(lineNumberHiddenAttribute(in: rendered, at: nsText.range(of: "---")))
    }

    private func makeLargeMarkdownDocument(lineCount: Int) -> String {
        (0..<lineCount).map { index in
            switch index % 5 {
            case 0:
                return "## Heading \(index)"
            case 1:
                return "- [ ] Task \(index) with **bold** and _italic_ text"
            case 2:
                return "> Quote \(index) with [link](https://example.com/\(index))"
            case 3:
                return "`inline code \(index)` and ~~removed text~~"
            default:
                return "Plain paragraph \(index) with enough words to resemble normal markdown editing."
            }
        }
        .joined(separator: "\n")
    }

    private func lineNumberHiddenAttribute(in attributed: NSAttributedString, at range: NSRange) -> Bool? {
        guard range.location != NSNotFound else {
            return nil
        }

        return attributed.attribute(
            .markdownLineNumberHiddenWhenSyntaxHidden,
            at: range.location,
            effectiveRange: nil
        ) as? Bool
    }
}

private final class LayoutInvalidationSpy: NSLayoutManager {
    var invalidatedLayoutRanges: [NSRange] = []
    var invalidatedDisplayRanges: [NSRange] = []

    override func invalidateLayout(forCharacterRange charRange: NSRange, actualCharacterRange actualCharRange: NSRangePointer?) {
        invalidatedLayoutRanges.append(charRange)
        super.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: actualCharRange)
    }

    override func invalidateDisplay(forCharacterRange charRange: NSRange) {
        invalidatedDisplayRanges.append(charRange)
        super.invalidateDisplay(forCharacterRange: charRange)
    }
}
