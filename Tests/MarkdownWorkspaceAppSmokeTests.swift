import XCTest
@testable import Downward

final class MarkdownWorkspaceAppSmokeTests: XCTestCase {
    @MainActor
    func testPreviewSampleDataConstructsNestedWorkspace() {
        XCTAssertEqual(PreviewSampleData.nestedWorkspace.displayName, "MarkdownWorkspace")
        XCTAssertFalse(PreviewSampleData.nestedWorkspace.rootNodes.isEmpty)
        XCTAssertEqual(PreviewSampleData.cleanDocument.displayName, "Inbox.md")
    }

    @MainActor
    func testContainerBootstrapStartsInNoWorkspaceState() async {
        let container = AppContainer(
            logger: DebugLogger(),
            bookmarkStore: StubBookmarkStore(),
            workspaceManager: LiveWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                securityScopedAccess: SmokeTestSecurityScopedAccessHandler(),
                workspaceEnumerator: StubWorkspaceEnumerator(snapshot: PreviewSampleData.emptyWorkspace)
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: StubErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            lifecycleObserver: LifecycleObserver()
        )

        await container.coordinator.bootstrapIfNeeded()

        XCTAssertEqual(container.session.launchState, .noWorkspaceSelected)
        XCTAssertEqual(container.session.workspaceAccessState, .noneSelected)
        XCTAssertNil(container.session.workspaceSnapshot)
    }

    @MainActor
    func testPreviewContainerInjectsReadyState() {
        let container = AppContainer.preview(
            launchState: .workspaceReady,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            snapshot: PreviewSampleData.nestedWorkspace,
            document: PreviewSampleData.cleanDocument,
            path: [.editor(PreviewSampleData.cleanDocument.url)]
        )

        XCTAssertEqual(container.session.launchState, .workspaceReady)
        XCTAssertEqual(container.session.workspaceSnapshot?.displayName, PreviewSampleData.nestedWorkspace.displayName)
        XCTAssertEqual(container.session.openDocument?.displayName, PreviewSampleData.cleanDocument.displayName)
    }

    @MainActor
    func testDocumentOpenAccessLossTransitionsToReconnectState() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: FailingDocumentManager(
                openError: .workspaceAccessInvalid(displayName: PreviewSampleData.nestedWorkspace.displayName)
            ),
            errorReporter: StubErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.loadDocument(at: PreviewSampleData.cleanDocument.url)

        XCTAssertEqual(session.launchState, .workspaceAccessInvalid)
        XCTAssertNil(session.workspaceSnapshot)
        XCTAssertNil(session.openDocument)
    }

    @MainActor
    func testMissingDocumentDoesNotTriggerWorkspaceReconnect() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: FailingDocumentManager(
                openError: .documentUnavailable(name: PreviewSampleData.cleanDocument.displayName)
            ),
            errorReporter: StubErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.loadDocument(at: PreviewSampleData.cleanDocument.url)

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.editorLoadError?.title, "Document Unavailable")
        XCTAssertNotNil(session.workspaceSnapshot)
    }

    @MainActor
    func testRenameActiveOpenDocumentUpdatesEditorStateAndRoute() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.editor(PreviewSampleData.cleanDocument.url)]

        let renamedURL = PreviewSampleData.workspaceRootURL.appending(path: "Renamed.md")
        let renamedSnapshot = makeWorkspaceSnapshotReplacingRootFile(
            oldURL: PreviewSampleData.cleanDocument.url,
            with: WorkspaceNode.file(
                .init(
                    url: renamedURL,
                    displayName: "Renamed.md",
                    subtitle: "Root document"
                )
            )
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: renamedSnapshot,
                renameOutcome: .renamedFile(
                    oldURL: PreviewSampleData.cleanDocument.url,
                    newURL: renamedURL,
                    displayName: "Renamed.md",
                    relativePath: "Renamed.md"
                )
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: StubErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.renameFile(at: PreviewSampleData.cleanDocument.url, to: "Renamed")

        XCTAssertEqual(session.workspaceSnapshot, renamedSnapshot)
        XCTAssertEqual(session.openDocument?.url, renamedURL)
        XCTAssertEqual(session.openDocument?.relativePath, "Renamed.md")
        XCTAssertEqual(session.openDocument?.displayName, "Renamed.md")
        XCTAssertEqual(session.path, [.editor(renamedURL)])
        XCTAssertEqual(session.openDocument?.text, PreviewSampleData.cleanDocument.text)
    }

    @MainActor
    func testDeleteActiveOpenDocumentClosesEditorAndShowsExplicitMessage() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.editor(PreviewSampleData.cleanDocument.url)]

        let deletedSnapshot = makeWorkspaceSnapshotRemovingRootFile(
            url: PreviewSampleData.cleanDocument.url
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: deletedSnapshot,
                deleteOutcome: .deletedFile(
                    url: PreviewSampleData.cleanDocument.url,
                    displayName: PreviewSampleData.cleanDocument.displayName
                )
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: StubErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.deleteFile(at: PreviewSampleData.cleanDocument.url)

        XCTAssertEqual(session.workspaceSnapshot, deletedSnapshot)
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertEqual(session.lastError?.title, "Document Deleted")
    }

    @MainActor
    func testDeleteDirtyActiveOpenDocumentIsRejectedBeforeMutationRuns() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        var dirtyDocument = PreviewSampleData.cleanDocument
        dirtyDocument.text = "Unsaved edits"
        dirtyDocument.isDirty = true
        dirtyDocument.saveState = .unsaved
        session.openDocument = dirtyDocument
        session.path = [.editor(dirtyDocument.url)]

        let workspaceManager = MutationTestingWorkspaceManager(
            refreshSnapshot: PreviewSampleData.nestedWorkspace
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: workspaceManager,
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: StubErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.deleteFile(at: dirtyDocument.url)

        let deleteCalls = await workspaceManager.deleteCalls

        XCTAssertEqual(deleteCalls, [])
        XCTAssertEqual(session.openDocument?.text, "Unsaved edits")
        XCTAssertEqual(session.path, [.editor(dirtyDocument.url)])
        XCTAssertEqual(session.lastError?.title, "Delete File")
    }

    @MainActor
    private func makeWorkspaceSnapshotReplacingRootFile(
        oldURL: URL,
        with replacement: WorkspaceNode
    ) -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            rootURL: PreviewSampleData.nestedWorkspace.rootURL,
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            rootNodes: PreviewSampleData.nestedWorkspace.rootNodes.map { node in
                node.url == oldURL ? replacement : node
            },
            lastUpdated: PreviewSampleData.previewDate
        )
    }

    @MainActor
    private func makeWorkspaceSnapshotRemovingRootFile(url: URL) -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            rootURL: PreviewSampleData.nestedWorkspace.rootURL,
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            rootNodes: PreviewSampleData.nestedWorkspace.rootNodes.filter { $0.url != url },
            lastUpdated: PreviewSampleData.previewDate
        )
    }
}

