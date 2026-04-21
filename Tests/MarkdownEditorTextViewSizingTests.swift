import SwiftUI
import UIKit
import XCTest
@testable import Downward

final class MarkdownEditorTextViewSizingTests: XCTestCase {
    @MainActor
    func testHostedEditorFillsFixedContainerHeight() {
        let text = MutableBox(String(repeating: "Line\n", count: 200))
        let topOverlayClearance = MutableBox<CGFloat>(0)
        let editor = MarkdownEditorTextView(
            text: Binding(
                get: { text.value },
                set: { text.value = $0 }
            ),
            topOverlayClearance: Binding(
                get: { topOverlayClearance.value },
                set: { topOverlayClearance.value = $0 }
            ),
            documentIdentity: PreviewSampleData.cleanDocument.url,
            font: .preferredFont(forTextStyle: .body),
            syntaxMode: .visible,
            isEditable: true,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            onEditorFocusChange: { _ in },
            onUndoRedoAvailabilityChange: { _, _ in }
        )
        .frame(width: 320, height: 480)

        let hostingController = UIHostingController(rootView: editor)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = hostingController
        window.makeKeyAndVisible()

        hostingController.view.frame = window.bounds
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        window.layoutIfNeeded()

        guard let textView = findEditorTextView(in: hostingController.view) else {
            XCTFail("Expected hosted EditorChromeAwareTextView")
            return
        }

        XCTAssertEqual(textView.frame.height, 480, accuracy: 1)
        XCTAssertEqual(textView.frame.width, 320, accuracy: 1)
        XCTAssertTrue(textView.textContainer.widthTracksTextView)
        XCTAssertEqual(textView.contentCompressionResistancePriority(for: .vertical), .defaultLow)
        XCTAssertEqual(textView.contentHuggingPriority(for: .vertical), .defaultLow)
    }

    private func findEditorTextView(in view: UIView) -> EditorChromeAwareTextView? {
        if let textView = view as? EditorChromeAwareTextView {
            return textView
        }

        for subview in view.subviews {
            if let textView = findEditorTextView(in: subview) {
                return textView
            }
        }

        return nil
    }
}

private final class MutableBox<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
