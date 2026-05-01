import SwiftUI
import UIKit
import XCTest
@testable import Downward

final class EditorUndoRedoTests: XCTestCase {
    @MainActor
    func testUndoRedoRequestsFollowAvailabilityAndDismissTracksFocus() {
        let system = makeEditorSystem()

        XCTAssertFalse(system.viewModel.isEditorFocused)
        XCTAssertFalse(system.viewModel.canUndo)
        XCTAssertFalse(system.viewModel.canRedo)
        XCTAssertEqual(system.viewModel.undoCommandToken, 0)
        XCTAssertEqual(system.viewModel.redoCommandToken, 0)
        XCTAssertEqual(system.viewModel.dismissKeyboardCommandToken, 0)

        system.viewModel.handleEditorFocusChange(true)
        system.viewModel.updateUndoRedoAvailability(canUndo: true, canRedo: false)

        XCTAssertTrue(system.viewModel.isEditorFocused)
        XCTAssertTrue(system.viewModel.canUndo)
        XCTAssertFalse(system.viewModel.canRedo)

        system.viewModel.requestUndo()
        system.viewModel.requestRedo()

        XCTAssertEqual(system.viewModel.undoCommandToken, 1)
        XCTAssertEqual(system.viewModel.redoCommandToken, 0)

        system.viewModel.updateUndoRedoAvailability(canUndo: false, canRedo: true)
        system.viewModel.requestRedo()
        system.viewModel.requestKeyboardDismiss()

        XCTAssertEqual(system.viewModel.redoCommandToken, 1)
        XCTAssertEqual(system.viewModel.dismissKeyboardCommandToken, 1)

        system.viewModel.handleEditorFocusChange(false)

        XCTAssertFalse(system.viewModel.isEditorFocused)
        XCTAssertFalse(system.viewModel.canUndo)
        XCTAssertFalse(system.viewModel.canRedo)
    }

    @MainActor
    func testViewModelOpensResolvedLocalMarkdownLinkThroughTrustedPresentation() {
        let system = makeEditorSystem()

        system.viewModel.openLocalMarkdownLink(destination: "References/README.md")

        XCTAssertEqual(system.session.pendingEditorPresentation?.relativePath, "References/README.md")
        XCTAssertEqual(system.session.pendingEditorPresentation?.routeURL, PreviewSampleData.readmeDocumentURL)
        XCTAssertNil(system.session.editorAlertError)
    }

    @MainActor
    func testViewModelShowsErrorForMissingLocalMarkdownLink() {
        let system = makeEditorSystem()

        system.viewModel.openLocalMarkdownLink(destination: "References/Missing.md")

        XCTAssertEqual(system.session.editorAlertError?.title, "Linked File Unavailable")
        XCTAssertNil(system.session.pendingEditorPresentation)
    }

    @MainActor
    func testCoordinatorConfiguresKeyboardAccessoryToolbar() {
        let textBox = MutableBox("Draft")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let configuration = makeConfiguration(text: textBox.value)

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        guard let accessoryView = textView.inputAccessoryView as? KeyboardAccessoryToolbarView else {
            XCTFail("Expected keyboard accessory toolbar view")
            return
        }

        XCTAssertNotNil(textView.keyboardAccessoryToolbarView)
        XCTAssertClear(accessoryView.backgroundColor)
        XCTAssertFalse(accessoryView.isOpaque)
        XCTAssertAccessoryToolbarItemsMatchCurrentIdiom(
            accessoryView.toolbar.items,
            formatItem: textView.formatAccessoryItem,
            undoItem: textView.undoAccessoryItem,
            redoItem: textView.redoAccessoryItem,
            dismissItem: textView.dismissAccessoryItem
        )
        XCTAssertFalse(textView.undoAccessoryItem?.isEnabled ?? true)
        XCTAssertFalse(textView.redoAccessoryItem?.isEnabled ?? true)
        XCTAssertFalse(textView.dismissAccessoryItem?.isEnabled ?? true)

        textView.trackingUndoManager.simulatedCanUndo = true
        textView.trackingUndoManager.simulatedCanRedo = false
        textView.simulatedIsFirstResponder = true

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: false
        )

