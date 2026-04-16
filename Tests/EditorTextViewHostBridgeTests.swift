import UIKit
import XCTest
@testable import Downward

final class EditorTextViewHostBridgeTests: XCTestCase {
    @MainActor
    func testBridgeAppliesHorizontalInsetWithoutMovingScrollIndicatorInsets() {
        let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 12, right: 0)
        textView.textContainer.lineFragmentPadding = 6
        textView.scrollIndicatorInsets = UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)

        let (container, bridge) = makeContainerWithBridge()
        container.insertSubview(textView, at: 0)

        bridge.update(
            configuration: .init(
                horizontalInset: 12,
                documentIdentity: PreviewSampleData.cleanDocument.url
            )
        )

        XCTAssertEqual(textView.textContainerInset.left, 12)
        XCTAssertEqual(textView.textContainerInset.right, 12)
        XCTAssertEqual(textView.textContainerInset.top, 8)
        XCTAssertEqual(textView.textContainerInset.bottom, 12)
        XCTAssertEqual(textView.textContainer.lineFragmentPadding, 0)
        XCTAssertEqual(textView.scrollIndicatorInsets, UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4))
    }

    @MainActor
    func testBridgeRebindsToReplacementTextViewWhenDocumentChanges() {
        let firstTextView = UITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        firstTextView.textContainerInset = .zero

        let (container, bridge) = makeContainerWithBridge()
        container.addSubview(firstTextView)
        bridge.update(
            configuration: .init(
                horizontalInset: 12,
                documentIdentity: PreviewSampleData.cleanDocument.url
            )
        )

        XCTAssertEqual(firstTextView.textContainerInset.left, 12)
        XCTAssertEqual(firstTextView.textContainerInset.right, 12)

        firstTextView.removeFromSuperview()

        let secondTextView = UITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        secondTextView.textContainerInset = UIEdgeInsets(top: 4, left: 1, bottom: 9, right: 1)
        secondTextView.textContainer.lineFragmentPadding = 8
        container.insertSubview(secondTextView, at: 0)

        bridge.update(
            configuration: .init(
                horizontalInset: 20,
                documentIdentity: PreviewSampleData.dirtyDocument.url
            )
        )

        XCTAssertEqual(secondTextView.textContainerInset.left, 20)
        XCTAssertEqual(secondTextView.textContainerInset.right, 20)
        XCTAssertEqual(secondTextView.textContainerInset.top, 4)
        XCTAssertEqual(secondTextView.textContainerInset.bottom, 9)
        XCTAssertEqual(secondTextView.textContainer.lineFragmentPadding, 0)
        XCTAssertEqual(firstTextView.textContainerInset.left, 12)
        XCTAssertEqual(firstTextView.textContainerInset.right, 12)
    }

    @MainActor
    private func makeContainerWithBridge() -> (UIView, EditorTextViewHostBridgeView) {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let bridge = EditorTextViewHostBridgeView(frame: .zero)
        container.addSubview(bridge)
        return (container, bridge)
    }
}
