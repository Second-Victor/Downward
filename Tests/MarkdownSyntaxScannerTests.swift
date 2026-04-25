import Foundation
import XCTest
@testable import Downward

final class MarkdownSyntaxScannerTests: XCTestCase {
    private let scanner = MarkdownSyntaxScanner()

    func testLineRangesIncludeLineEndingsAndFinalLine() {
        let text = "one\ntwo\r\nthree"

        XCTAssertEqual(
            scanner.lineRanges(in: text),
            [
                NSRange(location: 0, length: 4),
                NSRange(location: 4, length: 5),
                NSRange(location: 9, length: 5)
            ]
        )
    }

    func testIndentedCodeBlockRecognitionSkipsIndentedListItems() {
        let text = "paragraph\n    code\n\tmore\n    - list item\nplain"
        let scan = scanner.scan(text)
        let nsText = text as NSString

        XCTAssertEqual(scan.indentedCodeBlockRanges.count, 1)
        XCTAssertEqual(nsText.substring(with: scan.indentedCodeBlockRanges[0]), "    code\n\tmore\n")
    }

    func testFencedCodeBlockRecognitionIncludesFenceMetadata() {
        let text = "before\n```swift\n**literal**\n```\nafter"
        let scan = scanner.scan(text)
        let nsText = text as NSString

        XCTAssertEqual(scan.fencedCodeBlocks.count, 1)
        let block = scan.fencedCodeBlocks[0]
        XCTAssertEqual(nsText.substring(with: block.fullRange), "```swift\n**literal**\n```\n")
        XCTAssertEqual(nsText.substring(with: block.contentRange), "**literal**\n")
        XCTAssertEqual(nsText.substring(with: block.openingFenceRange), "```swift")
        XCTAssertEqual(block.closingFenceRange.map { nsText.substring(with: $0) }, "```")
    }

    func testInlineCodeSpansSupportSingleAndDoubleBacktickDelimiters() {
        let text = "Use `code` and ``code `here` `` today."
        let scan = scanner.scan(text)
        let nsText = text as NSString

        XCTAssertEqual(scan.inlineCodeSpans.count, 2)
        XCTAssertEqual(nsText.substring(with: scan.inlineCodeSpans[0].contentRange), "code")
        XCTAssertEqual(scan.inlineCodeSpans[0].delimiterLength, 1)
        XCTAssertEqual(nsText.substring(with: scan.inlineCodeSpans[1].contentRange), "code `here` ")
        XCTAssertEqual(scan.inlineCodeSpans[1].delimiterLength, 2)
    }

    func testInlineParsingCanIgnoreProtectedCodeAndImageRanges() {
        let text = "`**literal**` and ![**alt**](/image.png) and **styled** and [Link](https://example.com)"
        let scan = scanner.scan(text)
        let protectedRanges = scan.codeBlockRanges + scan.inlineCodeSpans.map(\.fullRange) + scan.imageRanges
        let boldRanges = scanner.inlineRanges(
            matching: [#"(?<!\*)\*\*(?=\S)(.+?)(?<=\S)\*\*(?!\*)"#],
            in: text,
            protectedRanges: protectedRanges
        )
        let linkRanges = scanner.inlineRanges(
            matching: [#"\[([^\]]+)\]\(([^)]+)\)"#],
            in: text,
            protectedRanges: protectedRanges
        )
        let nsText = text as NSString

        XCTAssertEqual(boldRanges.map { nsText.substring(with: $0) }, ["**styled**"])
        XCTAssertEqual(linkRanges.map { nsText.substring(with: $0) }, ["[Link](https://example.com)"])
    }

    func testImageRangesSkipProtectedCodeRanges() {
        let text = "`![literal](/code.png)` and ![Alt](/real.png)"
        let scan = scanner.scan(text)
        let nsText = text as NSString

        XCTAssertEqual(scan.imageRanges.map { nsText.substring(with: $0) }, ["![Alt](/real.png)"])
    }

    func testSyntaxVisibilityPolicyHidesOnlyModeControlledUnrevealedSyntax() {
        let syntaxRange = NSRange(location: 10, length: 2)

        XCTAssertFalse(
            MarkdownSyntaxVisibilityPolicy(syntaxMode: .visible, revealedRange: nil)
                .shouldHideSyntax(in: syntaxRange, rule: .followsMode)
        )
        XCTAssertFalse(
            MarkdownSyntaxVisibilityPolicy(
                syntaxMode: .hiddenOutsideCurrentLine,
                revealedRange: NSRange(location: 8, length: 10)
            )
            .shouldHideSyntax(in: syntaxRange, rule: .followsMode)
        )
        XCTAssertTrue(
            MarkdownSyntaxVisibilityPolicy(syntaxMode: .hiddenOutsideCurrentLine, revealedRange: nil)
                .shouldHideSyntax(in: syntaxRange, rule: .followsMode)
        )
        XCTAssertTrue(
            MarkdownSyntaxVisibilityPolicy(syntaxMode: .visible, revealedRange: nil)
                .shouldHideSyntax(in: syntaxRange, rule: .alwaysHidden)
        )
    }
}
