import Foundation
import XCTest
@testable import Downward

final class DocumentOpenPolicyTests: XCTestCase {
    func testBelowLimitFileSizeIsAllowed() throws {
        XCTAssertNoThrow(
            try DocumentOpenPolicy.validateReadableFileSize(
                DocumentOpenPolicy.maximumReadableFileSize - 1,
                displayName: "Below.md"
            )
        )
    }

    func testAtLimitFileSizeIsAllowed() throws {
        XCTAssertNoThrow(
            try DocumentOpenPolicy.validateReadableFileSize(
                DocumentOpenPolicy.maximumReadableFileSize,
                displayName: "AtLimit.md"
            )
        )
    }

    func testAboveLimitFileSizeIsRejectedWithClearCopy() throws {
        do {
            try DocumentOpenPolicy.validateReadableFileSize(
                DocumentOpenPolicy.maximumReadableFileSize + 1,
                displayName: "TooLarge.log"
            )
            XCTFail("Expected oversized file to be rejected.")
        } catch let error as AppError {
            guard case let .documentOpenFailed(name, details) = error else {
                return XCTFail("Expected documentOpenFailed error.")
            }

            XCTAssertEqual(name, "TooLarge.log")
            XCTAssertTrue(details.contains("too large to open safely"))
            XCTAssertTrue(details.contains(DocumentOpenPolicy.maximumReadableFileSizeDescription))
        }
    }

    func testMissingFileSizeIsRejectedWithClearCopy() throws {
        do {
            try DocumentOpenPolicy.validateReadableFileSize(nil, displayName: "Unknown.md")
            XCTFail("Expected unverifiable file size to be rejected.")
        } catch let error as AppError {
            guard case let .documentOpenFailed(name, details) = error else {
                return XCTFail("Expected documentOpenFailed error.")
            }

            XCTAssertEqual(name, "Unknown.md")
            XCTAssertTrue(details.contains("could not verify the file size"))
        }
    }
}