private struct SmokeTestSecurityScopedAccessHandler: SecurityScopedAccessHandling {
    func makeBookmark(for url: URL) throws -> Data {
        Data()
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedSecurityScopedURL {
        ResolvedSecurityScopedURL(url: URL(filePath: "/tmp"), displayName: "tmp", isStale: false)
    }

    func validateAccess(to url: URL) throws {}

    func withAccess<Value>(to url: URL, operation: (URL) throws -> Value) throws -> Value {
        try operation(url)
    }

    func withAccess<Value>(
        toDescendantAt relativePath: String,
        within workspaceRootURL: URL,
        operation: (URL) throws -> Value
    ) throws -> Value {
        try operation(
            relativePath
                .split(separator: "/", omittingEmptySubsequences: true)
                .reduce(workspaceRootURL) { partialURL, component in
                    partialURL.appending(path: String(component))
            }
        )
    }
}

private actor FailingDocumentManager: DocumentManager {
    let openError: AppError

    init(openError: AppError) {
        self.openError = openError
    }

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument {
        throw openError
    }

    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument {
        throw openError
    }

    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument {
        throw openError
    }
}

private actor MutationTestingWorkspaceManager: WorkspaceManager {
    let refreshSnapshot: WorkspaceSnapshot
    let renameOutcome: WorkspaceMutationOutcome?
    let deleteOutcome: WorkspaceMutationOutcome?
    private(set) var deleteCalls: [URL] = []

    init(
        refreshSnapshot: WorkspaceSnapshot,
        renameOutcome: WorkspaceMutationOutcome? = nil,
        deleteOutcome: WorkspaceMutationOutcome? = nil
    ) {
        self.refreshSnapshot = refreshSnapshot
        self.renameOutcome = renameOutcome
        self.deleteOutcome = deleteOutcome
    }

    func restoreWorkspace() async -> WorkspaceRestoreResult {
        .ready(refreshSnapshot)
    }

    func selectWorkspace(at url: URL) async -> WorkspaceRestoreResult {
        .ready(refreshSnapshot)
    }

    func refreshCurrentWorkspace() async throws -> WorkspaceSnapshot {
        refreshSnapshot
    }

    func createFile(named proposedName: String, in folderURL: URL?) async throws -> WorkspaceMutationResult {
        WorkspaceMutationResult(
            snapshot: refreshSnapshot,
            outcome: .createdFile(
                url: (folderURL ?? refreshSnapshot.rootURL).appending(path: proposedName),
                displayName: proposedName
            )
        )
    }

    func renameFile(at url: URL, to proposedName: String) async throws -> WorkspaceMutationResult {
        WorkspaceMutationResult(
            snapshot: refreshSnapshot,
            outcome: renameOutcome ?? .renamedFile(
                oldURL: url,
                newURL: url.deletingLastPathComponent().appending(path: proposedName),
                displayName: proposedName,
                relativePath: proposedName
            )
        )
    }

    func deleteFile(at url: URL) async throws -> WorkspaceMutationResult {
        deleteCalls.append(url)
        return WorkspaceMutationResult(
            snapshot: refreshSnapshot,
            outcome: deleteOutcome ?? .deletedFile(url: url, displayName: url.lastPathComponent)
        )
    }

    func clearWorkspaceSelection() async {}
}
