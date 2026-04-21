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
        let topOverlayBox = MutableBox<CGFloat>(0)
        let coordinator = makeCoordinator(text: textBox, topOverlayClearance: topOverlayBox)
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
    func testKeyboardOverlapUpdatesBottomInsetsLikePrototype() {
        let textBox = MutableBox("Draft")
        let topOverlayBox = MutableBox<CGFloat>(0)
        let coordinator = makeCoordinator(text: textBox, topOverlayClearance: topOverlayBox)
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
        let topOverlayBox = MutableBox<CGFloat>(0)
        let coordinator = makeCoordinator(text: textBox, topOverlayClearance: topOverlayBox)
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
    func testTopViewportUpdatesDoNotRewriteBottomKeyboardInsets() {
        let textBox = MutableBox("Draft")
        let topOverlayBox = MutableBox<CGFloat>(0)
        let coordinator = makeCoordinator(text: textBox, topOverlayClearance: topOverlayBox)
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

        coordinator.updateTopViewportInsets(for: textView)

        XCTAssertEqual(textView.contentInset.bottom, originalBottomInset, accuracy: 0.5)
        XCTAssertEqual(textView.verticalScrollIndicatorInsets.bottom, originalIndicatorBottomInset, accuracy: 0.5)
    }

    @MainActor
    func testAccessoryLayoutDoesNotRewriteBottomKeyboardInsets() {
        let textBox = MutableBox("Draft")
        let topOverlayBox = MutableBox<CGFloat>(0)
        let coordinator = makeCoordinator(text: textBox, topOverlayClearance: topOverlayBox)
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
        let accessoryView = KeyboardAccessoryToolbarView(
            target: actionTarget,
            undoAction: #selector(AccessoryActionTarget.performAction),
            redoAction: #selector(AccessoryActionTarget.performAction),
            dismissAction: #selector(AccessoryActionTarget.performAction)
        )

        let fittedSize = accessoryView.sizeThatFits(CGSize(width: 320, height: UIView.noIntrinsicMetric))

        XCTAssertGreaterThan(fittedSize.height, 0)
        XCTAssertClear(accessoryView.backgroundColor)
        XCTAssertGreaterThan(accessoryView.intrinsicContentSize.height, 0)
    }

    @MainActor
    func testCoordinatorExecutesPendingUndoCommand() {
        let textBox = MutableBox("Draft")
        let topOverlayBox = MutableBox<CGFloat>(0)
        var focusEvents: [Bool] = []
        var availabilityEvents: [(Bool, Bool)] = []
        let coordinator = MarkdownEditorTextView.Coordinator(
            text: Binding(
                get: { textBox.value },
                set: { textBox.value = $0 }
            ),
            topOverlayClearance: Binding(
                get: { topOverlayBox.value },
                set: { topOverlayBox.value = $0 }
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
        let topOverlayBox = MutableBox<CGFloat>(0)
        let coordinator = makeCoordinator(text: textBox, topOverlayClearance: topOverlayBox)
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
        let topOverlayBox = MutableBox<CGFloat>(0)
        let coordinator = makeCoordinator(text: textBox, topOverlayClearance: topOverlayBox)
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
        let topOverlayBox = MutableBox<CGFloat>(0)
        let coordinator = makeCoordinator(text: textBox, topOverlayClearance: topOverlayBox)
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        textView.simulatedIsFirstResponder = true
        textView.trackingUndoManager.simulatedCanUndo = true
        textView.trackingUndoManager.simulatedCanRedo = false
        let configuration = makeConfiguration(text: textBox.value)

        coordinator.configureKeyboardAccessory(for: textView)
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
    private func makeCoordinator(
        text: MutableBox<String>,
        topOverlayClearance: MutableBox<CGFloat>
    ) -> MarkdownEditorTextView.Coordinator {
        let textBinding = Binding(
            get: { text.value },
            set: { text.value = $0 }
        )
        let topOverlayBinding = Binding(
            get: { topOverlayClearance.value },
            set: { topOverlayClearance.value = $0 }
        )
        return MarkdownEditorTextView.Coordinator(
            text: textBinding,
            topOverlayClearance: topOverlayBinding,
            onEditorFocusChange: { _ in },
            onUndoRedoAvailabilityChange: { _, _ in }
        )
    }

    @MainActor
    private func makeConfiguration(text: String) -> MarkdownEditorTextView.Configuration {
        MarkdownEditorTextView.Configuration(
            text: text,
            documentIdentity: PreviewSampleData.cleanDocument.url,
            font: .preferredFont(forTextStyle: .body),
            syntaxMode: .visible,
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