        XCTAssertTrue(textView.undoAccessoryItem?.isEnabled ?? false)
        XCTAssertFalse(textView.redoAccessoryItem?.isEnabled ?? true)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertFalse(textView.dismissAccessoryItem?.isEnabled ?? true)
        } else {
            XCTAssertTrue(textView.dismissAccessoryItem?.isEnabled ?? false)
        }
    }

    @MainActor
    func testCoordinatorAppliesLineNumbersWithoutFullRerender() {
        let textBox = MutableBox("First\nSecond")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        textView.textContainerInset = UIEdgeInsets(
            top: EditorTextViewLayout.contentTopInset,
            left: EditorTextViewLayout.horizontalInset,
            bottom: EditorTextViewLayout.bottomInset,
            right: EditorTextViewLayout.horizontalInset
        )
        let initialConfiguration = makeConfiguration(text: textBox.value, showLineNumbers: false)

        coordinator.apply(
            configuration: initialConfiguration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )
        textView.selectedRange = NSRange(location: 3, length: 0)
        let initialRenderWork = coordinator.lastRenderWork

        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value, showLineNumbers: true),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: false
        )

        XCTAssertEqual(textView.text, textBox.value)
        XCTAssertEqual(textView.selectedRange, NSRange(location: 3, length: 0))
        XCTAssertEqual(coordinator.lastRenderWork, initialRenderWork)
        XCTAssertFalse(coordinator.hasPendingDeferredRerender)
        XCTAssertFalse(textView.lineNumberGutter?.isHidden ?? true)
        XCTAssertGreaterThan(textView.textContainerInset.left, EditorTextViewLayout.horizontalInset)
    }

    @MainActor
    func testCoordinatorRerendersWhenLargerHeadingTextChanges() {
        let textBox = MutableBox("# Title")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let initialConfiguration = makeConfiguration(text: textBox.value, largerHeadingText: false)

        coordinator.apply(
            configuration: initialConfiguration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value, largerHeadingText: true),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: false
        )

        let nsString = textView.textStorage.string as NSString
        let titleRange = nsString.range(of: "Title")
        let titleFont = textView.textStorage.attribute(.font, at: titleRange.location, effectiveRange: nil) as? UIFont

        XCTAssertGreaterThan(titleFont?.pointSize ?? 0, UIFont.preferredFont(forTextStyle: .body).pointSize)
    }

    @MainActor
    func testCoordinatorTogglesTaskCheckboxesAndUpdatesThemedPresentation() {
        let textBox = MutableBox("- [ ] Task\n1. [x] Done\n* [ ] Star")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let configuration = makeConfiguration(text: textBox.value)

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        let nsText = textBox.value as NSString
        let uncheckedRange = nsText.range(of: "[ ]")
        coordinator.toggleTaskCheckboxForTesting(in: uncheckedRange, textView: textView)

        XCTAssertEqual(textBox.value, "- [x] Task\n1. [x] Done\n* [ ] Star")
        XCTAssertEqual(
            textView.textStorage.attribute(.foregroundColor, at: uncheckedRange.location, effectiveRange: nil) as? UIColor,
            ResolvedEditorTheme.default.checkboxChecked
        )

        let checkedRange = (textBox.value as NSString).range(of: "[x]")
        coordinator.toggleTaskCheckboxForTesting(in: checkedRange, textView: textView)

        XCTAssertEqual(textBox.value, "- [ ] Task\n1. [x] Done\n* [ ] Star")
        XCTAssertEqual(
            textView.textStorage.attribute(.foregroundColor, at: checkedRange.location, effectiveRange: nil) as? UIColor,
            ResolvedEditorTheme.default.checkboxUnchecked
        )
    }

    @MainActor
    func testCoordinatorTogglesSlashTaskCheckboxToChecked() {
        let textBox = MutableBox("- [/] Partial")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        let slashRange = (textBox.value as NSString).range(of: "[/]")
        coordinator.toggleTaskCheckboxForTesting(in: slashRange, textView: textView)

        XCTAssertEqual(textBox.value, "- [x] Partial")
        XCTAssertEqual(
            textView.textStorage.attribute(.foregroundColor, at: slashRange.location, effectiveRange: nil) as? UIColor,
            ResolvedEditorTheme.default.checkboxChecked
        )
    }

    @MainActor
    func testCoordinatorOnlyResolvesTaskCheckboxTapWhenSettingIsEnabled() throws {
        let textBox = MutableBox("* [ ] Star")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        textView.textContainerInset = UIEdgeInsets(
            top: EditorTextViewLayout.contentTopInset,
            left: EditorTextViewLayout.horizontalInset,
            bottom: EditorTextViewLayout.bottomInset,
            right: EditorTextViewLayout.horizontalInset
        )
        let enabledConfiguration = makeConfiguration(text: textBox.value, tapToToggleTasks: true)

        coordinator.apply(
            configuration: enabledConfiguration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        let checkboxRange = (textBox.value as NSString).range(of: "[ ]")
        let tapPoint = try XCTUnwrap(pointForCharacterRange(checkboxRange, in: textView))
        XCTAssertEqual(
            coordinator.resolvedTaskCheckboxRangeForTesting(at: tapPoint, in: textView),
            checkboxRange
        )

        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value, tapToToggleTasks: false),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: false
        )

        XCTAssertNil(coordinator.resolvedTaskCheckboxRangeForTesting(at: tapPoint, in: textView))
    }

    @MainActor
    func testCoordinatorResolvesMarkdownLinkTapOnVisibleTitle() throws {
        let textBox = MutableBox("[Site](https://example.com)")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        textView.textContainerInset = UIEdgeInsets(
            top: EditorTextViewLayout.contentTopInset,
            left: EditorTextViewLayout.horizontalInset,
            bottom: EditorTextViewLayout.bottomInset,
            right: EditorTextViewLayout.horizontalInset
        )

        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        let titleRange = (textBox.value as NSString).range(of: "Site")
        let tapPoint = try XCTUnwrap(pointForCharacterRange(titleRange, in: textView))

        XCTAssertEqual(
            coordinator.resolvedMarkdownLinkDestinationForTesting(at: tapPoint, in: textView),
            .external(try XCTUnwrap(URL(string: "https://example.com")))
        )
    }

    @MainActor
    func testCoordinatorOpensMarkdownLinkUsingInjectedSystemOpener() throws {
        let textBox = MutableBox("[Site](www.example.com)")
        var openedURL: URL?
        let coordinator = makeCoordinator(text: textBox) { url in
            openedURL = url
        }
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        textView.textContainerInset = UIEdgeInsets(
            top: EditorTextViewLayout.contentTopInset,
            left: EditorTextViewLayout.horizontalInset,
            bottom: EditorTextViewLayout.bottomInset,
            right: EditorTextViewLayout.horizontalInset
        )

        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        let titleRange = (textBox.value as NSString).range(of: "Site")
        let tapPoint = try XCTUnwrap(pointForCharacterRange(titleRange, in: textView))
        coordinator.openMarkdownLinkForTesting(at: tapPoint, in: textView)

        XCTAssertEqual(openedURL, URL(string: "https://www.example.com"))
    }

    @MainActor
    func testCoordinatorRoutesRelativeMarkdownLinkToLocalOpener() throws {
        let textBox = MutableBox("[Local](notes.md)")
        var openedURL: URL?
        var openedLocalDestination: String?
        let coordinator = makeCoordinator(
            text: textBox,
            openExternalURL: { url in
                openedURL = url
            },
            openLocalMarkdownLink: { destination in
                openedLocalDestination = destination
            }
        )
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        textView.textContainerInset = UIEdgeInsets(
            top: EditorTextViewLayout.contentTopInset,
            left: EditorTextViewLayout.horizontalInset,
            bottom: EditorTextViewLayout.bottomInset,
            right: EditorTextViewLayout.horizontalInset
        )

        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        let titleRange = (textBox.value as NSString).range(of: "Local")
        let tapPoint = try XCTUnwrap(pointForCharacterRange(titleRange, in: textView))
        coordinator.openMarkdownLinkForTesting(at: tapPoint, in: textView)

        XCTAssertEqual(
            coordinator.resolvedMarkdownLinkDestinationForTesting(at: tapPoint, in: textView),
            .local("notes.md")
        )
        XCTAssertNil(openedURL)
        XCTAssertEqual(openedLocalDestination, "notes.md")
    }

    @MainActor
    func testCoordinatorContinuesTaskListWhenReturnIsPressedAtEnd() {
        let textBox = MutableBox("- [ ] Task")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        let handled = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: (textView.text as NSString).length, length: 0),
            replacementText: "\n"
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(textBox.value, "- [ ] Task\n- [ ] ")
        XCTAssertEqual(textView.selectedRange.location, (textBox.value as NSString).length)
    }

    @MainActor
    func testCoordinatorTaskContinuationParticipatesInUndoRedo() {
        let (textBox, coordinator, textView) = makeFormatterUndoSystem(text: "- [ ] Task")
        let originalSelection = NSRange(location: (textBox.value as NSString).length, length: 0)
        textView.selectedRange = originalSelection

        let handled = coordinator.textView(
            textView,
            shouldChangeTextIn: originalSelection,
            replacementText: "\n"
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(textBox.value, "- [ ] Task\n- [ ] ")
        XCTAssertEqual(textView.selectedRange, NSRange(location: (textBox.value as NSString).length, length: 0))
        assertFormatterUndoRedo(
            textBox: textBox,
            textView: textView,
            undoText: "- [ ] Task",
            undoSelection: originalSelection,
            redoText: "- [ ] Task\n- [ ] ",
            redoSelection: NSRange(location: ("- [ ] Task\n- [ ] " as NSString).length, length: 0)
        )
    }

    @MainActor
    func testCoordinatorContinuesNumberedTaskListWithNextNumber() {
        let textBox = MutableBox("1. [x] Done")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        let handled = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: (textView.text as NSString).length, length: 0),
            replacementText: "\n"
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(textBox.value, "1. [x] Done\n2. [ ] ")
    }

    @MainActor
    func testCoordinatorNumberedTaskContinuationParticipatesInUndoRedo() {
        let (textBox, coordinator, textView) = makeFormatterUndoSystem(text: "1. [x] Done")
        let originalSelection = NSRange(location: (textBox.value as NSString).length, length: 0)
        textView.selectedRange = originalSelection

        let handled = coordinator.textView(
            textView,
            shouldChangeTextIn: originalSelection,
            replacementText: "\n"
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(textBox.value, "1. [x] Done\n2. [ ] ")
        XCTAssertEqual(textView.selectedRange, NSRange(location: (textBox.value as NSString).length, length: 0))
        assertFormatterUndoRedo(
            textBox: textBox,
            textView: textView,
            undoText: "1. [x] Done",
            undoSelection: originalSelection,
            redoText: "1. [x] Done\n2. [ ] ",
            redoSelection: NSRange(location: ("1. [x] Done\n2. [ ] " as NSString).length, length: 0)
        )
    }

    @MainActor
    func testCoordinatorRemovesGeneratedTaskWhenReturnIsPressedAgain() {
        let textBox = MutableBox("- [ ] Task\n- [ ] ")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        let handled = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: (textView.text as NSString).length, length: 0),
            replacementText: "\n"
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(textBox.value, "- [ ] Task\n")
        XCTAssertEqual(textView.selectedRange.location, (textBox.value as NSString).length)
    }

    @MainActor
    func testCoordinatorGeneratedTaskRemovalParticipatesInUndoRedo() {
        let (textBox, coordinator, textView) = makeFormatterUndoSystem(text: "- [ ] Task\n- [ ] ")
        let originalSelection = NSRange(location: (textBox.value as NSString).length, length: 0)
        textView.selectedRange = originalSelection

        let handled = coordinator.textView(
            textView,
            shouldChangeTextIn: originalSelection,
            replacementText: "\n"
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(textBox.value, "- [ ] Task\n")
        XCTAssertEqual(textView.selectedRange, NSRange(location: (textBox.value as NSString).length, length: 0))
        assertFormatterUndoRedo(
            textBox: textBox,
            textView: textView,
            undoText: "- [ ] Task\n- [ ] ",
            undoSelection: originalSelection,
            redoText: "- [ ] Task\n",
            redoSelection: NSRange(location: ("- [ ] Task\n" as NSString).length, length: 0)
        )
    }

    @MainActor
    func testKeyboardOverlapUpdatesBottomInsetsLikePrototype() {
        let textBox = MutableBox("Draft")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let configuration = makeConfiguration(text: textBox.value)

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        guard let accessoryView = textView.inputAccessoryView as? KeyboardAccessoryToolbarView else {
            XCTFail("Expected keyboard accessory toolbar view")
            return
        }

        let accessoryHeight = accessoryView.sizeThatFits(CGSize(width: 320, height: UIView.noIntrinsicMetric)).height
        coordinator.applyKeyboardOverlap(accessoryHeight + 180, to: textView)
        let snapshot = coordinator.viewportInsetsSnapshot(for: textView)

        XCTAssertEqual(snapshot.keyboardOverlapInset, accessoryHeight + 180, accuracy: 0.5)
        XCTAssertEqual(textView.contentInset.bottom, accessoryHeight + 180, accuracy: 0.5)
        XCTAssertEqual(textView.verticalScrollIndicatorInsets.bottom, accessoryHeight + 180, accuracy: 0.5)
    }

    @MainActor
    func testKeyboardOverlapDoesNotCompensateContentOffsetForAccessoryHeight() {
        let textBox = MutableBox("Draft")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let configuration = makeConfiguration(text: textBox.value)

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        guard let accessoryView = textView.inputAccessoryView as? KeyboardAccessoryToolbarView else {
            XCTFail("Expected keyboard accessory toolbar view")
            return
        }

        let accessoryHeight = accessoryView.sizeThatFits(CGSize(width: 320, height: UIView.noIntrinsicMetric)).height
        textView.simulatedIsFirstResponder = true
        textView.contentSize = CGSize(width: 320, height: 1600)
        textView.contentOffset = CGPoint(x: 0, y: 120)

        coordinator.applyKeyboardOverlap(accessoryHeight + 180, to: textView)

        XCTAssertEqual(textView.contentInset.bottom, accessoryHeight + 180, accuracy: 0.5)
        XCTAssertEqual(textView.contentOffset.y, 120, accuracy: 0.5)
    }

    @MainActor
    func testRepeatedAccessoryStateUpdatesDoNotRewriteBottomKeyboardInsets() {
        let textBox = MutableBox("Draft")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let configuration = makeConfiguration(text: textBox.value)

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        coordinator.applyKeyboardOverlap(220, to: textView)
        let originalBottomInset = textView.contentInset.bottom
        let originalIndicatorBottomInset = textView.verticalScrollIndicatorInsets.bottom

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: false
        )

        XCTAssertEqual(textView.contentInset.bottom, originalBottomInset, accuracy: 0.5)
        XCTAssertEqual(textView.verticalScrollIndicatorInsets.bottom, originalIndicatorBottomInset, accuracy: 0.5)
    }

    @MainActor
    func testCoordinatorResetsViewportToDocumentStartWhenSwitchingDocuments() {
        let textBox = MutableBox(String(repeating: "Line\n", count: 120))
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let initialConfiguration = makeConfiguration(
            text: textBox.value,
            documentIdentity: PreviewSampleData.cleanDocument.url
        )

        coordinator.apply(
            configuration: initialConfiguration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        textView.contentSize = CGSize(width: 320, height: 2400)
        textView.contentOffset = CGPoint(x: 0, y: 120)
        textView.selectedRange = NSRange(location: 18, length: 0)

        coordinator.apply(
            configuration: makeConfiguration(
                text: "Replacement document",
                documentIdentity: PreviewSampleData.dirtyDocument.url
            ),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: false
        )

        XCTAssertTrue(coordinator.isNearDocumentStart(in: textView))
        XCTAssertLessThan(textView.contentOffset.y, 40)
        XCTAssertEqual(textView.selectedRange, NSRange(location: 0, length: 0))
    }

    @MainActor
    func testCoordinatorPreservesViewportForSameDocumentRerender() {
        let textBox = MutableBox(String(repeating: "Line\n", count: 120))
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let configuration = makeConfiguration(
            text: textBox.value,
            documentIdentity: PreviewSampleData.cleanDocument.url
        )

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        textView.contentSize = CGSize(width: 320, height: 2400)
        textView.contentOffset = CGPoint(x: 0, y: 120)

        coordinator.apply(
            configuration: makeConfiguration(
                text: textBox.value + "\nAppended line",
                documentIdentity: PreviewSampleData.cleanDocument.url
            ),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: false
        )

        XCTAssertEqual(textView.contentOffset.y, 120, accuracy: 0.5)
    }

    @MainActor
    func testCoordinatorPreservesCaretScreenPositionForSameDocumentRerenderWhenLayoutChanges() {
        let text = makeWrappingMarkdownLines(count: 140)
        let textBox = MutableBox(text)
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        textView.simulatedIsFirstResponder = true
        let configuration = makeConfiguration(
            text: textBox.value,
            largerHeadingText: false
        )

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        let caretLocation = (text as NSString).range(of: "Plain line 80").location
        let beforeScreenY = placeCaret(
            at: caretLocation,
            screenY: 280,
            in: textView
        )

        coordinator.apply(
            configuration: makeConfiguration(
                text: textBox.value,
                largerHeadingText: true
            ),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: false
        )

        XCTAssertEqual(textView.selectedRange, NSRange(location: caretLocation, length: 0))
        XCTAssertEqual(caretScreenY(in: textView), beforeScreenY, accuracy: 1.5)
    }

    @MainActor
    func testCoordinatorPreservesCaretScreenPositionWhenHiddenSyntaxRevealChangesLayout() {
        let firstLine = String(repeating: "**opening marker text wraps** ", count: 18)
        let middleLines = (0..<70).map { "Plain spacer line \($0)" }.joined(separator: "\n")
        let bottomLine = String(repeating: "~~bottom marker text wraps~~ ", count: 18)
        let text = "\(firstLine)\n\(middleLines)\n\(bottomLine)"
        let textBox = MutableBox(text)
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        textView.simulatedIsFirstResponder = true
        textView.selectedRange = NSRange(location: 4, length: 0)

        coordinator.apply(
            configuration: makeConfiguration(
                text: textBox.value,
                syntaxMode: .hiddenOutsideCurrentLine
            ),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        let caretLocation = (text as NSString).range(of: "bottom marker").location
        let beforeScreenY = placeCaret(
            at: caretLocation,
            screenY: 280,
            in: textView
        )

        coordinator.textViewDidChangeSelection(textView)

        XCTAssertEqual(textView.selectedRange, NSRange(location: caretLocation, length: 0))
        XCTAssertEqual(caretScreenY(in: textView), beforeScreenY, accuracy: 1.5)
    }

    @MainActor
    func testTopViewportInsetChangeKeepsScrolledDocumentStableAwayFromTop() {
        let textBox = MutableBox(String(repeating: "Line\n", count: 120))
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let configuration = makeConfiguration(text: textBox.value)

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        textView.contentSize = CGSize(width: 320, height: 2400)
        textView.contentOffset = CGPoint(x: 0, y: 120)

        coordinator.applyTopViewportInset(92, to: textView)

        XCTAssertEqual(textView.contentOffset.y, 120, accuracy: 0.5)
        XCTAssertEqual(
            textView.textContainerInset.top,
            EditorTextViewLayout.effectiveTopInset(topViewportInset: 92),
            accuracy: 0.5
        )
    }

    @MainActor
    func testSavedDateHeaderPublishesPullDistanceOnlyWhenDocumentIsPulledDown() {
        let textBox = MutableBox("Draft")
        var pullDistanceEvents: [CGFloat] = []
        let coordinator = MarkdownEditorTextView.Coordinator(
            text: Binding(
                get: { textBox.value },
                set: { textBox.value = $0 }
            ),
            onEditorFocusChange: { _ in },
            onUndoRedoAvailabilityChange: { _, _ in },
            onSavedDateHeaderPullDistanceChange: { pullDistanceEvents.append($0) }
        )
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))

        textView.contentOffset = CGPoint(x: 0, y: 48)
        coordinator.scrollViewDidScroll(textView)
        textView.contentOffset = CGPoint(x: 0, y: -20)
        coordinator.scrollViewDidScroll(textView)
        textView.contentOffset = CGPoint(x: 0, y: -8)
        coordinator.scrollViewDidScroll(textView)
        textView.contentOffset = CGPoint(x: 0, y: 0)
        coordinator.scrollViewDidScroll(textView)

        XCTAssertEqual(pullDistanceEvents.count, 3)
        XCTAssertEqual(pullDistanceEvents[0], 20, accuracy: 0.5)
        XCTAssertEqual(pullDistanceEvents[1], 8, accuracy: 0.5)
        XCTAssertEqual(pullDistanceEvents[2], 0, accuracy: 0.5)
    }

    @MainActor
    func testAccessoryLayoutDoesNotRewriteBottomKeyboardInsets() {
        let textBox = MutableBox("Draft")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let configuration = makeConfiguration(text: textBox.value)

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        guard let accessoryView = textView.inputAccessoryView as? KeyboardAccessoryToolbarView else {
            XCTFail("Expected keyboard accessory toolbar view")
            return
        }

        coordinator.applyKeyboardOverlap(240, to: textView)
        let originalBottomInset = textView.contentInset.bottom
        let originalIndicatorBottomInset = textView.verticalScrollIndicatorInsets.bottom

        accessoryView.frame = CGRect(x: 0, y: 0, width: 320, height: 44)
        accessoryView.setNeedsLayout()
        accessoryView.layoutIfNeeded()
        accessoryView.update(canUndo: true, canRedo: false, canDismiss: true)

        XCTAssertEqual(textView.contentInset.bottom, originalBottomInset, accuracy: 0.5)
        XCTAssertEqual(textView.verticalScrollIndicatorInsets.bottom, originalIndicatorBottomInset, accuracy: 0.5)
    }

    @MainActor
    func testKeyboardAccessoryReportsToolbarSizedHeight() {
        let actionTarget = AccessoryActionTarget()
        let theme = ResolvedEditorTheme.default
        let accessoryView = KeyboardAccessoryToolbarView(
            target: actionTarget,
            undoAction: #selector(AccessoryActionTarget.performAction),
            redoAction: #selector(AccessoryActionTarget.performAction),
            dismissAction: #selector(AccessoryActionTarget.performAction),
            resolvedTheme: theme
        )

        let fittedSize = accessoryView.sizeThatFits(CGSize(width: 320, height: UIView.noIntrinsicMetric))

        XCTAssertGreaterThan(fittedSize.height, 0)
        XCTAssertClear(accessoryView.backgroundColor)
        XCTAssertFalse(accessoryView.isOpaque)
        XCTAssertEqual(accessoryView.toolbar.tintColor, theme.accent)
        XCTAssertGreaterThan(accessoryView.intrinsicContentSize.height, 0)
    }

    @MainActor
    func testKeyboardAccessoryPlacesFormatButtonLeftAndEditingButtonsRight() {
        let actionTarget = AccessoryActionTarget()
        let accessoryView = KeyboardAccessoryToolbarView(
            target: actionTarget,
            undoAction: #selector(AccessoryActionTarget.performAction),
            redoAction: #selector(AccessoryActionTarget.performAction),
            dismissAction: #selector(AccessoryActionTarget.performAction),
            resolvedTheme: .default,
            showsDismissButton: true
        )

        let items = accessoryView.toolbar.items ?? []

        XCTAssertEqual(items.count, 6)
        XCTAssertTrue(items.first === accessoryView.formatButton)
        XCTAssertNil(accessoryView.formatButton.title)
        XCTAssertNotNil(accessoryView.formatButton.image)
        XCTAssertEqual(accessoryView.formatButton.accessibilityLabel, "Format")
        XCTAssertTrue(items[2] === accessoryView.undoButton)
        XCTAssertTrue(items[3] === accessoryView.redoButton)
        XCTAssertEqual(items[4].width, 8)
        XCTAssertTrue(items.last === accessoryView.dismissButton)
    }

    @MainActor
    func testKeyboardAccessoryCanHideDismissButtonForIPad() {
        let actionTarget = AccessoryActionTarget()
        let accessoryView = KeyboardAccessoryToolbarView(
            target: actionTarget,
            undoAction: #selector(AccessoryActionTarget.performAction),
            redoAction: #selector(AccessoryActionTarget.performAction),
            dismissAction: #selector(AccessoryActionTarget.performAction),
            resolvedTheme: .default,
            showsDismissButton: false
        )

        accessoryView.update(canUndo: true, canRedo: true, canDismiss: true)

        XCTAssertEqual(accessoryView.toolbar.items?.count, 4)
        XCTAssertTrue(accessoryView.toolbar.items?.first === accessoryView.formatButton)
        XCTAssertTrue(accessoryView.toolbar.items?.last === accessoryView.redoButton)
        XCTAssertFalse(accessoryView.toolbar.items?.contains(accessoryView.dismissButton) ?? true)
        XCTAssertFalse(accessoryView.dismissButton.isEnabled)
    }

    @MainActor
    func testEditorChromeStyleControlsKeyboardAndAccessoryAppearance() {
        let actionTarget = AccessoryActionTarget()
        let textView = TrackingUndoTextView()
        let accessoryView = KeyboardAccessoryToolbarView(
            target: actionTarget,
            undoAction: #selector(AccessoryActionTarget.performAction),
            redoAction: #selector(AccessoryActionTarget.performAction),
            dismissAction: #selector(AccessoryActionTarget.performAction),
            resolvedTheme: .default
        )
        textView.keyboardAccessoryToolbarView = accessoryView

        textView.applyEditorChromeInterfaceStyle(.dark)

        XCTAssertEqual(textView.overrideUserInterfaceStyle, .dark)
        XCTAssertEqual(textView.keyboardAppearance, .dark)
        XCTAssertEqual(accessoryView.overrideUserInterfaceStyle, .dark)
        XCTAssertEqual(accessoryView.toolbar.overrideUserInterfaceStyle, .dark)

        textView.applyEditorChromeInterfaceStyle(.light)

        XCTAssertEqual(textView.overrideUserInterfaceStyle, .light)
        XCTAssertEqual(textView.keyboardAppearance, .light)
        XCTAssertEqual(accessoryView.overrideUserInterfaceStyle, .light)
        XCTAssertEqual(accessoryView.toolbar.overrideUserInterfaceStyle, .light)

        textView.applyEditorChromeInterfaceStyle(.unspecified)

        XCTAssertEqual(textView.overrideUserInterfaceStyle, .unspecified)
        XCTAssertEqual(textView.keyboardAppearance, .default)
        XCTAssertEqual(accessoryView.overrideUserInterfaceStyle, .unspecified)
        XCTAssertEqual(accessoryView.toolbar.overrideUserInterfaceStyle, .unspecified)
    }

    @MainActor
    func testKeyboardAccessoryKeepsUIKitHostBackgroundUntouched() {
        let actionTarget = AccessoryActionTarget()
        let accessoryView = KeyboardAccessoryToolbarView(
            target: actionTarget,
            undoAction: #selector(AccessoryActionTarget.performAction),
            redoAction: #selector(AccessoryActionTarget.performAction),
            dismissAction: #selector(AccessoryActionTarget.performAction),
            resolvedTheme: .default
        )
        let hostView = UIView()
        hostView.backgroundColor = .white
        hostView.isOpaque = true

        hostView.addSubview(accessoryView)
        accessoryView.frame = CGRect(x: 0, y: 0, width: 320, height: 52)
        accessoryView.layoutIfNeeded()

        XCTAssertEqual(hostView.backgroundColor, .white)
        XCTAssertTrue(hostView.isOpaque)
        XCTAssertClear(accessoryView.backgroundColor)
        XCTAssertFalse(accessoryView.isOpaque)

        let paintedTheme = makeResolvedTheme(keyboardAccessoryUnderlayBackground: .brown)
        hostView.backgroundColor = .white
        hostView.isOpaque = true
        accessoryView.applyResolvedTheme(paintedTheme)

        XCTAssertEqual(hostView.backgroundColor, .white)
        XCTAssertTrue(hostView.isOpaque)
        XCTAssertClear(accessoryView.backgroundColor)
        XCTAssertFalse(accessoryView.isOpaque)
        XCTAssertEqual(accessoryView.toolbar.tintColor, paintedTheme.accent)
    }

    @MainActor
    func testDefaultThemeReapplicationPreservesClearAccessoryHost() {
        let actionTarget = AccessoryActionTarget()
        let accessoryView = KeyboardAccessoryToolbarView(
            target: actionTarget,
            undoAction: #selector(AccessoryActionTarget.performAction),
            redoAction: #selector(AccessoryActionTarget.performAction),
            dismissAction: #selector(AccessoryActionTarget.performAction),
            resolvedTheme: .default
        )
        let customTheme = ResolvedEditorTheme(
            editorBackground: .black,
            keyboardAccessoryUnderlayBackground: .brown,
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

        accessoryView.applyResolvedTheme(customTheme)
        XCTAssertClear(accessoryView.backgroundColor)
        XCTAssertFalse(accessoryView.isOpaque)
        XCTAssertEqual(accessoryView.toolbar.tintColor, customTheme.accent)

        accessoryView.applyResolvedTheme(.default)

        XCTAssertClear(accessoryView.backgroundColor)
        XCTAssertFalse(accessoryView.isOpaque)
        XCTAssertEqual(accessoryView.toolbar.tintColor, ResolvedEditorTheme.default.accent)
    }

    @MainActor
    func testCoordinatorPropagatesResolvedThemeToAccessoryAndLayoutManager() {
        let textBox = MutableBox("Draft `code`\n> Quote")
        let coordinator = makeCoordinator(text: textBox)
        let textStorage = NSTextStorage()
        let layoutManager = MarkdownCodeBackgroundLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), textContainer: textContainer)
        let theme = ResolvedEditorTheme(
            editorBackground: .black,
            keyboardAccessoryUnderlayBackground: .brown,
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
        let configuration = MarkdownEditorTextView.Configuration(
            text: textBox.value,
            documentIdentity: PreviewSampleData.cleanDocument.url,
            font: .preferredFont(forTextStyle: .body),
            resolvedTheme: theme,
            syntaxMode: .visible,
            isEditable: true
        )

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        guard let accessoryView = textView.inputAccessoryView as? KeyboardAccessoryToolbarView else {
            return XCTFail("Expected a keyboard accessory toolbar view")
        }
        guard let layoutManager = textView.layoutManager as? MarkdownCodeBackgroundLayoutManager else {
            return XCTFail("Expected markdown layout manager")
        }

        XCTAssertClear(accessoryView.backgroundColor)
        XCTAssertFalse(accessoryView.isOpaque)
        XCTAssertEqual(accessoryView.toolbar.tintColor, theme.accent)
        XCTAssertEqual(layoutManager.resolvedTheme, theme)
        XCTAssertEqual(textView.backgroundColor, theme.editorBackground)
        XCTAssertTrue(textView.isOpaque)
        XCTAssertEqual(textView.tintColor, theme.accent)
        XCTAssertEqual(
            textView.typingAttributes[.foregroundColor] as? UIColor,
            theme.primaryText
        )
    }

    @MainActor
    func testCoordinatorExecutesPendingUndoCommand() {
        let textBox = MutableBox("Draft")
        var focusEvents: [Bool] = []
        var availabilityEvents: [(Bool, Bool)] = []
        let coordinator = MarkdownEditorTextView.Coordinator(
            text: Binding(
                get: { textBox.value },
                set: { textBox.value = $0 }
            ),
            onEditorFocusChange: { focusEvents.append($0) },
            onUndoRedoAvailabilityChange: { canUndo, canRedo in
                availabilityEvents.append((canUndo, canRedo))
            }
        )
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let configuration = makeConfiguration(text: textBox.value)

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        textView.trackingUndoManager.simulatedCanUndo = true
        textView.trackingUndoManager.simulatedCanRedo = false

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 1,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: false
        )

        XCTAssertEqual(textView.trackingUndoManager.undoCallCount, 1)
        XCTAssertEqual(textView.trackingUndoManager.redoCallCount, 0)
        XCTAssertTrue(focusEvents.isEmpty)
        XCTAssertEqual(availabilityEvents.last?.0, false)
        XCTAssertEqual(availabilityEvents.last?.1, true)
    }

    @MainActor
    func testCoordinatorExecutesPendingRedoCommand() {
        let textBox = MutableBox("Draft")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let configuration = makeConfiguration(text: textBox.value)

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        textView.trackingUndoManager.simulatedCanUndo = false
        textView.trackingUndoManager.simulatedCanRedo = true

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 1,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: false
        )

        XCTAssertEqual(textView.trackingUndoManager.undoCallCount, 0)
        XCTAssertEqual(textView.trackingUndoManager.redoCallCount, 1)
    }

    @MainActor
    func testCoordinatorExecutesPendingKeyboardDismissCommand() {
        let textBox = MutableBox("Draft")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let configuration = makeConfiguration(text: textBox.value)

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        textView.simulatedIsFirstResponder = true

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 1,
            to: textView,
            force: false
        )

        XCTAssertGreaterThanOrEqual(textView.resignFirstResponderCallCount, 1)
    }

    @MainActor
    func testCoordinatorConfiguresNativeKeyboardAccessoryToolbar() {
        let textBox = MutableBox("Draft")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        textView.simulatedIsFirstResponder = true
        textView.trackingUndoManager.simulatedCanUndo = true
        textView.trackingUndoManager.simulatedCanRedo = false
        let configuration = makeConfiguration(text: textBox.value)

        coordinator.configureKeyboardAccessory(for: textView, resolvedTheme: .default)
        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        guard let accessoryView = textView.inputAccessoryView as? KeyboardAccessoryToolbarView else {
            return XCTFail("Expected a keyboard accessory toolbar view")
        }

        XCTAssertNotNil(textView.inputAccessoryView)
        XCTAssertTrue(accessoryView === textView.keyboardAccessoryToolbarView)
        XCTAssertAccessoryToolbarItemsMatchCurrentIdiom(
            textView.keyboardAccessoryToolbarView?.toolbar.items,
            formatItem: textView.formatAccessoryItem,
            undoItem: textView.undoAccessoryItem,
            redoItem: textView.redoAccessoryItem,
            dismissItem: textView.dismissAccessoryItem
        )
        XCTAssertNotNil(textView.formatAccessoryItem?.menu)
        XCTAssertEqual(textView.undoAccessoryItem?.isEnabled, true)
        XCTAssertEqual(textView.redoAccessoryItem?.isEnabled, false)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertEqual(textView.dismissAccessoryItem?.isEnabled, false)
        } else {
            XCTAssertEqual(textView.dismissAccessoryItem?.isEnabled, true)
        }
        XCTAssertEqual(textView.reloadInputViewsCallCount, 1)
    }

    @MainActor
    func testCoordinatorDoesNotRebuildFormatMenuDuringAccessoryRefresh() throws {
        let textBox = MutableBox("Draft")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))

        coordinator.configureKeyboardAccessory(for: textView, resolvedTheme: .default)
        let initialMenu = try XCTUnwrap(textView.formatAccessoryItem?.menu)

        coordinator.configureKeyboardAccessory(for: textView, resolvedTheme: .default)

        XCTAssertTrue(textView.formatAccessoryItem?.menu === initialMenu)
    }

    @MainActor
    func testCoordinatorFormatMenuOffersCodeLineAndCodeBlock() throws {
        let textBox = MutableBox("Draft")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))

        coordinator.configureKeyboardAccessory(for: textView, resolvedTheme: .default)

        let menu = try XCTUnwrap(textView.formatAccessoryItem?.menu)
        let codeMenu = try XCTUnwrap(menu.children.compactMap { $0 as? UIMenu }.first { $0.title == "Code" })

        XCTAssertEqual(codeMenu.children.map(\.title), ["Code Block", "Code Line"])
    }

    @MainActor
    func testCoordinatorAccessoryBoldWrapsSelectedText() {
        let textBox = MutableBox("Hello world")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        textView.selectedRange = NSRange(location: 6, length: 5)
        coordinator.applyInlineMarkdownFormatForTesting(marker: "**", in: textView)

        XCTAssertEqual(textBox.value, "Hello **world**")
        XCTAssertEqual(textView.selectedRange, NSRange(location: 8, length: 5))
    }

    @MainActor
    func testCoordinatorAccessoryInlineFormatTogglesWrappedSelectionOff() {
        let textBox = MutableBox("Hello **world**")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        textView.selectedRange = NSRange(location: 8, length: 5)
        coordinator.applyInlineMarkdownFormatForTesting(marker: "**", in: textView)

        XCTAssertEqual(textBox.value, "Hello world")
        XCTAssertEqual(textView.selectedRange, NSRange(location: 6, length: 5))
    }

    @MainActor
    func testCoordinatorAccessoryItalicWithEmptySelectionPlacesCursorInsideMarkers() {
        let textBox = MutableBox("Hello ")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        textView.selectedRange = NSRange(location: 6, length: 0)
        coordinator.applyInlineMarkdownFormatForTesting(marker: "*", in: textView)

        XCTAssertEqual(textBox.value, "Hello **")
        XCTAssertEqual(textView.selectedRange, NSRange(location: 7, length: 0))
    }

    @MainActor
    func testCoordinatorAccessoryCodeBlockWrapsSelectedText() {
        let textBox = MutableBox("let value = 1")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        textView.selectedRange = NSRange(location: 0, length: (textBox.value as NSString).length)
        coordinator.applyCodeBlockMarkdownFormatForTesting(in: textView)

        XCTAssertEqual(textBox.value, "```\nlet value = 1\n```")
        XCTAssertEqual(textView.selectedRange, NSRange(location: 4, length: 13))
    }

    @MainActor
    func testCoordinatorAccessoryCodeBlockWithEmptySelectionPlacesCursorInsideBlock() {
        let textBox = MutableBox("Before\nAfter")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        textView.selectedRange = NSRange(location: 7, length: 0)
        coordinator.applyCodeBlockMarkdownFormatForTesting(in: textView)

        XCTAssertEqual(textBox.value, "Before\n```\n\n```\nAfter")
        XCTAssertEqual(textView.selectedRange, NSRange(location: 11, length: 0))
    }

    @MainActor
    func testCoordinatorAccessoryTaskPrefixesCurrentLine() {
        let textBox = MutableBox("one\ntwo")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        textView.selectedRange = NSRange(location: 4, length: 0)
        coordinator.applyLineMarkdownPrefixForTesting("- [ ] ", in: textView)

        XCTAssertEqual(textBox.value, "one\n- [ ] two")
        XCTAssertEqual(textView.selectedRange, NSRange(location: 10, length: 0))
    }

    @MainActor
    func testCoordinatorAccessoryTaskInsertsOnCollapsedBlankLine() {
        let textBox = MutableBox("one\n\ntwo")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        textView.selectedRange = NSRange(location: 4, length: 0)
        coordinator.applyLineMarkdownPrefixForTesting("- [ ] ", in: textView)

        XCTAssertEqual(textBox.value, "one\n- [ ] \ntwo")
        XCTAssertEqual(textView.selectedRange, NSRange(location: 10, length: 0))
    }

    @MainActor
    func testCoordinatorAccessoryHeaderPrefixesSelectedLines() {
        let textBox = MutableBox("one\ntwo")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        textView.selectedRange = NSRange(location: 0, length: 7)
        coordinator.applyLineMarkdownPrefixForTesting("### ", in: textView)

        XCTAssertEqual(textBox.value, "### one\n### two")
        XCTAssertEqual(textView.selectedRange, NSRange(location: 0, length: 15))
    }

    @MainActor
    func testCoordinatorAccessoryInsertsLinkForSelectedURL() {
        let textBox = MutableBox("https://example.com")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        textView.selectedRange = NSRange(location: 0, length: (textBox.value as NSString).length)
        coordinator.insertMarkdownLinkForTesting(in: textView)

        XCTAssertEqual(textBox.value, "[link](https://example.com)")
        XCTAssertEqual(textView.selectedRange, NSRange(location: 1, length: 4))
    }

    @MainActor
    func testCoordinatorAccessoryBoldParticipatesInUndoRedo() {
        let (textBox, coordinator, textView) = makeFormatterUndoSystem(text: "Hello world")

        textView.selectedRange = NSRange(location: 6, length: 5)
        coordinator.applyInlineMarkdownFormatForTesting(marker: "**", in: textView)

        XCTAssertEqual(textBox.value, "Hello **world**")
        XCTAssertEqual(textView.selectedRange, NSRange(location: 8, length: 5))
        assertFormatterUndoRedo(
            textBox: textBox,
            textView: textView,
            undoText: "Hello world",
            undoSelection: NSRange(location: 6, length: 5),
            redoText: "Hello **world**",
            redoSelection: NSRange(location: 8, length: 5)
        )
    }

    @MainActor
    func testCoordinatorAccessoryLinkInsertionParticipatesInUndoRedo() {
        let (textBox, coordinator, textView) = makeFormatterUndoSystem(text: "Hello ")

        textView.selectedRange = NSRange(location: 6, length: 0)
        coordinator.insertMarkdownLinkForTesting(in: textView)

        XCTAssertEqual(textBox.value, "Hello [text](https://)")
        XCTAssertEqual(textView.selectedRange, NSRange(location: 7, length: 4))
        assertFormatterUndoRedo(
            textBox: textBox,
            textView: textView,
            undoText: "Hello ",
            undoSelection: NSRange(location: 6, length: 0),
            redoText: "Hello [text](https://)",
            redoSelection: NSRange(location: 7, length: 4)
        )
    }

    @MainActor
    func testCoordinatorAccessoryCodeBlockParticipatesInUndoRedo() {
        let (textBox, coordinator, textView) = makeFormatterUndoSystem(text: "let value = 1")

        textView.selectedRange = NSRange(location: 0, length: (textBox.value as NSString).length)
        coordinator.applyCodeBlockMarkdownFormatForTesting(in: textView)

        XCTAssertEqual(textBox.value, "```\nlet value = 1\n```")
        XCTAssertEqual(textView.selectedRange, NSRange(location: 4, length: 13))
        assertFormatterUndoRedo(
            textBox: textBox,
            textView: textView,
            undoText: "let value = 1",
            undoSelection: NSRange(location: 0, length: 13),
            redoText: "```\nlet value = 1\n```",
            redoSelection: NSRange(location: 4, length: 13)
        )
    }

    @MainActor
    func testCoordinatorAccessoryTaskPrefixParticipatesInUndoRedo() {
        let (textBox, coordinator, textView) = makeFormatterUndoSystem(text: "one\ntwo")

        textView.selectedRange = NSRange(location: 4, length: 0)
        coordinator.applyLineMarkdownPrefixForTesting("- [ ] ", in: textView)

        XCTAssertEqual(textBox.value, "one\n- [ ] two")
        XCTAssertEqual(textView.selectedRange, NSRange(location: 10, length: 0))
        assertFormatterUndoRedo(
            textBox: textBox,
            textView: textView,
            undoText: "one\ntwo",
            undoSelection: NSRange(location: 4, length: 0),
            redoText: "one\n- [ ] two",
            redoSelection: NSRange(location: 10, length: 0)
        )
    }

    @MainActor
    func testCoordinatorAccessoryHeadingPrefixParticipatesInUndoRedo() {
        let (textBox, coordinator, textView) = makeFormatterUndoSystem(text: "one\ntwo")

        textView.selectedRange = NSRange(location: 0, length: 7)
        coordinator.applyLineMarkdownPrefixForTesting("### ", in: textView)

        XCTAssertEqual(textBox.value, "### one\n### two")
        XCTAssertEqual(textView.selectedRange, NSRange(location: 0, length: 15))
        assertFormatterUndoRedo(
            textBox: textBox,
            textView: textView,
            undoText: "one\ntwo",
            undoSelection: NSRange(location: 0, length: 7),
            redoText: "### one\n### two",
            redoSelection: NSRange(location: 0, length: 15)
        )
    }

    @MainActor
    func testCoordinatorAccessoryInlineFormatToggleOffParticipatesInUndoRedo() {
        let (textBox, coordinator, textView) = makeFormatterUndoSystem(text: "Hello **world**")

        textView.selectedRange = NSRange(location: 8, length: 5)
        coordinator.applyInlineMarkdownFormatForTesting(marker: "**", in: textView)

        XCTAssertEqual(textBox.value, "Hello world")
        XCTAssertEqual(textView.selectedRange, NSRange(location: 6, length: 5))
        assertFormatterUndoRedo(
            textBox: textBox,
            textView: textView,
            undoText: "Hello **world**",
            undoSelection: NSRange(location: 8, length: 5),
            redoText: "Hello world",
            redoSelection: NSRange(location: 6, length: 5)
        )
    }

    @MainActor
    func testCoordinatorTaskCheckboxUncheckedToggleParticipatesInUndoRedo() {
        assertTaskCheckboxToggleUndoRedo(
            initialText: "- [ ] Task",
            checkboxText: "[ ]",
            toggledText: "- [x] Task",
            initialColor: ResolvedEditorTheme.default.checkboxUnchecked,
            toggledColor: ResolvedEditorTheme.default.checkboxChecked
        )
    }

    @MainActor
    func testCoordinatorTaskCheckboxCheckedToggleParticipatesInUndoRedo() {
        assertTaskCheckboxToggleUndoRedo(
            initialText: "- [x] Done",
            checkboxText: "[x]",
            toggledText: "- [ ] Done",
            initialColor: ResolvedEditorTheme.default.checkboxChecked,
            toggledColor: ResolvedEditorTheme.default.checkboxUnchecked
        )
    }

    @MainActor
    func testCoordinatorTaskCheckboxPartialToggleParticipatesInUndoRedo() {
        assertTaskCheckboxToggleUndoRedo(
            initialText: "- [/] Partial",
            checkboxText: "[/]",
            toggledText: "- [x] Partial",
            initialColor: ResolvedEditorTheme.default.checkboxChecked,
            toggledColor: ResolvedEditorTheme.default.checkboxChecked
        )
    }

    @MainActor
    func testCoordinatorSemanticLinePrefixKeepsZeroLengthSelectionReasonable() {
        let cases: [(text: String, prefix: String, expectedText: String, expectedSelection: NSRange)] = [
            ("## Title", "### ", "### Title", NSRange(location: 4, length: 0)),
            ("### Title", "# ", "# Title", NSRange(location: 2, length: 0)),
            ("- [ ] Task", "- [ ] ", "Task", NSRange(location: 0, length: 0)),
            ("- [x] Done", "- [ ] ", "Done", NSRange(location: 0, length: 0)),
            ("1. [ ] Ordered", "- [ ] ", "Ordered", NSRange(location: 0, length: 0))
        ]

        for testCase in cases {
            let textBox = MutableBox(testCase.text)
            let coordinator = makeCoordinator(text: textBox)
            let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
            coordinator.apply(
                configuration: makeConfiguration(text: textBox.value),
                undoCommandToken: 0,
                redoCommandToken: 0,
                dismissKeyboardCommandToken: 0,
                to: textView,
                force: true
            )

            textView.selectedRange = NSRange(location: 0, length: 0)
            coordinator.applyLineMarkdownPrefixForTesting(testCase.prefix, in: textView)

            XCTAssertEqual(textBox.value, testCase.expectedText)
            XCTAssertEqual(textView.selectedRange, testCase.expectedSelection)
        }
    }

    @MainActor
    func testSameLineTypingDoesNotForceHiddenSyntaxRerender() {
        let textBox = MutableBox("First line\nSecond line")
        let coordinator = makeCoordinator(text: textBox)

        let previousLine = NSRange(location: 11, length: 11)
        let sameLineAfterTyping = NSRange(location: 11, length: 12)

        XCTAssertFalse(
            coordinator.shouldRefreshRevealedLine(
                previousRange: previousLine,
                currentRange: sameLineAfterTyping,
                selectionRange: NSRange(location: 18, length: 0),
                textChangeTouchedLineBreaks: false
            ),
            "Typing regular characters on the same line should not rerender the full attributed document."
        )

        XCTAssertTrue(
            coordinator.shouldRefreshRevealedLine(
                previousRange: previousLine,
                currentRange: sameLineAfterTyping,
                selectionRange: NSRange(location: 18, length: 0),
                textChangeTouchedLineBreaks: true
            ),
            "Line-break edits can change which text belongs to the current line and should still rerender."
        )

        XCTAssertTrue(
            coordinator.shouldRefreshRevealedLine(
                previousRange: previousLine,
                currentRange: NSRange(location: 0, length: 10),
                selectionRange: NSRange(location: 5, length: 0),
                textChangeTouchedLineBreaks: false
            ),
            "Moving to a different line should still refresh the hidden-syntax presentation."
        )

        XCTAssertTrue(
            coordinator.shouldRefreshRevealedLine(
                previousRange: previousLine,
                currentRange: sameLineAfterTyping,
                selectionRange: NSRange(location: 11, length: 12),
                textChangeTouchedLineBreaks: false
            ),
            "Multi-line or explicit selections should still refresh because the revealed range can expand."
        )
    }

    @MainActor
    func testCoordinatorRestylesSameLineTypingImmediatelyWithoutDeferredFullRerender() {
        let textBox = MutableBox("Draft")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        textView.simulatedIsFirstResponder = true
        let configuration = MarkdownEditorTextView.Configuration(
            text: textBox.value,
            documentIdentity: PreviewSampleData.cleanDocument.url,
            font: .preferredFont(forTextStyle: .body),
            syntaxMode: .hiddenOutsideCurrentLine,
            isEditable: true
        )

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        XCTAssertTrue(
            coordinator.textView(
                textView,
                shouldChangeTextIn: NSRange(location: 5, length: 0),
                replacementText: " **bold**"
            )
        )
        textView.text = "Draft **bold**"
        textView.selectedRange = NSRange(location: (textView.text as NSString).length, length: 0)

        coordinator.textViewDidChange(textView)
        coordinator.textViewDidChangeSelection(textView)

        let markerRange = (textView.text as NSString).range(of: "**")
        XCTAssertFalse(coordinator.hasPendingFullDocumentRerender)
        XCTAssertFalse(coordinator.hasPendingDeferredRerender)
        XCTAssertEqual(
            (textView.textStorage.attribute(.markdownSyntaxToken, at: markerRange.location, effectiveRange: nil) as? Int)
                .flatMap(MarkdownSyntaxVisibilityRule.init(rawValue:)),
            .followsMode
        )
    }

    @MainActor
    func testCoordinatorDoesNotRevealTopLineMarkdownSyntaxBeforeEditorFocus() {
        let textBox = MutableBox("# Heading\nBody")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        textView.selectedRange = NSRange(location: 0, length: 0)
        let configuration = MarkdownEditorTextView.Configuration(
            text: textBox.value,
            documentIdentity: PreviewSampleData.cleanDocument.url,
            font: .preferredFont(forTextStyle: .body),
            syntaxMode: .hiddenOutsideCurrentLine,
            isEditable: true
        )

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        let markerRange = (textView.text as NSString).range(of: "#")
        XCTAssertEqual(textView.textStorage.attribute(.markdownHiddenSyntax, at: markerRange.location, effectiveRange: nil) as? Bool, true)

        textView.simulatedIsFirstResponder = true
        coordinator.textViewDidBeginEditing(textView)
        XCTAssertNil(textView.textStorage.attribute(.markdownHiddenSyntax, at: markerRange.location, effectiveRange: nil))

        coordinator.textViewDidEndEditing(textView)
        XCTAssertEqual(textView.textStorage.attribute(.markdownHiddenSyntax, at: markerRange.location, effectiveRange: nil) as? Bool, true)
    }

    @MainActor
    func testCoordinatorRevealsFencedCodeMarkersWhenCaretIsInsideBlock() {
        let text = "Before\n```\ncode\n```\nAfter"
        let textBox = MutableBox(text)
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        textView.simulatedIsFirstResponder = true
        let configuration = MarkdownEditorTextView.Configuration(
            text: textBox.value,
            documentIdentity: PreviewSampleData.cleanDocument.url,
            font: .preferredFont(forTextStyle: .body),
            syntaxMode: .hiddenOutsideCurrentLine,
            isEditable: true
        )

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )
        textView.selectedRange = NSRange(location: (text as NSString).range(of: "code").location, length: 0)
        coordinator.textViewDidChangeSelection(textView)

        let nsText = textView.text as NSString
        let openingFenceRange = nsText.range(of: "```")
        let closingFenceRange = nsText.range(
            of: "```",
            options: [],
            range: NSRange(
                location: NSMaxRange(openingFenceRange),
                length: nsText.length - NSMaxRange(openingFenceRange)
            )
        )

        XCTAssertNil(textView.textStorage.attribute(.markdownHiddenSyntax, at: openingFenceRange.location, effectiveRange: nil))
        XCTAssertNil(textView.textStorage.attribute(.markdownHiddenSyntax, at: closingFenceRange.location, effectiveRange: nil))
    }

    @MainActor
    func testCoordinatorDefersFullMarkdownRerenderAfterLineBreakEdit() async {
        let textBox = MutableBox("Draft")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        textView.simulatedIsFirstResponder = true
        let configuration = MarkdownEditorTextView.Configuration(
            text: textBox.value,
            documentIdentity: PreviewSampleData.cleanDocument.url,
            font: .preferredFont(forTextStyle: .body),
            syntaxMode: .hiddenOutsideCurrentLine,
            isEditable: true
        )

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        XCTAssertTrue(
            coordinator.textView(
                textView,
                shouldChangeTextIn: NSRange(location: 5, length: 0),
                replacementText: "\n**bold**"
            )
        )
        textView.text = "Draft\n**bold**"
        textView.selectedRange = NSRange(location: (textView.text as NSString).length, length: 0)

        coordinator.textViewDidChange(textView)
        coordinator.textViewDidChangeSelection(textView)

        let markerRange = (textView.text as NSString).range(of: "**")
        XCTAssertTrue(coordinator.hasPendingFullDocumentRerender)
        XCTAssertTrue(coordinator.hasPendingDeferredRerender)
        XCTAssertNil(
            textView.textStorage.attribute(.markdownSyntaxToken, at: markerRange.location, effectiveRange: nil) as? Int
        )

        try? await Task.sleep(for: MarkdownEditorTextView.Coordinator.deferredRerenderDelay + .milliseconds(80))

        XCTAssertFalse(coordinator.hasPendingFullDocumentRerender)
        XCTAssertFalse(coordinator.hasPendingDeferredRerender)
        XCTAssertEqual(
            (textView.textStorage.attribute(.markdownSyntaxToken, at: markerRange.location, effectiveRange: nil) as? Int)
                .flatMap(MarkdownSyntaxVisibilityRule.init(rawValue:)),
            .followsMode
        )
    }

    @MainActor
    func testCoordinatorUsesIncrementalRestyleForLargeSameLineTyping() {
        let largeParagraph = String(repeating: "word ", count: 12_000)
        let textBox = MutableBox(largeParagraph)
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        textView.simulatedIsFirstResponder = true
        let configuration = MarkdownEditorTextView.Configuration(
            text: textBox.value,
            documentIdentity: PreviewSampleData.cleanDocument.url,
            font: .preferredFont(forTextStyle: .body),
            syntaxMode: .hiddenOutsideCurrentLine,
            isEditable: true
        )

        coordinator.apply(
            configuration: configuration,
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        let insertionLocation = (textView.text as NSString).length
        XCTAssertTrue(
            coordinator.textView(
                textView,
                shouldChangeTextIn: NSRange(location: insertionLocation, length: 0),
                replacementText: "**bold**"
            )
        )
        textView.text += "**bold**"
        textView.selectedRange = NSRange(location: (textView.text as NSString).length, length: 0)

        coordinator.textViewDidChange(textView)

        let markerRange = (textView.text as NSString).range(of: "**bold**")
        XCTAssertFalse(coordinator.hasPendingFullDocumentRerender)
        XCTAssertFalse(coordinator.hasPendingDeferredRerender)
        XCTAssertEqual(
            (textView.textStorage.attribute(.markdownSyntaxToken, at: markerRange.location, effectiveRange: nil) as? Int)
                .flatMap(MarkdownSyntaxVisibilityRule.init(rawValue:)),
            .followsMode
        )
    }

    @MainActor
    func testDeferredRerenderIsReplacedByNewerStructuralEdit() async {
        let textBox = MutableBox("Draft")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))

        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        applyTextEdit("\nFirst", at: (textView.text as NSString).length, in: textView, coordinator: coordinator)
        XCTAssertTrue(coordinator.hasPendingFullDocumentRerender)
        XCTAssertTrue(coordinator.hasPendingDeferredRerender)

        try? await Task.sleep(for: .milliseconds(70))
        applyTextEdit("\nSecond", at: (textView.text as NSString).length, in: textView, coordinator: coordinator)

        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(coordinator.hasPendingFullDocumentRerender)
        XCTAssertTrue(coordinator.hasPendingDeferredRerender)
        XCTAssertEqual(textView.text, "Draft\nFirst\nSecond")

        try? await Task.sleep(for: MarkdownEditorTextView.Coordinator.deferredRerenderDelay)
        XCTAssertFalse(coordinator.hasPendingFullDocumentRerender)
        XCTAssertFalse(coordinator.hasPendingDeferredRerender)
        XCTAssertEqual(textView.text, "Draft\nFirst\nSecond")
    }

    @MainActor
    func testDeferredRerenderDoesNotApplyAfterDocumentIdentityChanges() async {
        let documentA = URL(fileURLWithPath: "/tmp/DocumentA.md")
        let documentB = URL(fileURLWithPath: "/tmp/DocumentB.md")
        let textBox = MutableBox("Document A")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))

        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value, documentIdentity: documentA),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )
        applyTextEdit("\nStructural A", at: (textView.text as NSString).length, in: textView, coordinator: coordinator)
        XCTAssertTrue(coordinator.hasPendingDeferredRerender)

        textBox.value = "Document B"
        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value, documentIdentity: documentB),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        XCTAssertFalse(coordinator.hasPendingFullDocumentRerender)
        XCTAssertFalse(coordinator.hasPendingDeferredRerender)

        try? await Task.sleep(for: MarkdownEditorTextView.Coordinator.deferredRerenderDelay + .milliseconds(80))
        XCTAssertEqual(textView.text, "Document B")
        XCTAssertEqual(textView.attributedText.string, "Document B")
        XCTAssertFalse(coordinator.hasPendingFullDocumentRerender)
        XCTAssertFalse(coordinator.hasPendingDeferredRerender)
    }

    @MainActor
    func testForceApplyingCurrentDocumentCancelsDeferredRerender() async {
        let textBox = MutableBox("Draft")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let documentIdentity = URL(fileURLWithPath: "/tmp/CurrentDocument.md")

        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value, documentIdentity: documentIdentity),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )
        applyTextEdit("\nStructural", at: (textView.text as NSString).length, in: textView, coordinator: coordinator)
        XCTAssertTrue(coordinator.hasPendingDeferredRerender)

        textBox.value = textView.text
        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value, documentIdentity: documentIdentity),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )

        XCTAssertFalse(coordinator.hasPendingFullDocumentRerender)
        XCTAssertFalse(coordinator.hasPendingDeferredRerender)

        try? await Task.sleep(for: MarkdownEditorTextView.Coordinator.deferredRerenderDelay + .milliseconds(80))
        XCTAssertEqual(textView.text, "Draft\nStructural")
        XCTAssertFalse(coordinator.hasPendingFullDocumentRerender)
        XCTAssertFalse(coordinator.hasPendingDeferredRerender)
    }

