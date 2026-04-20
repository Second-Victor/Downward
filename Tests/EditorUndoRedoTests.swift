import SwiftUI
import UIKit
import XCTest
@testable import Downward

final class EditorUndoRedoTests: XCTestCase {
    @MainActor
    func testUndoRedoRequestsFollowAvailabilityAndDismissTracksFocus() {
        let system = makeEditorSystem()

        XCTAssertFalse(system.viewModel.isEditorFocused)
        XCTAssertFalse(system.viewModel.showsKeyboardToolbar)
        XCTAssertFalse(system.viewModel.canUndo)
        XCTAssertFalse(system.viewModel.canRedo)
        XCTAssertEqual(system.viewModel.undoCommandToken, 0)
        XCTAssertEqual(system.viewModel.redoCommandToken, 0)
        XCTAssertEqual(system.viewModel.dismissKeyboardCommandToken, 0)

        system.viewModel.handleEditorFocusChange(true)
        system.viewModel.updateUndoRedoAvailability(canUndo: true, canRedo: false)

        XCTAssertTrue(system.viewModel.isEditorFocused)
        XCTAssertTrue(system.viewModel.showsKeyboardToolbar)
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
        XCTAssertFalse(system.viewModel.showsKeyboardToolbar)
        XCTAssertFalse(system.viewModel.canUndo)
        XCTAssertFalse(system.viewModel.canRedo)
    }

    @MainActor
    func testCoordinatorExecutesPendingUndoCommand() {
        var text = "Draft"
        var topOverlayClearance: CGFloat = 0
        let textBinding = Binding(
            get: { text },
            set: { text = $0 }
        )
        let topOverlayBinding = Binding(
            get: { topOverlayClearance },
            set: { topOverlayClearance = $0 }
        )
        var focusEvents: [Bool] = []
        var availabilityEvents: [(Bool, Bool)] = []
        let coordinator = MarkdownEditorTextView.Coordinator(
            text: textBinding,
            topOverlayClearance: topOverlayBinding,
            onEditorFocusChange: { focusEvents.append($0) },
            onUndoRedoAvailabilityChange: { canUndo, canRedo in
                availabilityEvents.append((canUndo, canRedo))
            }
        )
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let configuration = MarkdownEditorTextView.Configuration(
            text: text,
            documentIdentity: PreviewSampleData.cleanDocument.url,
            font: .preferredFont(forTextStyle: .body),
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
        var text = "Draft"
        var topOverlayClearance: CGFloat = 0
        let textBinding = Binding(
            get: { text },
            set: { text = $0 }
        )
        let topOverlayBinding = Binding(
            get: { topOverlayClearance },
            set: { topOverlayClearance = $0 }
        )
        let coordinator = MarkdownEditorTextView.Coordinator(
            text: textBinding,
            topOverlayClearance: topOverlayBinding,
            onEditorFocusChange: { _ in },
            onUndoRedoAvailabilityChange: { _, _ in }
        )
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let configuration = MarkdownEditorTextView.Configuration(
            text: text,
            documentIdentity: PreviewSampleData.cleanDocument.url,
            font: .preferredFont(forTextStyle: .body),
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
        var text = "Draft"
        var topOverlayClearance: CGFloat = 0
        let textBinding = Binding(
            get: { text },
            set: { text = $0 }
        )
        let topOverlayBinding = Binding(
            get: { topOverlayClearance },
            set: { topOverlayClearance = $0 }
        )
        let coordinator = MarkdownEditorTextView.Coordinator(
            text: textBinding,
            topOverlayClearance: topOverlayBinding,
            onEditorFocusChange: { _ in },
            onUndoRedoAvailabilityChange: { _, _ in }
        )
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let configuration = MarkdownEditorTextView.Configuration(
            text: text,
            documentIdentity: PreviewSampleData.cleanDocument.url,
            font: .preferredFont(forTextStyle: .body),
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
        var text = "Draft"
        var topOverlayClearance: CGFloat = 0
        let textBinding = Binding(
            get: { text },
            set: { text = $0 }
        )
        let topOverlayBinding = Binding(
            get: { topOverlayClearance },
            set: { topOverlayClearance = $0 }
        )
        let coordinator = MarkdownEditorTextView.Coordinator(
            text: textBinding,
            topOverlayClearance: topOverlayBinding,
            onEditorFocusChange: { _ in },
            onUndoRedoAvailabilityChange: { _, _ in }
        )
        let textView = TrackingUndoTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        textView.simulatedIsFirstResponder = true
        textView.trackingUndoManager.simulatedCanUndo = true
        textView.trackingUndoManager.simulatedCanRedo = false
        let configuration = MarkdownEditorTextView.Configuration(
            text: text,
            documentIdentity: PreviewSampleData.cleanDocument.url,
            font: .preferredFont(forTextStyle: .body),
            syntaxMode: .visible,
            isEditable: true
        )

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
