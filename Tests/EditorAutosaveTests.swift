import Foundation
import XCTest
@testable import Downward

final class EditorAutosaveTests: XCTestCase {
    @MainActor
    func testAutosaveDebounceOnlySavesLatestSnapshot() async throws {
        let documentManager = RecordingDocumentManager(saveDelay: .milliseconds(10))
        let system = makeEditorSystem(documentManager: documentManager)

        system.viewModel.handleTextChange("First draft")
        try await Task.sleep(for: .milliseconds(20))
        system.viewModel.handleTextChange("Second draft")
        try await Task.sleep(for: .milliseconds(140))

        let savedTexts = await documentManager.savedTexts

        XCTAssertEqual(savedTexts, ["Second draft"])
        XCTAssertEqual(system.session.openDocument?.text, "Second draft")
        XCTAssertFalse(system.viewModel.showsUnsavedIndicator)
    }

    @MainActor
    func testSaveOrderingRemainsSerializedWhenEditArrivesDuringSave() async throws {
        let documentManager = RecordingDocumentManager(saveDelay: .milliseconds(120))
        let system = makeEditorSystem(
            documentManager: documentManager,
            autosaveDelay: .milliseconds(20)
        )

        system.viewModel.handleTextChange("First revision")
        try await Task.sleep(for: .milliseconds(40))
        system.viewModel.handleTextChange("Second revision")
        try await Task.sleep(for: .milliseconds(320))

        let savedTexts = await documentManager.savedTexts

        XCTAssertEqual(savedTexts, ["First revision", "Second revision"])
        XCTAssertEqual(system.session.openDocument?.text, "Second revision")
        XCTAssertFalse(system.session.openDocument?.isDirty ?? true)
    }

    @MainActor
    func testRedDotTransitionsFromUnsavedToSavingToSaved() async throws {
        let documentManager = RecordingDocumentManager(saveDelay: .milliseconds(90))
        let system = makeEditorSystem(
            documentManager: documentManager,
            autosaveDelay: .milliseconds(20)
        )

        XCTAssertFalse(system.viewModel.showsUnsavedIndicator)

        system.viewModel.handleTextChange("Edited text")
        XCTAssertTrue(system.viewModel.showsUnsavedIndicator)
        XCTAssertFalse(system.viewModel.showsSaveStatusIndicator)
        XCTAssertEqual(system.session.openDocument?.saveState, .unsaved)

        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(system.session.openDocument?.saveState, .saving)
        XCTAssertTrue(system.viewModel.showsUnsavedIndicator)
        XCTAssertFalse(system.viewModel.showsSaveStatusIndicator)

        try await Task.sleep(for: .milliseconds(120))
        guard case .saved = system.session.openDocument?.saveState else {
            return XCTFail("Expected save state to become saved after autosave succeeds.")
        }
        XCTAssertFalse(system.viewModel.showsUnsavedIndicator)
    }

    @MainActor
    func testSaveFailureKeepsRedDotVisible() async throws {
        let documentManager = RecordingDocumentManager(
            saveDelay: .milliseconds(20),
            failureSequence: [
                AppError.documentSaveFailed(name: "Inbox.md", details: "Disk write failed.")
            ]
        )
        let system = makeEditorSystem(
            documentManager: documentManager,
            autosaveDelay: .milliseconds(20)
        )

        system.viewModel.handleTextChange("Broken save")
        try await Task.sleep(for: .milliseconds(80))

        guard case .failed = system.session.openDocument?.saveState else {
            return XCTFail("Expected save state to become failed when autosave throws.")
        }
        XCTAssertTrue(system.session.openDocument?.isDirty ?? false)
        XCTAssertTrue(system.viewModel.showsUnsavedIndicator)
        XCTAssertTrue(system.viewModel.showsSaveStatusIndicator)
    }

    @MainActor
    func testDisappearFlushesPendingDirtyDocumentImmediately() async throws {
        let documentManager = RecordingDocumentManager(saveDelay: .milliseconds(10))
        let system = makeEditorSystem(
            documentManager: documentManager,
            autosaveDelay: .seconds(5)
        )

        system.viewModel.handleTextChange("Disappear flush")
        system.viewModel.handleDisappear(for: PreviewSampleData.cleanDocument.url)
        try await Task.sleep(for: .milliseconds(40))

        let savedTexts = await documentManager.savedTexts

        XCTAssertEqual(savedTexts, ["Disappear flush"])
        XCTAssertFalse(system.session.openDocument?.isDirty ?? true)
    }

    @MainActor
    private func makeEditorSystem(
        documentManager: any DocumentManager,
        autosaveDelay: Duration = .milliseconds(40)
    ) -> (session: AppSession, viewModel: EditorViewModel) {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument

        let logger = DebugLogger()
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: documentManager,
            errorReporter: StubErrorReporter(logger: logger),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: logger
        )

        let viewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            autosaveDelay: autosaveDelay
        )
        viewModel.handleAppear(for: PreviewSampleData.cleanDocument.url)

        return (session, viewModel)
    }
}

private actor RecordingDocumentManager: DocumentManager {
    let saveDelay: Duration
    private var failureSequence: [AppError]
    private var conflictSequence: [OpenDocument]
    private(set) var savedTexts: [String] = []

    init(
        saveDelay: Duration,
        failureSequence: [AppError] = [],
        conflictSequence: [OpenDocument] = []
    ) {
        self.saveDelay = saveDelay
        self.failureSequence = failureSequence
        self.conflictSequence = conflictSequence
    }

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument {
        throw AppError.documentUnavailable(name: url.lastPathComponent)
    }

    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument {
        document
    }

    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument {
        try? await Task.sleep(for: saveDelay)
        savedTexts.append(document.text)

        if failureSequence.isEmpty == false {
            throw failureSequence.removeFirst()
        }

        if overwriteConflict == false, conflictSequence.isEmpty == false {
            return conflictSequence.removeFirst()
        }

        var savedDocument = document
        savedDocument.isDirty = false
        savedDocument.saveState = .saved(Date(timeIntervalSince1970: 1_710_000_100))
        savedDocument.conflictState = .none
        return savedDocument
    }
}