#if DEBUG
    @MainActor
    func testViewportResetTaskIsReplacedWhenDocumentIdentityChanges() async {
        let documentA = URL(fileURLWithPath: "/tmp/ViewportA.md")
        let documentB = URL(fileURLWithPath: "/tmp/ViewportB.md")
        let documentC = URL(fileURLWithPath: "/tmp/ViewportC.md")
        let textBox = MutableBox("Document A")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))

        coordinator.apply(
            configuration: makeConfiguration(text: "Document A", documentIdentity: documentA),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )
        textView.contentOffset = CGPoint(x: 0, y: 200)

        textBox.value = "Document B"
        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value, documentIdentity: documentB),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )
        XCTAssertTrue(coordinator.hasPendingViewportReset)

        textView.contentOffset = CGPoint(x: 0, y: 240)
        textBox.value = "Document C"
        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value, documentIdentity: documentC),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )
        XCTAssertTrue(coordinator.hasPendingViewportReset)

        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(coordinator.hasPendingViewportReset)
        XCTAssertEqual(textView.text, "Document C")
        XCTAssertTrue(coordinator.isNearDocumentStart(in: textView))
    }
#endif

    @MainActor
    private func applyTextEdit(
        _ replacement: String,
        at location: Int,
        in textView: UITextView,
        coordinator: MarkdownEditorTextView.Coordinator
    ) {
        let editRange = NSRange(location: location, length: 0)
        XCTAssertTrue(coordinator.textView(textView, shouldChangeTextIn: editRange, replacementText: replacement))
        textView.text = ((textView.text ?? "") as NSString).replacingCharacters(in: editRange, with: replacement)
        textView.selectedRange = NSRange(location: location + (replacement as NSString).length, length: 0)
        coordinator.textViewDidChange(textView)
    }

    @MainActor
    private func makeCoordinator(
        text: MutableBox<String>,
        openExternalURL: @escaping @MainActor (URL) -> Void = { _ in },
        openLocalMarkdownLink: @escaping @MainActor (String) -> Void = { _ in }
    ) -> MarkdownEditorTextView.Coordinator {
        let textBinding = Binding(
            get: { text.value },
            set: { text.value = $0 }
        )
        return MarkdownEditorTextView.Coordinator(
            text: textBinding,
            onEditorFocusChange: { _ in },
            onUndoRedoAvailabilityChange: { _, _ in },
            openExternalURL: openExternalURL,
            openLocalMarkdownLink: openLocalMarkdownLink
        )
    }

    @MainActor
    private func makeFormatterUndoSystem(
        text: String
    ) -> (MutableBox<String>, MarkdownEditorTextView.Coordinator, FormatterUndoTextView) {
        let textBox = MutableBox(text)
        let coordinator = makeCoordinator(text: textBox)
        let textView = FormatterUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        coordinator.apply(
            configuration: makeConfiguration(text: textBox.value),
            undoCommandToken: 0,
            redoCommandToken: 0,
            dismissKeyboardCommandToken: 0,
            to: textView,
            force: true
        )
        return (textBox, coordinator, textView)
    }

    @MainActor
    private func assertFormatterUndoRedo(
        textBox: MutableBox<String>,
        textView: FormatterUndoTextView,
        undoText: String,
        undoSelection: NSRange,
        redoText: String,
        redoSelection: NSRange,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(textView.formatterUndoManager.canUndo, file: file, line: line)
        XCTAssertEqual(textView.undoAccessoryItem?.isEnabled, true, file: file, line: line)

        textView.formatterUndoManager.undo()

        XCTAssertEqual(textBox.value, undoText, file: file, line: line)
        XCTAssertEqual(textView.selectedRange, undoSelection, file: file, line: line)
        XCTAssertTrue(textView.formatterUndoManager.canRedo, file: file, line: line)
        XCTAssertEqual(textView.redoAccessoryItem?.isEnabled, true, file: file, line: line)

        textView.formatterUndoManager.redo()

        XCTAssertEqual(textBox.value, redoText, file: file, line: line)
        XCTAssertEqual(textView.selectedRange, redoSelection, file: file, line: line)
        XCTAssertTrue(textView.formatterUndoManager.canUndo, file: file, line: line)
        XCTAssertEqual(textView.undoAccessoryItem?.isEnabled, true, file: file, line: line)
    }

    @MainActor
    private func assertTaskCheckboxToggleUndoRedo(
        initialText: String,
        checkboxText: String,
        toggledText: String,
        initialColor: UIColor,
        toggledColor: UIColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let (textBox, coordinator, textView) = makeFormatterUndoSystem(text: initialText)
        let initialCheckboxRange = (initialText as NSString).range(of: checkboxText)
        let preservedSelection = NSRange(location: (initialText as NSString).length, length: 0)
        textView.selectedRange = preservedSelection

        coordinator.toggleTaskCheckboxForTesting(in: initialCheckboxRange, textView: textView)

        XCTAssertEqual(textBox.value, toggledText, file: file, line: line)
        XCTAssertEqual(textView.selectedRange, preservedSelection, file: file, line: line)
        XCTAssertSameResolvedColor(
            textView.textStorage.attribute(.foregroundColor, at: initialCheckboxRange.location, effectiveRange: nil) as? UIColor,
            toggledColor,
            file: file,
            line: line
        )
        XCTAssertTrue(textView.formatterUndoManager.canUndo, file: file, line: line)
        XCTAssertEqual(textView.undoAccessoryItem?.isEnabled, true, file: file, line: line)

        textView.formatterUndoManager.undo()

        XCTAssertEqual(textBox.value, initialText, file: file, line: line)
        XCTAssertEqual(textView.selectedRange, preservedSelection, file: file, line: line)
        XCTAssertSameResolvedColor(
            textView.textStorage.attribute(.foregroundColor, at: initialCheckboxRange.location, effectiveRange: nil) as? UIColor,
            initialColor,
            file: file,
            line: line
        )
        XCTAssertTrue(textView.formatterUndoManager.canRedo, file: file, line: line)
        XCTAssertEqual(textView.redoAccessoryItem?.isEnabled, true, file: file, line: line)

        textView.formatterUndoManager.redo()

        XCTAssertEqual(textBox.value, toggledText, file: file, line: line)
        XCTAssertEqual(textView.selectedRange, preservedSelection, file: file, line: line)
        XCTAssertSameResolvedColor(
            textView.textStorage.attribute(.foregroundColor, at: initialCheckboxRange.location, effectiveRange: nil) as? UIColor,
            toggledColor,
            file: file,
            line: line
        )
        XCTAssertTrue(textView.formatterUndoManager.canUndo, file: file, line: line)
        XCTAssertEqual(textView.undoAccessoryItem?.isEnabled, true, file: file, line: line)
    }

    @MainActor
    private func makeConfiguration(text: String) -> MarkdownEditorTextView.Configuration {
        makeConfiguration(text: text, documentIdentity: PreviewSampleData.cleanDocument.url)
    }

    @MainActor
    private func makeConfiguration(
        text: String,
        showLineNumbers: Bool
    ) -> MarkdownEditorTextView.Configuration {
        makeConfiguration(
            text: text,
            documentIdentity: PreviewSampleData.cleanDocument.url,
            showLineNumbers: showLineNumbers
        )
    }

    @MainActor
    private func makeConfiguration(
        text: String,
        largerHeadingText: Bool
    ) -> MarkdownEditorTextView.Configuration {
        makeConfiguration(
            text: text,
            documentIdentity: PreviewSampleData.cleanDocument.url,
            largerHeadingText: largerHeadingText
        )
    }

    @MainActor
    private func makeConfiguration(
        text: String,
        syntaxMode: MarkdownSyntaxMode
    ) -> MarkdownEditorTextView.Configuration {
        makeConfiguration(
            text: text,
            documentIdentity: PreviewSampleData.cleanDocument.url,
            syntaxMode: syntaxMode
        )
    }

    @MainActor
    private func makeConfiguration(
        text: String,
        tapToToggleTasks: Bool
    ) -> MarkdownEditorTextView.Configuration {
        makeConfiguration(
            text: text,
            documentIdentity: PreviewSampleData.cleanDocument.url,
            tapToToggleTasks: tapToToggleTasks
        )
    }

    @MainActor
    private func makeConfiguration(
        text: String,
        documentIdentity: URL,
        syntaxMode: MarkdownSyntaxMode = .visible,
        showLineNumbers: Bool = false,
        largerHeadingText: Bool = false,
        tapToToggleTasks: Bool = true
    ) -> MarkdownEditorTextView.Configuration {
        MarkdownEditorTextView.Configuration(
            text: text,
            documentIdentity: documentIdentity,
            font: .preferredFont(forTextStyle: .body),
            syntaxMode: syntaxMode,
            showLineNumbers: showLineNumbers,
            largerHeadingText: largerHeadingText,
            tapToToggleTasks: tapToToggleTasks,
            isEditable: true
        )
    }

    @MainActor
    private func makeWrappingMarkdownLines(count: Int) -> String {
        (0..<count)
            .map { index in
                if index.isMultiple(of: 6) {
                    return "# Heading \(index) with enough words to wrap on the narrow test text view"
                }

                return "Plain line \(index) with enough text to keep layout realistic"
            }
            .joined(separator: "\n")
    }

    @MainActor
    private func placeCaret(
        at location: Int,
        screenY: CGFloat,
        in textView: UITextView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> CGFloat {
        textView.selectedRange = NSRange(location: location, length: 0)
        guard let position = textView.position(from: textView.beginningOfDocument, offset: location) else {
            XCTFail("Expected caret position", file: file, line: line)
            return .nan
        }

        textView.layoutManager.ensureLayout(for: textView.textContainer)
        let caretRect = textView.caretRect(for: position)
        textView.contentSize = CGSize(
            width: max(textView.contentSize.width, textView.bounds.width),
            height: max(textView.contentSize.height, caretRect.maxY + textView.bounds.height)
        )
        textView.setContentOffset(CGPoint(x: 0, y: max(0, caretRect.minY - screenY)), animated: false)
        return caretScreenY(in: textView, file: file, line: line)
    }

    @MainActor
    private func caretScreenY(
        in textView: UITextView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> CGFloat {
        let location = textView.selectedRange.location
        guard let position = textView.position(from: textView.beginningOfDocument, offset: location) else {
            XCTFail("Expected caret position", file: file, line: line)
            return .nan
        }

        return textView.caretRect(for: position).minY - textView.contentOffset.y
    }

    @MainActor
    private func pointForCharacterRange(_ range: NSRange, in textView: UITextView) -> CGPoint? {
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        let glyphRange = textView.layoutManager.glyphRange(
            forCharacterRange: range,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else {
            return nil
        }

        let rect = textView.layoutManager.boundingRect(
            forGlyphRange: glyphRange,
            in: textView.textContainer
        )
        return CGPoint(
            x: rect.midX + textView.textContainerInset.left,
            y: rect.midY + textView.textContainerInset.top
        )
    }

    @MainActor
    private func makeEditorSystem() -> (session: AppSession, coordinator: AppCoordinator, viewModel: EditorViewModel) {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.editor(PreviewSampleData.cleanDocument.url)]

        let logger = DebugLogger()
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: logger),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: logger
        )
        let viewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            autosaveDelay: .milliseconds(20)
        )

        return (session, coordinator, viewModel)
    }
}

