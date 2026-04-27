import XCTest
@testable import Downward

final class TextLineMetricsTests: XCTestCase {
    func testEmptyTextHasOneLine() {
        let metrics = TextLineMetrics(text: "")

        XCTAssertEqual(metrics.lineStartLocations, [0])
        XCTAssertEqual(metrics.lineCount, 1)
        XCTAssertEqual(metrics.lineNumber(at: 0), 1)
    }

    func testTrailingNewlineAddsEmptyFinalLine() {
        let metrics = TextLineMetrics(text: "one\ntwo\n")

        XCTAssertEqual(metrics.lineStartLocations, [0, 4, 8])
        XCTAssertEqual(metrics.lineCount, 3)
        XCTAssertEqual(metrics.lineNumber(at: 8), 3)
    }

    func testCRLFAndCRCountAsSingleLineBreaks() {
        let metrics = TextLineMetrics(text: "one\r\ntwo\rthree")

        XCTAssertEqual(metrics.lineStartLocations, [0, 5, 9])
        XCTAssertEqual(metrics.lineCount, 3)
        XCTAssertEqual(metrics.lineNumber(at: 5), 2)
        XCTAssertEqual(metrics.lineNumber(at: 9), 3)
    }

    func testLargeDocumentLookupUsesCachedStarts() {
        let text = (1...5_000).map { "Line \($0)" }.joined(separator: "\n")
        let metrics = TextLineMetrics(text: text)

        XCTAssertEqual(metrics.lineCount, 5_000)
        XCTAssertEqual(metrics.lineNumber(at: metrics.lineStartLocations[3_999]), 4_000)
        XCTAssertEqual(metrics.lineNumber(at: metrics.lineStartLocations[4_999]), 5_000)
    }

    func testLocationPastEndResolvesToLastLine() {
        let metrics = TextLineMetrics(text: "one\ntwo")

        XCTAssertEqual(metrics.lineNumber(at: 10_000), 2)
        XCTAssertEqual(metrics.lineNumber(at: -10), 1)
    }
}
