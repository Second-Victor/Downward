import Foundation
import XCTest
@testable import Downward

final class EditorConflictTests: XCTestCase {
    @MainActor
    func testAutosavePresentsConflictResolutionWhenDiskVersionChanged() async throws {
        let conflictedDocument = makeConflictedDocument()
        let documentManager = ConflictResolvingDocumentManager(
            conflictedSaveResult: conflictedDocument,
            reloadedDocument: PreviewSampleData.cleanDocument
        )
        let system = makeEditorSystem(documentManager: documentManager)

        system.viewModel.handleTextChange("Local edits")
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertTrue(system.viewModel.isShowingConflictResolution)
        XCTAssertEqual(system.session.openDocument?.conflictState, conflictedDocument.conflictState)
        XCTAssertTrue(system.session.openDocument?.isDirty ?? false)
    }

    @MainActor
    func testPreservingConflictEditsKeepsEditorOpenAndBackRequiresResolution() async throws {
        let conflictedDocument = makeConflictedDocument()
        let documentManager = ConflictResolvingDocumentManager(
            conflictedSaveResult: conflictedDocument,
            reloadedDocument: PreviewSampleData.cleanDocument
        )
        let system = makeEditorSystem(documentManager: documentManager)

        system.viewModel.handleTextChange("Local edits")
        try await Task.sleep(for: .milliseconds(80))
        system.viewModel.preserveConflictEdits()

        guard case .preservingEdits = system.session.openDocument?.conflictState else {
            return XCTFail("Expected preserved edits state after deferring the conflict.")
        }

        system.viewModel.handleDisappear(for: PreviewSampleData.cleanDocument.url)
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(system.session.lastError, conflictedDocument.conflictState.activeConflict?.error)
        XCTAssertNotNil(system.session.openDocument)
    }

    @MainActor
    func testConflictAfterDisappearSurfacesBrowserAlertAndPreservesDocumentState() async throws {
        let conflictedDocument = makeConflictedDocument()
        let documentManager = ConflictResolvingDocumentManager(
            conflictedSaveResult: conflictedDocument,
            reloadedDocument: PreviewSampleData.cleanDocument
        )
        let system = makeEditorSystem(documentManager: documentManager)

        system.viewModel.handleTextChange("Local edits")
        system.viewModel.handleDisappear(for: PreviewSampleData.cleanDocument.url)
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(system.session.lastError, conflictedDocument.conflictState.activeConflict?.error)
        XCTAssertEqual(system.session.openDocument?.conflictState, conflictedDocument.conflictState)
    }

    @MainActor
    func testReloadResolutionReplacesCurrentDocument() async throws {
        let conflictedDocument = makeConflictedDocument()
        let reloadedDocument = PreviewSampleData.cleanDocument
        let documentManager = ConflictResolvingDocumentManager(
            conflictedSaveResult: conflictedDocument,
            reloadedDocument: reloadedDocument
        )
        let system = makeEditorSystem(documentManager: documentManager)

        system.viewModel.handleTextChange("Local edits")
        try await Task.sleep(for: .milliseconds(80))
        system.viewModel.reloadFromDisk()
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(system.session.openDocument, reloadedDocument)
        XCTAssertFalse(system.viewModel.isShowingConflictResolution)
    }

    @MainActor
    func testObservationStopsRevalidatingAfterEditorDisappears() async throws {
        let documentManager = ObservationRecordingDocumentManager(document: PreviewSampleData.cleanDocument)
        let system = makeEditorSystem(documentManager: documentManager)

        try await waitUntil {
            await documentManager.isObserving
        }

        await documentManager.emitObservedChange()
        try await waitUntil {
            await documentManager.revalidateCallCount == 1
        }

        system.viewModel.handleDisappear(for: PreviewSampleData.cleanDocument.url)

        try await waitUntil {
            await documentManager.isObserving == false
        }

        await documentManager.emitObservedChange()
        try await Task.sleep(for: .milliseconds(40))
        let revalidateCallCount = await documentManager.revalidateCallCount
        XCTAssertEqual(revalidateCallCount, 1)
    }

    @MainActor
    private func makeEditorSystem(
        documentManager: any DocumentManager,
        autosaveDelay: Duration = .milliseconds(20)
    ) -> (session: AppSession, viewModel: EditorViewModel) {
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
            documentManager: documentManager,
            errorReporter: DefaultErrorReporter(logger: logger),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: logger
        )

        let viewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            autosaveDelay: autosaveDelay
        )
        viewModel.handleAppear(for: PreviewSampleData.cleanDocument.url)

        return (session, viewModel)
    }

    @MainActor
    private func makeConflictedDocument() -> OpenDocument {
        var document = PreviewSampleData.cleanDocument
        document.text = "Locally edited text"
        document.isDirty = true
        document.saveState = .unsaved
        document.conflictState = .needsResolution(
            DocumentConflict(
                kind: .modifiedOnDisk,
                error: PreviewSampleData.conflictError
            )
        )
        return document
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .milliseconds(200),
        pollInterval: Duration = .milliseconds(10),
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            if await condition() {
                return
            }

            try await Task.sleep(for: pollInterval)
        }

        XCTFail("Timed out waiting for condition.")
    }
}

private actor ConflictResolvingDocumentManager: DocumentManager {
    let conflictedSaveResult: OpenDocument
    let reloadedDocument: OpenDocument

    init(conflictedSaveResult: OpenDocument, reloadedDocument: OpenDocument) {
        self.conflictedSaveResult = conflictedSaveResult
        self.reloadedDocument = reloadedDocument
    }

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument {
        reloadedDocument
    }

    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument {
        reloadedDocument
    }

    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument {
        reloadedDocument
    }

    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument {
        if overwriteConflict {
            var savedDocument = document
            savedDocument.isDirty = false
            savedDocument.saveState = .saved(Date(timeIntervalSince1970: 1_710_000_200))
            savedDocument.conflictState = .none
            return savedDocument
        }

        return conflictedSaveResult
    }

    func observeDocumentChanges(for document: OpenDocument) async throws -> AsyncStream<Void> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func relocateDocumentSession(
        for document: OpenDocument,
        to url: URL,
        relativePath: String
    ) async {}
}

private actor ObservationRecordingDocumentManager: DocumentManager {
    let document: OpenDocument
    private var continuation: AsyncStream<Void>.Continuation?

    private(set) var revalidateCallCount = 0
    private(set) var isObserving = false

    init(document: OpenDocument) {
        self.document = document
    }

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument {
        document
    }

    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument {
        document
    }

    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument {
        revalidateCallCount += 1
        return document
    }

    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument {
        document
    }

    func observeDocumentChanges(for document: OpenDocument) async throws -> AsyncStream<Void> {
        AsyncStream { continuation in
            self.continuation = continuation
            isObserving = true
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.stopObserving()
                }
            }
        }
    }

    func relocateDocumentSession(
        for document: OpenDocument,
        to url: URL,
        relativePath: String
    ) async {}

    func emitObservedChange() {
        continuation?.yield(())
    }

    private func stopObserving() {
        continuation = nil
        isObserving = false
    }
}
