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
        let hiddenMarkerColor = rendered.attribute(.foregroundColor, at: hiddenMarkerRange.location, effectiveRange: nil) as? UIColor
        let hiddenMarkerFont = rendered.attribute(.font, at: hiddenMarkerRange.location, effectiveRange: nil) as? UIFont
        let revealedMarkerColor = rendered.attribute(.foregroundColor, at: revealedMarkerRange.location, effectiveRange: nil) as? UIColor

        XCTAssertEqual(hiddenMarkerColor, .clear)
        XCTAssertEqual(hiddenMarkerFont?.pointSize, 0.1)
        XCTAssertNotEqual(revealedMarkerColor, UIColor.clear)
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
        let markerColor = rendered.attribute(.foregroundColor, at: markerRange.location, effectiveRange: nil) as? UIColor
        let titleFont = rendered.attribute(.font, at: titleRange.location, effectiveRange: nil) as? UIFont

        XCTAssertEqual(markerColor, .clear)
        XCTAssertGreaterThan(titleFont?.pointSize ?? 0, baseFont.pointSize)
        XCTAssertTrue(titleFont?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
    }
}
