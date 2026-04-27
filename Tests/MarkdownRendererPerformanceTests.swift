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
    private enum RendererWorkBudget {
        static let oneThousandLineDocument = 1_000
        static let fiveThousandLineDocument = 5_000
        static let twentyThousandLineDocument = 20_000
        static let fiftyThousandLineDiagnosticDocument = 50_000
        static let measuredDocumentLineCount = 2_000
        static let maximumCurrentLineRestyleCharacters = 512
    }

    private let baseFont = UIFont.preferredFont(forTextStyle: .body)
    private let renderer = MarkdownStyledTextRenderer()

    func testLargeDocumentInitialRenderUsesFullDocumentBudget() {
        let text = makeLargeMarkdownDocument(lineCount: RendererWorkBudget.measuredDocumentLineCount)
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

    func testRepresentativeDocumentSizesKeepSameLineTypingOnCurrentLineBudget() {
        let scenarios: [(lineCount: Int, lineNeedle: String)] = [
            (
                RendererWorkBudget.oneThousandLineDocument,
                "Plain paragraph 999"
            ),
            (
                RendererWorkBudget.fiveThousandLineDocument,
                "Plain paragraph 4999"
            ),
            (
                RendererWorkBudget.twentyThousandLineDocument,
                "Plain paragraph 19999"
            )
        ]

        for scenario in scenarios {
            assertSameLineEditUsesCurrentLineBudget(
                lineCount: scenario.lineCount,
                lineNeedle: scenario.lineNeedle,
                insertion: " with **budgeted** styling"
            )
        }
    }

    func testLargeDocumentInlineSameLineEditsStayOnCurrentLineBudget() {
        let lineCount = RendererWorkBudget.fiveThousandLineDocument
        let scenarios: [(lineNeedle: String, insertion: String)] = [
            (
                "- Bullet 4991 with **bold** and _italic_ text",
                " plus __more__"
            ),
            (
                "`inline code 4993` and ~~removed text~~",
                " plus `token`"
            ),
            (
                "Image and link paragraph 4998 with [link](https://example.com/4998) and ![Alt 4998](/assets/image-4998.png)",
                " and [docs](https://example.com/docs)"
            )
        ]

        for scenario in scenarios {
            assertSameLineEditUsesCurrentLineBudget(
                lineCount: lineCount,
                lineNeedle: scenario.lineNeedle,
                insertion: scenario.insertion
            )
        }
    }

    func testHiddenSyntaxSameLineEditRestylesOnlyRevealedCurrentLine() {
        assertSameLineEditUsesCurrentLineBudget(
            lineCount: RendererWorkBudget.fiveThousandLineDocument,
            lineNeedle: "Plain paragraph 4999",
            insertion: " with hidden markers **still local**",
            syntaxMode: .hiddenOutsideCurrentLine
        )
    }

    func testFiftyThousandLineBudgetIsDiagnosticOnlyForLineScanning() {
        let text = makeLargeMarkdownDocument(lineCount: RendererWorkBudget.fiftyThousandLineDiagnosticDocument)
        let scanner = MarkdownSyntaxScanner()

        let lineRanges = scanner.lineRanges(in: text)

        XCTAssertEqual(lineRanges.count, RendererWorkBudget.fiftyThousandLineDiagnosticDocument)
    }

    func testLargeDocumentLineBreakEditDefersFullDocumentRerender() {
        let text = makeStructuralMarkdownDocument()
        let insertionLocation = NSMaxRange((text as NSString).range(of: "Plain structural paragraph"))

        assertStructuralEditDefersFullDocumentRerender(
            text: text,
            changedRange: NSRange(location: insertionLocation, length: 0),
            replacement: "\n## Structural heading"
        )
    }

    func testFencedCodeDelimiterEditDefersFullDocumentRerender() {
        let text = makeStructuralMarkdownDocument()
        let insertionLocation = NSMaxRange((text as NSString).range(of: "```"))

        assertStructuralEditDefersFullDocumentRerender(
            text: text,
            changedRange: NSRange(location: insertionLocation, length: 0),
            replacement: " swift"
        )
    }

    func testFencedCodeContentEditDefersFullDocumentRerender() {
        let text = makeStructuralMarkdownDocument()
        let insertionLocation = NSMaxRange((text as NSString).range(of: "literal **code**"))

        assertStructuralEditDefersFullDocumentRerender(
            text: text,
            changedRange: NSRange(location: insertionLocation, length: 0),
            replacement: " still code"
        )
    }

    func testBlockquoteMarkerLineEditDefersFullDocumentRerender() {
        let text = makeStructuralMarkdownDocument()
        let insertionLocation = NSMaxRange((text as NSString).range(of: "> Quoted line"))

        assertStructuralEditDefersFullDocumentRerender(
            text: text,
            changedRange: NSRange(location: insertionLocation, length: 0),
            replacement: " with continuation"
        )
    }

    func testRemovingExistingBlockquoteMarkerDefersFullDocumentRerender() {
        let text = makeStructuralMarkdownDocument()
        let markerRange = (text as NSString).range(of: "> Quoted line")

        assertStructuralEditDefersFullDocumentRerender(
            text: text,
            changedRange: NSRange(location: markerRange.location, length: 1),
            replacement: ""
        )
    }

    func testSetextUnderlineEditDefersFullDocumentRerender() {
        let text = makeStructuralMarkdownDocument()
        let underlineRange = (text as NSString).range(of: "---------------")

        assertStructuralEditDefersFullDocumentRerender(
            text: text,
            changedRange: NSRange(location: underlineRange.location, length: 1),
            replacement: "x"
        )
    }

    func testLineBeforeSetextUnderlineEditDefersFullDocumentRerender() {
        let text = makeStructuralMarkdownDocument()
        let insertionLocation = NSMaxRange((text as NSString).range(of: "Setext Title"))

        assertStructuralEditDefersFullDocumentRerender(
            text: text,
            changedRange: NSRange(location: insertionLocation, length: 0),
            replacement: " Updated"
        )
    }

    func testHorizontalRuleLikeLineEditDefersFullDocumentRerender() {
        let text = makeStructuralMarkdownDocument()
        let insertionLocation = NSMaxRange((text as NSString).range(of: "***"))

        assertStructuralEditDefersFullDocumentRerender(
            text: text,
            changedRange: NSRange(location: insertionLocation, length: 0),
            replacement: "*"
        )
    }

    func testLargeDocumentThemeSwitchUsesFullDocumentRestyleBudget() {
        let text = makeLargeMarkdownDocument(lineCount: RendererWorkBudget.measuredDocumentLineCount)
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
        let text = makeLargeMarkdownDocument(lineCount: RendererWorkBudget.measuredDocumentLineCount)
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
        let text = makeLargeMarkdownDocument(lineCount: RendererWorkBudget.measuredDocumentLineCount)
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
        let text = makeLargeMarkdownDocument(lineCount: RendererWorkBudget.measuredDocumentLineCount)
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

    private func assertSameLineEditUsesCurrentLineBudget(
        lineCount: Int,
        lineNeedle: String,
        insertion: String,
        syntaxMode: MarkdownSyntaxMode = .hiddenOutsideCurrentLine,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let text = makeLargeMarkdownDocument(lineCount: lineCount)
        let textBox = MutablePerformanceBox(text)
        let coordinator = makeCoordinator(text: textBox)
        let textView = PerformanceTextView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let nsText = text as NSString
        let lineRange = nsText.range(of: lineNeedle)
        XCTAssertNotEqual(lineRange.location, NSNotFound, file: file, line: line)
        let insertionLocation = NSMaxRange(lineRange)

        coordinator.apply(
            configuration: makeConfiguration(text: text, syntaxMode: syntaxMode),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )
        textView.selectedRange = NSRange(location: insertionLocation, length: 0)
        coordinator.textViewDidChangeSelection(textView)

        let editRange = NSRange(location: insertionLocation, length: 0)
        XCTAssertTrue(
            coordinator.textView(textView, shouldChangeTextIn: editRange, replacementText: insertion),
            file: file,
            line: line
        )
        let updatedText = nsText.replacingCharacters(in: editRange, with: insertion)
        textView.text = updatedText
        textView.selectedRange = NSRange(location: insertionLocation + (insertion as NSString).length, length: 0)

        coordinator.textViewDidChange(textView)

        guard case let .currentLine(characterCount)? = coordinator.lastRenderWork else {
            return XCTFail("Expected same-line typing to use current-line restyle", file: file, line: line)
        }
        XCTAssertLessThanOrEqual(
            characterCount,
            RendererWorkBudget.maximumCurrentLineRestyleCharacters,
            file: file,
            line: line
        )
        XCTAssertFalse(coordinator.hasPendingFullDocumentRerender, file: file, line: line)
        XCTAssertFalse(coordinator.hasPendingDeferredRerender, file: file, line: line)
        XCTAssertEqual(textBox.value, updatedText, file: file, line: line)
        XCTAssertEqual(textView.text, updatedText, file: file, line: line)
        XCTAssertEqual(
            textView.selectedRange,
            NSRange(location: insertionLocation + (insertion as NSString).length, length: 0),
            file: file,
            line: line
        )
    }

    private func assertStructuralEditDefersFullDocumentRerender(
        text: String,
        changedRange: NSRange,
        replacement: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let textBox = MutablePerformanceBox(text)
        let coordinator = makeCoordinator(text: textBox)
        let textView = PerformanceTextView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let nsText = text as NSString
        let safeChangedRange = NSRange(
            location: min(changedRange.location, nsText.length),
            length: min(changedRange.length, nsText.length - min(changedRange.location, nsText.length))
        )

        coordinator.apply(
            configuration: makeConfiguration(text: text, syntaxMode: .hiddenOutsideCurrentLine),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )
        textView.selectedRange = NSRange(location: safeChangedRange.location, length: 0)
        coordinator.textViewDidChangeSelection(textView)

        XCTAssertTrue(
            coordinator.textView(textView, shouldChangeTextIn: safeChangedRange, replacementText: replacement),
            file: file,
            line: line
        )
        let updatedText = nsText.replacingCharacters(in: safeChangedRange, with: replacement)
        let updatedSelectionLocation = safeChangedRange.location + (replacement as NSString).length
        textView.textStorage.replaceCharacters(in: safeChangedRange, with: replacement)
        textView.selectedRange = NSRange(location: updatedSelectionLocation, length: 0)

        coordinator.textViewDidChange(textView)

        if case .currentLine? = coordinator.lastRenderWork {
            XCTFail("Structural markdown edit should not use current-line restyle", file: file, line: line)
        }
        if case .fullDocument? = coordinator.lastRenderWork {
            XCTFail("Structural markdown edit should not synchronously rerender the full document", file: file, line: line)
        }
        XCTAssertTrue(coordinator.hasPendingFullDocumentRerender, file: file, line: line)
        XCTAssertTrue(coordinator.hasPendingDeferredRerender, file: file, line: line)
        XCTAssertEqual(
            coordinator.lastRenderWork,
            .deferredFullDocumentRerenderScheduled(characterCount: (updatedText as NSString).length),
            file: file,
            line: line
        )
        XCTAssertEqual(textBox.value, updatedText, file: file, line: line)
        XCTAssertEqual(textView.text, updatedText, file: file, line: line)
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
                return "Plain paragraph \(index) before fenced code."
            case 5:
                return "```"
            case 6:
                return "literal **code \(index)**"
            case 7:
                return "```"
            case 8:
                return "Image and link paragraph \(index) with [link](https://example.com/\(index)) and ![Alt \(index)](/assets/image-\(index).png)"
            default:
                return "Plain paragraph \(index) with enough words to resemble normal markdown editing."
            }
        }
        .joined(separator: "\n")
    }

    private func makeStructuralMarkdownDocument() -> String {
        """
        Plain structural paragraph
        ```
        literal **code**
        ```
        > Quoted line
        Setext Title
        ---------------
        ***
        Closing paragraph
        """
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
            horizontalRuleText: .systemGray,
            checkboxUnchecked: .systemRed,
            checkboxChecked: .systemGreen
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
