import Foundation
import XCTest
@testable import Downward

final class MarkdownFormattingPlanTests: XCTestCase {
    func testLinePrefixPlanPreservesLineEndingsWhenApplyingAndRemovingPrefix() {
        let cases = [
            "one\ntwo",
            "one\r\ntwo",
            "one\rtwo",
            "one\r\ntwo\r\n"
        ]

        for text in cases {
            let applied = MarkdownLinePrefixPlan.make(prefix: "> ", selectedText: text).replacement
            let removed = MarkdownLinePrefixPlan.make(prefix: "> ", selectedText: applied).replacement

            XCTAssertEqual(removed, text)
            XCTAssertEqual(lineEndings(in: applied), lineEndings(in: text))
        }
    }

    func testCodeBlockPlanWrapsSelectedTextInFences() {
        let plan = MarkdownCodeBlockPlan.make(selectedText: "let value = 1")

        XCTAssertEqual(plan.replacement, "```\nlet value = 1\n```")
        XCTAssertEqual(plan.selectedRangeInReplacement, NSRange(location: 4, length: 13))
    }

    func testCodeBlockPlanPlacesCursorInsideEmptyBlock() {
        let plan = MarkdownCodeBlockPlan.make(selectedText: "")

        XCTAssertEqual(plan.replacement, "```\n\n```\n")
        XCTAssertEqual(plan.selectedRangeInReplacement, NSRange(location: 4, length: 0))
    }

    func testCodeBlockPlanPreservesSelectedLineEndings() {
        let plan = MarkdownCodeBlockPlan.make(selectedText: "one\r\ntwo")

        XCTAssertEqual(plan.replacement, "```\r\none\r\ntwo\r\n```")
        XCTAssertEqual(plan.selectedRangeInReplacement, NSRange(location: 5, length: 8))
    }

    func testCodeBlockPlanTogglesExistingFencedSelectionOff() {
        let plan = MarkdownCodeBlockPlan.make(selectedText: "```\nlet value = 1\n```")

        XCTAssertEqual(plan.replacement, "let value = 1")
        XCTAssertEqual(plan.selectedRangeInReplacement, NSRange(location: 0, length: 13))
    }

    func testHeadingPlanSetsHeadingLevelWithoutStackingMarkers() {
        XCTAssertEqual(MarkdownHeadingPlan.make(level: 2, selectedText: "Title").replacement, "## Title")
        XCTAssertEqual(MarkdownHeadingPlan.make(level: 3, selectedText: "# Title").replacement, "### Title")
        XCTAssertEqual(MarkdownHeadingPlan.make(level: 1, selectedText: "### Title").replacement, "# Title")
        XCTAssertEqual(MarkdownHeadingPlan.make(level: 2, selectedText: "###### Title").replacement, "## Title")
    }

    func testHeadingPlanAppliesToSelectedNonEmptyLines() {
        XCTAssertEqual(
            MarkdownHeadingPlan.make(level: 2, selectedText: "One\n\n### Three").replacement,
            "## One\n\n## Three"
        )
    }

    func testLinePrefixPlanRoutesHeadingPrefixesThroughHeadingSemantics() {
        XCTAssertEqual(
            MarkdownLinePrefixPlan.make(prefix: "### ", selectedText: "## Existing heading").replacement,
            "### Existing heading"
        )
    }

    func testTaskPlanPrefixesNormalText() {
        XCTAssertEqual(
            MarkdownTaskListPlan.make(selectedText: "normal line").replacement,
            "- [ ] normal line"
        )
    }

    func testTaskPlanInsertsMarkerOnCollapsedBlankLine() {
        let plan = MarkdownLinePrefixPlan.make(
            prefix: "- [ ] ",
            selectedText: "\n",
            selectedRangeInSelectedText: NSRange(location: 0, length: 0)
        )

        XCTAssertEqual(plan.replacement, "- [ ] \n")
        XCTAssertEqual(plan.selectedRangeInReplacement, NSRange(location: 6, length: 0))
    }

    func testTaskPlanPreservesIndentedCollapsedBlankLine() {
        let plan = MarkdownLinePrefixPlan.make(
            prefix: "- [ ] ",
            selectedText: "   \n",
            selectedRangeInSelectedText: NSRange(location: 0, length: 0)
        )

        XCTAssertEqual(plan.replacement, "   - [ ] \n")
        XCTAssertEqual(plan.selectedRangeInReplacement, NSRange(location: 9, length: 0))
    }

    func testTaskPlanTogglesExistingTasksOffWithoutStacking() {
        XCTAssertEqual(MarkdownTaskListPlan.make(selectedText: "- [ ] text").replacement, "text")
        XCTAssertEqual(MarkdownTaskListPlan.make(selectedText: "- [x] text").replacement, "text")
        XCTAssertEqual(MarkdownTaskListPlan.make(selectedText: "- [/] text").replacement, "text")
        XCTAssertEqual(MarkdownTaskListPlan.make(selectedText: "* [ ] text").replacement, "text")
        XCTAssertEqual(MarkdownTaskListPlan.make(selectedText: "1. [ ] text").replacement, "text")
    }

