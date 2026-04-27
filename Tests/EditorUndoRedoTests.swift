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
        XCTAssertEqual(accessoryView.toolbar.items?.count, 4)
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
        XCTAssertTrue(textView.dismissAccessoryItem?.isEnabled ?? false)
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
            horizontalRuleText: .systemGray
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
            horizontalRuleText: .systemGray
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
        XCTAssertEqual(textView.keyboardAccessoryToolbarView?.toolbar.items?.count, 4)
        XCTAssertEqual(textView.undoAccessoryItem?.isEnabled, true)
        XCTAssertEqual(textView.redoAccessoryItem?.isEnabled, false)
        XCTAssertEqual(textView.dismissAccessoryItem?.isEnabled, true)
        XCTAssertEqual(textView.reloadInputViewsCallCount, 1)
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
    func testCoordinatorDefersFullMarkdownRerenderAfterLineBreakEdit() async {
        let textBox = MutableBox("Draft")
        let coordinator = makeCoordinator(text: textBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
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
        text: MutableBox<String>
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
        documentIdentity: URL,
        showLineNumbers: Bool = false,
        largerHeadingText: Bool = false
    ) -> MarkdownEditorTextView.Configuration {
        MarkdownEditorTextView.Configuration(
            text: text,
            documentIdentity: documentIdentity,
            font: .preferredFont(forTextStyle: .body),
            syntaxMode: .visible,
            showLineNumbers: showLineNumbers,
            largerHeadingText: largerHeadingText,
            isEditable: true
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
        horizontalRuleText: .tertiaryLabel
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