private final class TrackingUndoTextView: EditorChromeAwareTextView {
    let trackingUndoManager = TrackingUndoManager()
    var simulatedIsFirstResponder = false
    var resignFirstResponderCallCount = 0
    var reloadInputViewsCallCount = 0

    override var undoManager: UndoManager? {
        trackingUndoManager
    }

    override var isFirstResponder: Bool {
        simulatedIsFirstResponder
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        resignFirstResponderCallCount += 1
        simulatedIsFirstResponder = false
        return true
    }

    override func reloadInputViews() {
        reloadInputViewsCallCount += 1
        super.reloadInputViews()
    }
}

private final class FormatterUndoTextView: EditorChromeAwareTextView {
    let formatterUndoManager = UndoManager()

    override var undoManager: UndoManager? {
        formatterUndoManager
    }
}

private final class TrackingUndoManager: UndoManager {
    var simulatedCanUndo = false
    var simulatedCanRedo = false
    var undoCallCount = 0
    var redoCallCount = 0

    override var canUndo: Bool {
        simulatedCanUndo
    }

    override var canRedo: Bool {
        simulatedCanRedo
    }

    override func undo() {
        undoCallCount += 1
        simulatedCanUndo = false
        simulatedCanRedo = true
    }

    override func redo() {
        redoCallCount += 1
        simulatedCanUndo = true
        simulatedCanRedo = false
    }
}

