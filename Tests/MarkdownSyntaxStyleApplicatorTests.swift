import UIKit
import XCTest
@testable import Downward

@MainActor
final class MarkdownSyntaxStyleApplicatorTests: XCTestCase {
    private let baseFont = UIFont.systemFont(ofSize: 16)
    private let theme = ResolvedEditorTheme(
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
        horizontalRuleText: .systemGray
    )

    func testHeadingApplicationUsesHeadingFontThemeAndSyntaxVisibility() {
        let text = "# Heading"
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: hiddenApplicator.baseAttributes
        )
        let nsText = text as NSString

        hiddenApplicator.applyATXHeading(
            contentRange: nsText.range(of: "Heading"),
            markerRange: nsText.range(of: "#"),
            spacerRange: nsText.range(of: " "),
            level: 1,
            in: attributed
        )

        let headingRange = nsText.range(of: "Heading")
        let markerRange = nsText.range(of: "#")
        let headingFont = attributed.attribute(.font, at: headingRange.location, effectiveRange: nil) as? UIFont

        XCTAssertEqual(attributed.attribute(.foregroundColor, at: headingRange.location, effectiveRange: nil) as? UIColor, theme.headingText)
        XCTAssertGreaterThan(headingFont?.pointSize ?? 0, baseFont.pointSize)
        XCTAssertTrue(headingFont?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        XCTAssertEqual(attributed.attribute(.foregroundColor, at: markerRange.location, effectiveRange: nil) as? UIColor, theme.syntaxMarkerText)
        XCTAssertEqual(attributed.attribute(.markdownHiddenSyntax, at: markerRange.location, effectiveRange: nil) as? Bool, true)
    }

    func testInlineCodeApplicationUsesMonospaceCodeAttributesAndHiddenDelimiters() {
        let text = "Use `code` today."
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: hiddenApplicator.baseAttributes
        )
        let nsText = text as NSString
        let match = MarkdownCodeSpan(
            fullRange: nsText.range(of: "`code`"),
            contentRange: nsText.range(of: "code"),
            delimiterLength: 1
        )

        hiddenApplicator.applyInlineCode(match, in: attributed)

        let codeRange = nsText.range(of: "code")
        let delimiterRange = nsText.range(of: "`")
        let codeFont = attributed.attribute(.font, at: codeRange.location, effectiveRange: nil) as? UIFont

        XCTAssertTrue(codeFont?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true)
        XCTAssertEqual(attributed.attribute(.foregroundColor, at: codeRange.location, effectiveRange: nil) as? UIColor, theme.inlineCodeText)
        XCTAssertEqual(
            attributed.attribute(.markdownCodeBackgroundKind, at: codeRange.location, effectiveRange: nil) as? Int,
            MarkdownCodeBackgroundKind.inline.rawValue
        )
        XCTAssertEqual(attributed.attribute(.markdownHiddenSyntax, at: delimiterRange.location, effectiveRange: nil) as? Bool, true)
    }

    func testLinkAndImageApplicationPreserveTextAndUseExpectedThemeRoles() {
        let text = "[Site](https://example.com)\n![Alt](/image.png)"
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: visibleApplicator.baseAttributes
        )
        let nsText = text as NSString
        let linkFullRange = nsText.range(of: "[Site](https://example.com)")
        let linkTitleRange = nsText.range(of: "Site")

        visibleApplicator.applyLink(
            titleRange: linkTitleRange,
            hiddenRanges: [
                NSRange(location: linkFullRange.location, length: 1),
                NSRange(location: NSMaxRange(linkTitleRange), length: 2),
                nsText.range(of: "https://example.com"),
                NSRange(location: NSMaxRange(linkFullRange) - 1, length: 1)
            ],
            in: attributed
        )
        visibleApplicator.applyImage(
            altTextRange: nsText.range(of: "Alt"),
            hiddenRanges: [
                nsText.range(of: "!["),
                NSRange(location: NSMaxRange(nsText.range(of: "Alt")), length: 2),
                nsText.range(of: "/image.png"),
                NSRange(location: NSMaxRange(nsText.range(of: "![Alt](/image.png")) - 1, length: 1)
            ],
            in: attributed
        )

        let linkRange = nsText.range(of: "Site")
        let imageAltRange = nsText.range(of: "Alt")
        let imageAltFont = attributed.attribute(.font, at: imageAltRange.location, effectiveRange: nil) as? UIFont

        XCTAssertEqual(attributed.string, text)
        XCTAssertEqual(attributed.attribute(.foregroundColor, at: linkRange.location, effectiveRange: nil) as? UIColor, theme.linkText)
        XCTAssertEqual(attributed.attribute(.underlineStyle, at: linkRange.location, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(attributed.attribute(.foregroundColor, at: imageAltRange.location, effectiveRange: nil) as? UIColor, theme.imageAltText)
        XCTAssertTrue(imageAltFont?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
        XCTAssertNil(attributed.attribute(.markdownHiddenSyntax, at: nsText.range(of: "https://example.com").location, effectiveRange: nil))
    }

    func testInlineContentApplicationStylesEmphasisAndMarksOnlyProvidedSyntaxRanges() {
        let text = "**bold** plain"
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: hiddenApplicator.baseAttributes
        )
        let nsText = text as NSString
        let contentRange = nsText.range(of: "bold")
        let openingMarkerRange = nsText.range(of: "**")
        let closingMarkerRange = NSRange(location: NSMaxRange(contentRange), length: 2)

        hiddenApplicator.applyInlineContent(
            range: contentRange,
            in: attributed,
            transform: { [hiddenApplicator] font in
                hiddenApplicator.transformedFont(font, adding: .traitBold)
                    ?? UIFont.boldSystemFont(ofSize: font.pointSize)
            },
            additionalAttributes: [.foregroundColor: theme.emphasisText]
        )
        hiddenApplicator.applySyntaxMarkerRanges(
            [openingMarkerRange, closingMarkerRange],
            in: attributed
        )

        let contentFont = attributed.attribute(.font, at: contentRange.location, effectiveRange: nil) as? UIFont
        let plainRange = nsText.range(of: "plain")

        XCTAssertTrue(contentFont?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        XCTAssertEqual(attributed.attribute(.foregroundColor, at: contentRange.location, effectiveRange: nil) as? UIColor, theme.emphasisText)
        XCTAssertEqual(attributed.attribute(.markdownHiddenSyntax, at: openingMarkerRange.location, effectiveRange: nil) as? Bool, true)
        XCTAssertNil(attributed.attribute(.markdownHiddenSyntax, at: plainRange.location, effectiveRange: nil))
    }

    private var visibleApplicator: MarkdownSyntaxStyleApplicator {
        MarkdownSyntaxStyleApplicator(
            baseFont: baseFont,
            resolvedTheme: theme,
            syntaxMode: .visible,
            revealedRange: nil
        )
    }

    private var hiddenApplicator: MarkdownSyntaxStyleApplicator {
        MarkdownSyntaxStyleApplicator(
            baseFont: baseFont,
            resolvedTheme: theme,
            syntaxMode: .hiddenOutsideCurrentLine,
            revealedRange: nil
        )
    }
}
