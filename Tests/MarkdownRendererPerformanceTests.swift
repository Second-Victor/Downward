import SwiftUI
import UIKit
import XCTest
@testable import Downward

#if DEBUG
@MainActor
final class MarkdownRendererPerformanceTests: XCTestCase {
    // CI wall-clock thresholds are too noisy for UIKit/TextKit rendering. These tests enforce
    // the work budget instead: full-document events may touch the whole buffer, while ordinary
    // same-line typing in a large document must stay bounded to the edited line.
    private enum Budget {
        static let largeDocumentLineCount = 2_000
        static let maximumCurrentLineRestyleCharacters = 512
    }

    private let baseFont = UIFont.preferredFont(forTextStyle: .body)
    private let renderer = MarkdownStyledTextRenderer()

    func testLargeDocumentInitialRenderUsesFullDocumentBudget() {
        let text = makeLargeMarkdownDocument(lineCount: Budget.largeDocumentLineCount)
        let textBox = MutablePerformanceBox(text)
        let coordinator = makeCoordinator(text: textBox)
        let textView = PerformanceTextView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))

        coordinator.apply(
            configuration: makeConfiguration(text: text, syntaxMode: .hiddenOutsideCurrentLine),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        XCTAssertEqual(textView.textStorage.length, (text as NSString).length)
        XCTAssertEqual(
            coordinator.lastRenderWork,
            .fullDocument(characterCount: (text as NSString).length)
        )
    }

    func testLargeDocumentSameLineTypingUsesCurrentLineBudget() {
        let text = makeLargeMarkdownDocument(lineCount: Budget.largeDocumentLineCount)
        let textBox = MutablePerformanceBox(text)
        let coordinator = makeCoordinator(text: textBox)
        let textView = PerformanceTextView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let nsText = text as NSString
        let lineRange = nsText.range(of: "Plain paragraph 1999")
        let insertionLocation = NSMaxRange(lineRange)

        coordinator.apply(
            configuration: makeConfiguration(text: text, syntaxMode: .hiddenOutsideCurrentLine),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )
        textView.selectedRange = NSRange(location: insertionLocation, length: 0)
        coordinator.textViewDidChangeSelection(textView)

        let insertion = " with **budgeted** styling"
        XCTAssertTrue(
            coordinator.textView(
                textView,
                shouldChangeTextIn: NSRange(location: insertionLocation, length: 0),
                replacementText: insertion
            )
        )
        textView.text = nsText.replacingCharacters(in: NSRange(location: insertionLocation, length: 0), with: insertion)
        textView.selectedRange = NSRange(location: insertionLocation + (insertion as NSString).length, length: 0)

        coordinator.textViewDidChange(textView)

        guard case let .currentLine(characterCount)? = coordinator.lastRenderWork else {
            return XCTFail("Expected same-line typing to use current-line restyle")
        }
        XCTAssertLessThanOrEqual(characterCount, Budget.maximumCurrentLineRestyleCharacters)
        XCTAssertFalse(coordinator.hasPendingFullDocumentRerender)
        XCTAssertFalse(coordinator.hasPendingDeferredRerender)
    }

    func testLargeDocumentLineBreakEditDefersFullDocumentRerender() {
        let text = makeLargeMarkdownDocument(lineCount: Budget.largeDocumentLineCount)
        let textBox = MutablePerformanceBox(text)
        let coordinator = makeCoordinator(text: textBox)
        let textView = PerformanceTextView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let insertionLocation = (text as NSString).length

        coordinator.apply(
            configuration: makeConfiguration(text: text, syntaxMode: .hiddenOutsideCurrentLine),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )
        textView.selectedRange = NSRange(location: insertionLocation, length: 0)
        coordinator.textViewDidChangeSelection(textView)

        let insertion = "\n## Structural heading"
        XCTAssertTrue(
            coordinator.textView(
                textView,
                shouldChangeTextIn: NSRange(location: insertionLocation, length: 0),
                replacementText: insertion
            )
        )
        textView.text = text + insertion
        textView.selectedRange = NSRange(location: (textView.text as NSString).length, length: 0)

        coordinator.textViewDidChange(textView)

        XCTAssertTrue(coordinator.hasPendingFullDocumentRerender)
        XCTAssertTrue(coordinator.hasPendingDeferredRerender)
        XCTAssertEqual(
            coordinator.lastRenderWork,
            .deferredFullDocumentRerenderScheduled(characterCount: (textView.text as NSString).length)
        )
    }

    func testLargeDocumentThemeSwitchUsesFullDocumentRestyleBudget() {
        let text = makeLargeMarkdownDocument(lineCount: Budget.largeDocumentLineCount)
        let textBox = MutablePerformanceBox(text)
        let coordinator = makeCoordinator(text: textBox)
        let textView = PerformanceTextView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))

        coordinator.apply(
            configuration: makeConfiguration(text: text, resolvedTheme: .default),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )
        coordinator.apply(
            configuration: makeConfiguration(text: text, resolvedTheme: customTheme),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: false
        )

        XCTAssertEqual(
            coordinator.lastRenderWork,
            .fullDocument(characterCount: (text as NSString).length)
        )
        XCTAssertFalse(coordinator.hasPendingFullDocumentRerender)
        XCTAssertFalse(coordinator.hasPendingDeferredRerender)
        let headingRange = (textView.text as NSString).range(of: "Heading 0")
        XCTAssertEqual(
            textView.textStorage.attribute(.foregroundColor, at: headingRange.location, effectiveRange: nil) as? UIColor,
            customTheme.headingText
        )
    }

    func testMeasureLargeDocumentSameLineTypingLatency() {
        let text = makeLargeMarkdownDocument(lineCount: Budget.largeDocumentLineCount)
        let textBox = MutablePerformanceBox(text)
        let coordinator = makeCoordinator(text: textBox)
        let textView = PerformanceTextView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let nsText = text as NSString
        let lineRange = nsText.range(of: "Plain paragraph 1999")
        var insertionLocation = NSMaxRange(lineRange)
        var currentText = text
        var iteration = 0

        coordinator.apply(
            configuration: makeConfiguration(text: text, syntaxMode: .hiddenOutsideCurrentLine),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )
        textView.selectedRange = NSRange(location: insertionLocation, length: 0)
        coordinator.textViewDidChangeSelection(textView)

        measure(metrics: [XCTClockMetric()], options: latencyMeasureOptions) {
            let insertion = " typed\(iteration)"
            XCTAssertTrue(
                coordinator.textView(
                    textView,
                    shouldChangeTextIn: NSRange(location: insertionLocation, length: 0),
                    replacementText: insertion
                )
            )
            currentText = (currentText as NSString).replacingCharacters(
                in: NSRange(location: insertionLocation, length: 0),
                with: insertion
            )
            insertionLocation += (insertion as NSString).length
            textView.text = currentText
            textView.selectedRange = NSRange(location: insertionLocation, length: 0)

            coordinator.textViewDidChange(textView)

            guard case .currentLine? = coordinator.lastRenderWork else {
                return XCTFail("Expected same-line typing to stay on the current-line restyle path")
            }
            XCTAssertFalse(coordinator.hasPendingFullDocumentRerender)
            XCTAssertFalse(coordinator.hasPendingDeferredRerender)
            iteration += 1
        }
    }

    func testMeasureLargeDocumentPasteFullRenderLatency() {
        let text = makeLargeMarkdownDocument(lineCount: Budget.largeDocumentLineCount)
        let pastedText = text + "\n" + makeRepresentativeMarkdownPaste()
        let expectedLength = (pastedText as NSString).length

        measure(metrics: [XCTClockMetric()], options: latencyMeasureOptions) {
            let rendered = renderer.render(
                configuration: .init(
                    text: pastedText,
                    baseFont: baseFont,
                    resolvedTheme: .default,
                    syntaxMode: .hiddenOutsideCurrentLine,
                    revealedRange: nil
                )
            )

            XCTAssertEqual(rendered.length, expectedLength)
        }
    }

    func testMeasureLargeDocumentThemeSwitchRestyleLatency() {
        let text = makeLargeMarkdownDocument(lineCount: Budget.largeDocumentLineCount)
        let textBox = MutablePerformanceBox(text)
        let coordinator = makeCoordinator(text: textBox)
        let textView = PerformanceTextView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        var useCustomTheme = true

        coordinator.apply(
            configuration: makeConfiguration(text: text, resolvedTheme: .default),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        measure(metrics: [XCTClockMetric()], options: latencyMeasureOptions) {
            let nextTheme = useCustomTheme ? customTheme : ResolvedEditorTheme.default
            coordinator.apply(
                configuration: makeConfiguration(text: text, resolvedTheme: nextTheme),
                undoCommandToken: 0,
                redoCommandToken: 0,
                dismissKeyboardCommandToken: 0,
                to: textView,
                force: false
            )

            XCTAssertEqual(
                coordinator.lastRenderWork,
                .fullDocument(characterCount: (text as NSString).length)
            )
            XCTAssertFalse(coordinator.hasPendingFullDocumentRerender)
            XCTAssertFalse(coordinator.hasPendingDeferredRerender)
            useCustomTheme.toggle()
        }
    }

    private var latencyMeasureOptions: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        return options
    }

    private func makeCoordinator(
        text: MutablePerformanceBox<String>
    ) -> MarkdownEditorTextView.Coordinator {
        let textBinding = Binding(
            get: { text.value },
            set: { text.value = $0 }
        )
        return MarkdownEditorTextView.Coordinator(
            text: textBinding,
            onEditorFocusChange: { _ in },
            onUndoRedoAvailabilityChange: { _, _ in }
        )
    }

    private func makeConfiguration(
        text: String,
        resolvedTheme: ResolvedEditorTheme = .default,
        syntaxMode: MarkdownSyntaxMode = .visible
    ) -> MarkdownEditorTextView.Configuration {
        MarkdownEditorTextView.Configuration(
            text: text,
            documentIdentity: PreviewSampleData.cleanDocument.url,
            font: baseFont,
            resolvedTheme: resolvedTheme,
            syntaxMode: syntaxMode,
            isEditable: true
        )
    }

    private func makeLargeMarkdownDocument(lineCount: Int) -> String {
        (0..<lineCount).map { index in
            switch index % 10 {
            case 0:
                return "## Heading \(index)"
            case 1:
                return "- Bullet \(index) with **bold** and _italic_ text"
            case 2:
                return "> Quote \(index) with [link](https://example.com/\(index))"
            case 3:
                return "`inline code \(index)` and ~~removed text~~"
            case 4:
                return "![Alt \(index)](/assets/image-\(index).png)"
            case 5:
                return "```"
            case 6:
                return "literal **code \(index)**"
            case 7:
                return "```"
            case 8:
                return "---"
            default:
                return "Plain paragraph \(index) with enough words to resemble normal markdown editing."
            }
        }
        .joined(separator: "\n")
    }

    private func makeRepresentativeMarkdownPaste() -> String {
        (0..<120).map { index in
            switch index % 6 {
            case 0:
                return "### Pasted Heading \(index)"
            case 1:
                return "- pasted bullet \(index) with **strong** and _emphasis_"
            case 2:
                return "> pasted quote \(index)"
            case 3:
                return "`pasted inline code \(index)` and [source](https://example.com/paste/\(index))"
            case 4:
                return "![Pasted alt \(index)](/pasted/\(index).png)"
            default:
                return "Pasted paragraph \(index) with enough words to resemble a real clipboard chunk."
            }
        }
        .joined(separator: "\n")
    }

    private var customTheme: ResolvedEditorTheme {
        ResolvedEditorTheme(
            editorBackground: .black,
            keyboardAccessoryUnderlayBackground: .black,
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
    }
}

private final class PerformanceTextView: EditorChromeAwareTextView {
    private let performanceUndoManager = UndoManager()

    override var undoManager: UndoManager? {
        performanceUndoManager
    }
}

private final class MutablePerformanceBox<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
#endif
