import UIKit
import XCTest
@testable import Downward

final class EditorKeyboardGeometryControllerTests: XCTestCase {
    @MainActor
    func testAttachTracksLatestActiveTextView() {
        let controller = EditorKeyboardGeometryController()
        let firstTextView = EditorChromeAwareTextView(frame: .zero, textContainer: nil)
        let secondTextView = EditorChromeAwareTextView(frame: .zero, textContainer: nil)

        controller.attach(to: firstTextView, onKeyboardFrameApplied: {}, onKeyboardHideApplied: {})
        XCTAssertTrue(controller.activeTextView === firstTextView)

        controller.attach(to: secondTextView, onKeyboardFrameApplied: {}, onKeyboardHideApplied: {})
        XCTAssertTrue(controller.activeTextView === secondTextView)
    }

    @MainActor
    func testApplyKeyboardOverlapUpdatesBottomInsetsFromStoredOverlap() {
        let controller = EditorKeyboardGeometryController()
        let textView = EditorChromeAwareTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))

        controller.applyKeyboardOverlap(240, to: textView)
        let snapshot = controller.viewportInsetsSnapshot(for: textView)

        XCTAssertEqual(textView.keyboardOverlapInset, 240, accuracy: 0.5)
        XCTAssertEqual(snapshot.keyboardOverlapInset, 240, accuracy: 0.5)
        XCTAssertEqual(textView.contentInset.bottom, 240, accuracy: 0.5)
        XCTAssertEqual(textView.verticalScrollIndicatorInsets.bottom, 240, accuracy: 0.5)
    }
}