private final class MutableBox<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

private final class AccessoryActionTarget: NSObject {
    @objc func performAction() {}
}

private func makeResolvedTheme(
    keyboardAccessoryUnderlayBackground: UIColor,
    accent: UIColor = .orange
) -> ResolvedEditorTheme {
    ResolvedEditorTheme(
        editorBackground: .black,
        keyboardAccessoryUnderlayBackground: keyboardAccessoryUnderlayBackground,
        accent: accent,
        primaryText: .label,
        secondaryText: .secondaryLabel,
        tertiaryText: .tertiaryLabel,
        headingText: .label,
        emphasisText: .label,
        strikethroughText: .label,
        syntaxMarkerText: .secondaryLabel,
        subtleSyntaxMarkerText: .tertiaryLabel,
        linkText: .link,
        imageAltText: .secondaryLabel,
        inlineCodeText: .label,
        inlineCodeBackground: .secondarySystemFill,
        codeBlockText: .label,
        codeBlockBackground: .secondarySystemFill,
        blockquoteText: .label,
        blockquoteBackground: .secondarySystemFill,
        blockquoteBar: .tertiaryLabel,
        horizontalRuleText: .tertiaryLabel,
        checkboxUnchecked: .systemRed,
        checkboxChecked: .systemGreen
    )
}