    func testTaskPlanNormalizesExistingTasksWhenApplyingToMixedSelection() {
        XCTAssertEqual(
            MarkdownTaskListPlan.make(selectedText: "normal\n* [x] checked\n1. [/] partial").replacement,
            "- [ ] normal\n- [x] checked\n- [/] partial"
        )
    }

    func testLinePrefixPlanRoutesTaskPrefixThroughTaskSemantics() {
        XCTAssertEqual(
            MarkdownLinePrefixPlan.make(prefix: "- [ ] ", selectedText: "- [x] done").replacement,
            "done"
        )
    }

    func testSemanticLinePrefixPlanReturnsCursorForHeadings() {
        XCTAssertEqual(
            MarkdownLinePrefixPlan.make(
                prefix: "### ",
                selectedText: "## Title",
                selectedRangeInSelectedText: NSRange(location: 0, length: 0)
            ).selectedRangeInReplacement,
            NSRange(location: 4, length: 0)
        )
        XCTAssertEqual(
            MarkdownLinePrefixPlan.make(
                prefix: "# ",
                selectedText: "### Title",
                selectedRangeInSelectedText: NSRange(location: 0, length: 0)
            ).selectedRangeInReplacement,
            NSRange(location: 2, length: 0)
        )
    }

    func testSemanticLinePrefixPlanReturnsCursorForTaskToggleOff() {
        XCTAssertEqual(
            MarkdownLinePrefixPlan.make(
                prefix: "- [ ] ",
                selectedText: "- [ ] Task",
                selectedRangeInSelectedText: NSRange(location: 0, length: 0)
            ).selectedRangeInReplacement,
            NSRange(location: 0, length: 0)
        )
        XCTAssertEqual(
            MarkdownLinePrefixPlan.make(
                prefix: "- [ ] ",
                selectedText: "1. [ ] Ordered",
                selectedRangeInSelectedText: NSRange(location: 0, length: 0)
            ).selectedRangeInReplacement,
            NSRange(location: 0, length: 0)
        )
    }

    func testTaskPlanPreservesLineEndings() {
        let text = "one\r\ntwo\r\n"
        let applied = MarkdownTaskListPlan.make(selectedText: text).replacement
        let removed = MarkdownTaskListPlan.make(selectedText: applied).replacement

        XCTAssertEqual(applied, "- [ ] one\r\n- [ ] two\r\n")
        XCTAssertEqual(removed, text)
    }

    func testLinkInsertionEscapesSelectedLabelText() {
        XCTAssertEqual(
            MarkdownLinkInsertionPlan.make(forSelectedText: "hello [world]").replacement,
            #"[hello \[world\]](https://)"#
        )
        XCTAssertEqual(
            MarkdownLinkInsertionPlan.make(forSelectedText: "multi\nline").replacement,
            "[multi line](https://)"
        )
    }

    func testImageInsertionEscapesSelectedAltText() {
        XCTAssertEqual(
            MarkdownImageInsertionPlan.make(forSelectedText: "image]name").replacement,
            #"![image\]name](https://)"#
        )
        XCTAssertEqual(
            MarkdownImageInsertionPlan.make(forSelectedText: "multi\nline").replacement,
            "![multi line](https://)"
        )
    }

    func testURLClassifierAllowsOnlyMarkdownSafeDestinations() {
        XCTAssertEqual(MarkdownFormattingURLClassifier.markdownDestination(for: "https://example.com"), "https://example.com")
        XCTAssertEqual(MarkdownFormattingURLClassifier.markdownDestination(for: "http://example.com"), "http://example.com")
        XCTAssertEqual(MarkdownFormattingURLClassifier.markdownDestination(for: "www.example.com"), "www.example.com")
        XCTAssertEqual(MarkdownFormattingURLClassifier.markdownDestination(for: "test@example.com"), "mailto:test@example.com")
        XCTAssertEqual(MarkdownFormattingURLClassifier.markdownDestination(for: "mailto:test@example.com"), "mailto:test@example.com")
        XCTAssertNil(MarkdownFormattingURLClassifier.markdownDestination(for: "foo:bar"))
        XCTAssertNil(MarkdownFormattingURLClassifier.markdownDestination(for: "javascript:alert(1)"))
        XCTAssertNil(MarkdownFormattingURLClassifier.markdownDestination(for: "file:///private/tmp/example"))
    }

    func testExternalLinkURLConvertsMarkdownDestinationsToSystemOpenableURLs() {
        XCTAssertEqual(MarkdownExternalLinkURL.url(forMarkdownDestination: "https://example.com"), URL(string: "https://example.com"))
        XCTAssertEqual(MarkdownExternalLinkURL.url(forMarkdownDestination: "www.example.com"), URL(string: "https://www.example.com"))
        XCTAssertEqual(MarkdownExternalLinkURL.url(forMarkdownDestination: "test@example.com"), URL(string: "mailto:test@example.com"))
        XCTAssertNil(MarkdownExternalLinkURL.url(forMarkdownDestination: "notes.md"))
    }

    private func lineEndings(in text: String) -> [String] {
        var endings: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\r" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "\n" {
                    endings.append("\r\n")
                    index = text.index(after: next)
                } else {
                    endings.append("\r")
                    index = next
                }
            } else if character == "\n" {
                endings.append("\n")
                index = text.index(after: index)
            } else {
                index = text.index(after: index)
            }
        }
        return endings
    }
}
