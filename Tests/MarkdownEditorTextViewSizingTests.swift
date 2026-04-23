import SwiftUI
import UIKit
import XCTest
@testable import Downward

final class MarkdownEditorTextViewSizingTests: XCTestCase {
    @MainActor
    func testHostedEditorFillsFixedContainerHeight() {
        let text = MutableBox(String(repeating: "Line\n", count: 200))
        let topViewportInset: CGFloat = 64
        let editor = MarkdownEditorTextView(
            text: Binding(
                get: { text.value },
                set: { text.value = $0 }
            ),
            documentIdentity: PreviewSampleData.cleanDocument.url,
            topViewportInset: topViewportInset,
            font: .preferredFont(forTextStyle: .body),
            resolvedTheme: .default,
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
        XCTAssertEqual(
            textView.textContainerInset.top,
            EditorTextViewLayout.effectiveTopInset(topViewportInset: topViewportInset)
        )
        XCTAssertEqual(textView.textContainerInset.left, EditorTextViewLayout.horizontalInset)
        XCTAssertEqual(textView.textContainerInset.right, EditorTextViewLayout.horizontalInset)
        XCTAssertEqual(textView.textContainerInset.bottom, EditorTextViewLayout.bottomInset)
        XCTAssertEqual(textView.contentInset.top, 0)
        XCTAssertEqual(textView.contentOffset.y, 0, accuracy: 0.5)
        XCTAssertEqual(textView.verticalScrollIndicatorInsets.top, 0)
        XCTAssertEqual(textView.contentCompressionResistancePriority(for: .vertical), .defaultLow)
        XCTAssertEqual(textView.contentHuggingPriority(for: .vertical), .defaultLow)
        XCTAssertGreaterThanOrEqual(
            visibleTopOfFirstGlyph(in: textView),
            EditorTextViewLayout.effectiveTopInset(topViewportInset: topViewportInset) - 1
        )
    }

    @MainActor
    func testEffectiveTopInsetAddsViewportClearanceToInternalPadding() {
        XCTAssertEqual(
            EditorTextViewLayout.effectiveTopInset(topViewportInset: 0),
            EditorTextViewLayout.contentTopInset
        )
        XCTAssertEqual(
            EditorTextViewLayout.effectiveTopInset(topViewportInset: 52),
            52 + EditorTextViewLayout.contentTopInset
        )
    }

    @MainActor
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

    @MainActor
    private func visibleTopOfFirstGlyph(in textView: UITextView) -> CGFloat {
        textView.layoutIfNeeded()
        let glyphRange = textView.layoutManager.glyphRange(
            forCharacterRange: NSRange(location: 0, length: min(1, textView.textStorage.length)),
            actualCharacterRange: nil
        )
        let glyphRect = textView.layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)
        return glyphRect.minY + textView.textContainerInset.top - textView.contentOffset.y
    }
}

private final class MutableBox<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