private func XCTAssertClear(
    _ color: UIColor?,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let color else {
        return XCTFail("Expected a color", file: file, line: line)
    }

    let resolvedColor = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    XCTAssertEqual(resolvedColor.cgColor.alpha, 0, accuracy: 0.001, file: file, line: line)
}

private func XCTAssertAccessoryToolbarItemsMatchCurrentIdiom(
    _ items: [UIBarButtonItem]?,
    formatItem: UIBarButtonItem?,
    undoItem: UIBarButtonItem?,
    redoItem: UIBarButtonItem?,
    dismissItem: UIBarButtonItem?,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let items else {
        return XCTFail("Expected toolbar items", file: file, line: line)
    }

    XCTAssertTrue(items.first === formatItem, file: file, line: line)

    if UIDevice.current.userInterfaceIdiom == .pad {
        XCTAssertEqual(items.count, 4, file: file, line: line)
        XCTAssertTrue(items[2] === undoItem, file: file, line: line)
        XCTAssertTrue(items[3] === redoItem, file: file, line: line)
        XCTAssertFalse(items.contains { $0 === dismissItem }, file: file, line: line)
    } else {
        XCTAssertEqual(items.count, 6, file: file, line: line)
        XCTAssertTrue(items[2] === undoItem, file: file, line: line)
        XCTAssertTrue(items[3] === redoItem, file: file, line: line)
        XCTAssertTrue(items.last === dismissItem, file: file, line: line)
    }
}

private func XCTAssertSameResolvedColor(
    _ actual: UIColor?,
    _ expected: UIColor,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let actual else {
        return XCTFail("Expected a color", file: file, line: line)
    }

    let lightTraits = UITraitCollection(userInterfaceStyle: .light)
    let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
    XCTAssertEqual(actual.resolvedColor(with: lightTraits), expected.resolvedColor(with: lightTraits), file: file, line: line)
    XCTAssertEqual(actual.resolvedColor(with: darkTraits), expected.resolvedColor(with: darkTraits), file: file, line: line)
}
