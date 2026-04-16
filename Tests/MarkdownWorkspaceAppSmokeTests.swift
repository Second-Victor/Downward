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
            recentFilesStore: RecentFilesStore(initialItems: []),
            editorAppearanceStore: EditorAppearanceStore(),
            workspaceManager: LiveWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                securityScopedAccess: SmokeTestSecurityScopedAccessHandler(),
                workspaceEnumerator: StubWorkspaceEnumerator(snapshot: PreviewSampleData.emptyWorkspace)
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            lifecycleObserver: LifecycleObserver()
        )

        await container.coordinator.bootstrapIfNeeded()

        XCTAssertEqual(container.session.launchState, RootLaunchState.noWorkspaceSelected)
        XCTAssertEqual(container.session.workspaceAccessState, WorkspaceAccessState.noneSelected)
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
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        let result = await coordinator.loadDocument(at: PreviewSampleData.cleanDocument.url)

        XCTAssertEqual(session.launchState, .workspaceAccessInvalid)
        XCTAssertNil(session.workspaceSnapshot)
        XCTAssertNil(session.openDocument)
        guard case let .failure(error) = result else {
            return XCTFail("Expected workspace reconnect failure.")
        }
        XCTAssertEqual(error.title, "Workspace Needs Reconnect")
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
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        let result = await coordinator.loadDocument(at: PreviewSampleData.cleanDocument.url)

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertNotNil(session.workspaceSnapshot)
        XCTAssertNil(session.editorLoadError)
        guard case let .failure(error) = result else {
            return XCTFail("Expected missing-document failure.")
        }
        XCTAssertEqual(error.title, "Document Unavailable")
    }

    @MainActor
    func testLateFirstDocumentLoadDoesNotOverwriteCurrentSelection() async throws {
        let firstDocument = PreviewSampleData.cleanDocument
        var secondDocument = PreviewSampleData.dirtyDocument
        secondDocument.isDirty = false
        secondDocument.saveState = .idle
        secondDocument.conflictState = .none

        let sessionStore = StubSessionStore()
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.path = [.editor(firstDocument.url)]
        let documentManager = DelayedOpenDocumentManager(
            documents: [
                firstDocument.url: firstDocument,
                secondDocument.url: secondDocument,
            ],
            openDelays: [
                firstDocument.url: .milliseconds(180),
                secondDocument.url: .milliseconds(20),
            ]
        )

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: documentManager,
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let viewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            autosaveDelay: .milliseconds(20)
        )

        viewModel.handleAppear(for: firstDocument.url)
        try await Task.sleep(for: .milliseconds(30))
        session.path = [.editor(secondDocument.url)]
        viewModel.handleAppear(for: secondDocument.url)
        viewModel.handleDisappear(for: firstDocument.url)

        try await waitUntil {
            session.openDocument?.url == secondDocument.url
        }
        try await Task.sleep(for: .milliseconds(220))
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()
        let observedURLs = await documentManager.observedURLs

        XCTAssertEqual(session.openDocument?.url, secondDocument.url)
        XCTAssertEqual(session.openDocument?.displayName, secondDocument.displayName)
        XCTAssertEqual(session.path, [.editor(secondDocument.url)])
        XCTAssertNil(session.editorLoadError)
        XCTAssertNil(session.lastError)
        XCTAssertEqual(restoredSession?.relativePath, secondDocument.relativePath)
        XCTAssertEqual(observedURLs, [secondDocument.url])
    }

    @MainActor
    func testNavigatingAwayBeforeDelayedLoadCompletesDoesNotReopenDocumentOrObservation() async throws {
        let sessionStore = StubSessionStore()
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.path = [.editor(PreviewSampleData.cleanDocument.url)]
        let documentManager = DelayedOpenDocumentManager(
            documents: [
                PreviewSampleData.cleanDocument.url: PreviewSampleData.cleanDocument,
            ],
            openDelays: [
                PreviewSampleData.cleanDocument.url: .milliseconds(180),
            ]
        )

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: documentManager,
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let viewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            autosaveDelay: .milliseconds(20)
        )

        viewModel.handleAppear(for: PreviewSampleData.cleanDocument.url)
        try await Task.sleep(for: .milliseconds(30))
        session.path = []
        viewModel.handleDisappear(for: PreviewSampleData.cleanDocument.url)
        try await Task.sleep(for: .milliseconds(220))

        let restoredSession = try await sessionStore.loadRestorableDocumentSession()
        let observedURLs = await documentManager.observedURLs

        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.editorLoadError)
        XCTAssertNil(session.lastError)
        XCTAssertTrue(observedURLs.isEmpty)
        XCTAssertNil(restoredSession)
    }

    @MainActor
    func testRefreshWorkspaceRemovesStaleEditorRouteWhenCleanSelectedFileDisappears() async throws {
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: PreviewSampleData.cleanDocument.relativePath)
        )
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.editor(PreviewSampleData.cleanDocument.url)]

        let refreshedSnapshot = makeWorkspaceSnapshotRemovingRootFile(
            url: PreviewSampleData.cleanDocument.url
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: refreshedSnapshot
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        let result = await coordinator.refreshWorkspace()
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        guard case let .success(snapshot)? = result else {
            return XCTFail("Expected successful refresh.")
        }

        XCTAssertEqual(snapshot, refreshedSnapshot)
        XCTAssertEqual(session.workspaceSnapshot, refreshedSnapshot)
        XCTAssertNil(session.openDocument)
        XCTAssertNil(session.editorLoadError)
        XCTAssertEqual(session.path, [])
        XCTAssertEqual(session.lastError?.title, "Document Unavailable")
        XCTAssertNil(restoredSession)
    }

    @MainActor
    func testRefreshWorkspaceTrimsMissingNestedFolderRoute() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.path = [.folder(PreviewSampleData.year2026URL)]

        let refreshedSnapshot = WorkspaceSnapshot(
            rootURL: PreviewSampleData.nestedWorkspace.rootURL,
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            rootNodes: [
                .file(
                    .init(
                        url: PreviewSampleData.cleanDocument.url,
                        displayName: PreviewSampleData.cleanDocument.displayName,
                        subtitle: "Root document"
                    )
                ),
            ],
            lastUpdated: PreviewSampleData.previewDate
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: refreshedSnapshot
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.refreshWorkspace()

        XCTAssertEqual(session.workspaceSnapshot, refreshedSnapshot)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.lastError)
    }

    @MainActor
    func testForegroundRevalidationDoesNotOverwriteNewSelection() async throws {
        let originalDocument = PreviewSampleData.cleanDocument
        var revalidatedOriginalDocument = PreviewSampleData.cleanDocument
        revalidatedOriginalDocument.text = "# Refreshed\n\nOld selection should not reattach."

        var replacementDocument = PreviewSampleData.dirtyDocument
        replacementDocument.isDirty = false
        replacementDocument.saveState = .idle
        replacementDocument.conflictState = .none

        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = originalDocument
        session.path = [.editor(originalDocument.url)]

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: DelayedRevalidationDocumentManager(
                revalidatedDocument: revalidatedOriginalDocument,
                revalidationDelay: .milliseconds(150)
            ),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        let foregroundTask = Task {
            await coordinator.handleSceneDidBecomeActive()
        }

        try await Task.sleep(for: .milliseconds(30))
        session.openDocument = replacementDocument
        session.path = [.editor(replacementDocument.url)]

        await foregroundTask.value

        XCTAssertEqual(session.openDocument?.url, replacementDocument.url)
        XCTAssertEqual(session.openDocument?.text, replacementDocument.text)
        XCTAssertEqual(session.path, [.editor(replacementDocument.url)])
        XCTAssertNil(session.lastError)
    }

    @MainActor
    func testBootstrapRestoresLastOpenDocumentWhenWorkspaceRestoreSucceeds() async throws {
        let session = AppSession()
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace,
                forcedRestoreResult: .ready(PreviewSampleData.nestedWorkspace)
            ),
            documentManager: RestorationDocumentManager(
                openedDocument: PreviewSampleData.cleanDocument
            ),
            sessionStore: StubSessionStore(
                initialSession: RestorableDocumentSession(relativePath: "Inbox.md")
            ),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.bootstrapIfNeeded()

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertEqual(session.openDocument, PreviewSampleData.cleanDocument)
        XCTAssertEqual(session.path, [.editor(PreviewSampleData.cleanDocument.url)])
        XCTAssertNil(session.lastError)
    }

    @MainActor
    func testBootstrapWithMissingLastFileKeepsWorkspaceReadyWithoutReconnect() async throws {
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: "Missing.md")
        )
        let session = AppSession()
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace,
                forcedRestoreResult: .ready(PreviewSampleData.nestedWorkspace)
            ),
            documentManager: FailingDocumentManager(
                openError: .documentUnavailable(name: "Missing.md")
            ),
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.bootstrapIfNeeded()

        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.lastError)
        XCTAssertNil(restoredSession)
    }

    @MainActor
    func testBootstrapWithRenamedLastFileKeepsWorkspaceReadyAndClearsStaleRestoreTarget() async throws {
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: "Journal/2026/OldName.md")
        )
        let session = AppSession()
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace,
                forcedRestoreResult: .ready(PreviewSampleData.nestedWorkspace)
            ),
            documentManager: FailingDocumentManager(
                openError: .documentUnavailable(name: "OldName.md")
            ),
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.bootstrapIfNeeded()
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.lastError)
        XCTAssertNil(restoredSession)
    }

    @MainActor
    func testBootstrapWithUnreadableLastFileKeepsWorkspaceReadyAndClearsStaleRestoreTarget() async throws {
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: "Broken.md")
        )
        let session = AppSession()
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace,
                forcedRestoreResult: .ready(PreviewSampleData.nestedWorkspace)
            ),
            documentManager: FailingDocumentManager(
                openError: .documentOpenFailed(
                    name: "Broken.md",
                    details: "The file is not valid UTF-8 text."
                )
            ),
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.bootstrapIfNeeded()
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.lastError)
        XCTAssertNil(restoredSession)
    }

    @MainActor
    func testBootstrapInvalidWorkspaceRestoreClearsStaleEditorRouteAndShowsReconnectState() async throws {
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: PreviewSampleData.cleanDocument.relativePath)
        )
        let session = AppSession()
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.editor(PreviewSampleData.cleanDocument.url)]

        let reconnectError = UserFacingError(
            title: "Workspace Needs Reconnect",
            message: "The previous folder reference is stale.",
            recoverySuggestion: "Choose the folder again or clear the stored workspace."
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace,
                forcedRestoreResult: .accessInvalid(
                    .invalid(
                        displayName: PreviewSampleData.nestedWorkspace.displayName,
                        error: reconnectError
                    )
                )
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.bootstrapIfNeeded()
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.launchState, .workspaceAccessInvalid)
        XCTAssertEqual(
            session.workspaceAccessState,
            .invalid(
                displayName: PreviewSampleData.nestedWorkspace.displayName,
                error: reconnectError
            )
        )
        XCTAssertNil(session.workspaceSnapshot)
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertEqual(session.lastError, reconnectError)
        XCTAssertEqual(restoredSession?.relativePath, PreviewSampleData.cleanDocument.relativePath)
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
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
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
    func testRenameDirtyNestedOpenDocumentPreservesUnsavedEditsUpdatesRestoreStateAndSavesToNewPath() async throws {
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: PreviewSampleData.dirtyDocument.relativePath)
        )
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace

        var openDocument = PreviewSampleData.dirtyDocument
        openDocument.text = "# Monday\n\nUnsaved edits stay with the renamed file."
        openDocument.isDirty = true
        openDocument.saveState = .unsaved
        session.openDocument = openDocument
        session.path = [.folder(PreviewSampleData.year2026URL), .editor(openDocument.url)]

        let renamedURL = PreviewSampleData.year2026URL.appending(path: "2026-04-13 Renamed.md")
        let renamedRelativePath = "Journal/2026/2026-04-13 Renamed.md"
        let renamedSnapshot = makeWorkspaceSnapshotReplacingFile(
            oldURL: openDocument.url,
            with: .file(
                .init(
                    url: renamedURL,
                    displayName: "2026-04-13 Renamed.md",
                    subtitle: "Daily note"
                )
            )
        )
        let documentManager = MutationTrackingDocumentManager()
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: renamedSnapshot,
                renameOutcome: .renamedFile(
                    oldURL: openDocument.url,
                    newURL: renamedURL,
                    displayName: "2026-04-13 Renamed.md",
                    relativePath: renamedRelativePath
                )
            ),
            documentManager: documentManager,
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: RecentFilesStore(initialItems: [])
        )

        _ = await coordinator.renameFile(at: openDocument.url, to: "2026-04-13 Renamed")
        let renamedDocument = try XCTUnwrap(session.openDocument)
        let restorableSessionAfterRename = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.workspaceSnapshot, renamedSnapshot)
        XCTAssertEqual(session.path, [.folder(PreviewSampleData.year2026URL), .editor(renamedURL)])
        XCTAssertEqual(renamedDocument.url, renamedURL)
        XCTAssertEqual(renamedDocument.relativePath, renamedRelativePath)
        XCTAssertEqual(renamedDocument.displayName, "2026-04-13 Renamed.md")
        XCTAssertEqual(renamedDocument.text, "# Monday\n\nUnsaved edits stay with the renamed file.")
        XCTAssertTrue(renamedDocument.isDirty)
        XCTAssertEqual(renamedDocument.saveState, .unsaved)
        XCTAssertEqual(restorableSessionAfterRename?.relativePath, renamedRelativePath)
        XCTAssertTrue(
            workspaceViewModel.isSelected(
                .file(
                    .init(
                        url: URL(filePath: "\(PreviewSampleData.workspaceRootURL.path)/Journal/2026/../2026/2026-04-13 Renamed.md"),
                        displayName: "2026-04-13 Renamed.md",
                        subtitle: "Daily note"
                    )
                )
            )
        )

        _ = await coordinator.saveDocument(renamedDocument)
        let savedInputs = await documentManager.savedInputs
        let relocatedInputs = await documentManager.relocatedInputs
        let persistedSessionAfterSave = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(savedInputs.map(\.url), [renamedURL])
        XCTAssertEqual(savedInputs.map(\.relativePath), [renamedRelativePath])
        XCTAssertEqual(relocatedInputs.map(\.fromRelativePath), [PreviewSampleData.dirtyDocument.relativePath])
        XCTAssertEqual(relocatedInputs.map(\.toURL), [renamedURL])
        XCTAssertEqual(relocatedInputs.map(\.toRelativePath), [renamedRelativePath])
        XCTAssertEqual(persistedSessionAfterSave?.relativePath, renamedRelativePath)
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
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
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
    func testDeleteNestedOpenDocumentKeepsFolderRouteAndClearsRestoreState() async throws {
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: PreviewSampleData.dirtyDocument.relativePath)
        )
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace

        var openDocument = PreviewSampleData.dirtyDocument
        openDocument.isDirty = false
        openDocument.saveState = .saved(PreviewSampleData.previewDate)
        session.openDocument = openDocument
        session.path = [.folder(PreviewSampleData.year2026URL), .editor(openDocument.url)]

        let deletedSnapshot = makeWorkspaceSnapshotRemovingFile(url: openDocument.url)
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: deletedSnapshot,
                deleteOutcome: .deletedFile(
                    url: openDocument.url,
                    displayName: openDocument.displayName
                )
            ),
            documentManager: MutationTrackingDocumentManager(),
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.deleteFile(at: openDocument.url)
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.workspaceSnapshot, deletedSnapshot)
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [.folder(PreviewSampleData.year2026URL)])
        XCTAssertEqual(session.lastError?.title, "Document Deleted")
        XCTAssertNil(restoredSession)
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
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
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
    func testStaleObservedRevalidationAfterRenameDoesNotReattachOldDocumentState() async {
        let originalDocument = PreviewSampleData.dirtyDocument
        let renamedURL = PreviewSampleData.year2026URL.appending(path: "2026-04-13 Renamed.md")
        let renamedRelativePath = "Journal/2026/2026-04-13 Renamed.md"

        var revalidatedOldDocument = originalDocument
        revalidatedOldDocument.text = "# Monday\n\nOld file state should not come back."

        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = originalDocument
        session.path = [.folder(PreviewSampleData.year2026URL), .editor(originalDocument.url)]

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: makeWorkspaceSnapshotReplacingFile(
                    oldURL: originalDocument.url,
                    with: .file(
                        .init(
                            url: renamedURL,
                            displayName: "2026-04-13 Renamed.md",
                            subtitle: "Daily note"
                        )
                    )
                ),
                renameOutcome: .renamedFile(
                    oldURL: originalDocument.url,
                    newURL: renamedURL,
                    displayName: "2026-04-13 Renamed.md",
                    relativePath: renamedRelativePath
                )
            ),
            documentManager: RestorationDocumentManager(
                openedDocument: originalDocument,
                revalidatedDocument: revalidatedOldDocument
            ),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.renameFile(at: originalDocument.url, to: "2026-04-13 Renamed")
        let revalidationResult = await coordinator.revalidateObservedDocument(matching: originalDocument)

        XCTAssertNil(revalidationResult)
        XCTAssertEqual(session.openDocument?.url, renamedURL)
        XCTAssertEqual(session.openDocument?.relativePath, renamedRelativePath)
        XCTAssertNotEqual(session.openDocument?.text, revalidatedOldDocument.text)
        XCTAssertEqual(session.path, [.folder(PreviewSampleData.year2026URL), .editor(renamedURL)])
    }

    @MainActor
    func testClearWorkspaceResetsAppStateAndNavigation() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: PreviewSampleData.nestedWorkspace.displayName)
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.editorLoadError = PreviewSampleData.failedLoadError
        session.path = [.settings, .editor(PreviewSampleData.cleanDocument.url)]
        session.lastError = PreviewSampleData.saveFailedError

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.clearWorkspace()

        XCTAssertEqual(session.launchState, RootLaunchState.noWorkspaceSelected)
        XCTAssertEqual(session.workspaceAccessState, WorkspaceAccessState.noneSelected)
        XCTAssertNil(session.workspaceSnapshot)
        XCTAssertNil(session.openDocument)
        XCTAssertNil(session.editorLoadError)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.lastError)
    }

    @MainActor
    func testClearWorkspaceRemovesStoredBookmark() async throws {
        let bookmarkStore = StubBookmarkStore(
            initialBookmark: StoredWorkspaceBookmark(
                workspaceName: PreviewSampleData.nestedWorkspace.displayName,
                lastKnownPath: PreviewSampleData.nestedWorkspace.rootURL.path,
                bookmarkData: Data("workspace-bookmark".utf8)
            )
        )
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: PreviewSampleData.nestedWorkspace.displayName)
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.settings]

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: LiveWorkspaceManager(
                bookmarkStore: bookmarkStore,
                securityScopedAccess: SmokeTestSecurityScopedAccessHandler(),
                workspaceEnumerator: StubWorkspaceEnumerator(snapshot: PreviewSampleData.nestedWorkspace)
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.clearWorkspace()

        let bookmark = try await bookmarkStore.loadBookmark()
        XCTAssertNil(bookmark)
        XCTAssertEqual(session.launchState, RootLaunchState.noWorkspaceSelected)
        XCTAssertEqual(session.path, [])
    }

    @MainActor
    func testClearWorkspaceFailureKeepsExistingStateAndShowsError() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: PreviewSampleData.nestedWorkspace.displayName)
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.settings]

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: PreviewSampleData.nestedWorkspace,
                clearError: .workspaceClearFailed(details: "The bookmark store is unavailable.")
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.clearWorkspace()

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertEqual(session.openDocument?.url, PreviewSampleData.cleanDocument.url)
        XCTAssertEqual(session.path, [.settings])
        XCTAssertEqual(session.lastError?.title, "Can’t Clear Workspace")
    }

    @MainActor
    func testClearWorkspaceAfterInvalidRestoreClearsBookmarkAndDocumentSession() async throws {
        let bookmarkStore = StubBookmarkStore(
            initialBookmark: StoredWorkspaceBookmark(
                workspaceName: PreviewSampleData.nestedWorkspace.displayName,
                lastKnownPath: PreviewSampleData.nestedWorkspace.rootURL.path,
                bookmarkData: Data("workspace-bookmark".utf8)
            )
        )
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: PreviewSampleData.cleanDocument.relativePath)
        )
        let session = AppSession()
        session.launchState = .workspaceAccessInvalid
        session.workspaceAccessState = .invalid(
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            error: PreviewSampleData.invalidWorkspaceError
        )
        session.lastError = PreviewSampleData.invalidWorkspaceError

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: LiveWorkspaceManager(
                bookmarkStore: bookmarkStore,
                securityScopedAccess: SmokeTestSecurityScopedAccessHandler(),
                workspaceEnumerator: StubWorkspaceEnumerator(snapshot: PreviewSampleData.nestedWorkspace)
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.clearWorkspace()

        let bookmark = try await bookmarkStore.loadBookmark()
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertNil(bookmark)
        XCTAssertNil(restoredSession)
        XCTAssertEqual(session.launchState, RootLaunchState.noWorkspaceSelected)
        XCTAssertEqual(session.workspaceAccessState, WorkspaceAccessState.noneSelected)
        XCTAssertNil(session.workspaceSnapshot)
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.lastError)
    }

    @MainActor
    func testReconnectFromSettingsReplacesWorkspaceAndClearsNavigationState() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: PreviewSampleData.nestedWorkspace.displayName)
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.settings]

        let replacementWorkspaceURL = URL(filePath: "/preview/ReconnectedWorkspace")
        let replacementSnapshot = WorkspaceSnapshot(
            rootURL: replacementWorkspaceURL,
            displayName: "ReconnectedWorkspace",
            rootNodes: PreviewSampleData.emptyWorkspace.rootNodes,
            lastUpdated: PreviewSampleData.previewDate
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: replacementSnapshot,
                selectResult: .ready(replacementSnapshot)
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.handleFolderPickerResult(.success([replacementWorkspaceURL]))

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, replacementSnapshot)
        XCTAssertEqual(session.workspaceAccessState, .ready(displayName: "ReconnectedWorkspace"))
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.lastError)
    }

    @MainActor
    func testReconnectFromInvalidWorkspaceRestoresLastOpenDocumentWhenStillValid() async throws {
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: PreviewSampleData.cleanDocument.relativePath)
        )
        let session = AppSession()
        session.launchState = .workspaceAccessInvalid
        session.workspaceAccessState = .invalid(
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            error: PreviewSampleData.invalidWorkspaceError
        )
        session.lastError = PreviewSampleData.invalidWorkspaceError

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: PreviewSampleData.nestedWorkspace,
                selectResult: .ready(PreviewSampleData.nestedWorkspace)
            ),
            documentManager: RestorationDocumentManager(
                openedDocument: PreviewSampleData.cleanDocument
            ),
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.handleFolderPickerResult(.success([PreviewSampleData.workspaceRootURL]))
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertEqual(session.workspaceAccessState, .ready(displayName: PreviewSampleData.nestedWorkspace.displayName))
        XCTAssertEqual(session.openDocument, PreviewSampleData.cleanDocument)
        XCTAssertEqual(session.path, [.editor(PreviewSampleData.cleanDocument.url)])
        XCTAssertNil(session.lastError)
        XCTAssertEqual(restoredSession?.relativePath, PreviewSampleData.cleanDocument.relativePath)
    }

    @MainActor
    func testReconnectFromInvalidWorkspaceWithMissingLastFileKeepsBrowserAndClearsStaleRestoreTarget() async throws {
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: "Journal/2026/Missing.md")
        )
        let session = AppSession()
        session.launchState = .workspaceAccessInvalid
        session.workspaceAccessState = .invalid(
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            error: PreviewSampleData.invalidWorkspaceError
        )
        session.lastError = PreviewSampleData.invalidWorkspaceError

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: PreviewSampleData.nestedWorkspace,
                selectResult: .ready(PreviewSampleData.nestedWorkspace)
            ),
            documentManager: FailingDocumentManager(
                openError: .documentUnavailable(name: "Missing.md")
            ),
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.handleFolderPickerResult(.success([PreviewSampleData.workspaceRootURL]))
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertEqual(session.workspaceAccessState, .ready(displayName: PreviewSampleData.nestedWorkspace.displayName))
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.lastError)
        XCTAssertNil(restoredSession)
    }

    @MainActor
    func testReconnectFromInvalidWorkspaceWithUnreadableLastFileKeepsBrowserAndClearsStaleRestoreTarget() async throws {
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: "Broken.md")
        )
        let session = AppSession()
        session.launchState = .workspaceAccessInvalid
        session.workspaceAccessState = .invalid(
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            error: PreviewSampleData.invalidWorkspaceError
        )
        session.lastError = PreviewSampleData.invalidWorkspaceError

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: PreviewSampleData.nestedWorkspace,
                selectResult: .ready(PreviewSampleData.nestedWorkspace)
            ),
            documentManager: FailingDocumentManager(
                openError: .documentOpenFailed(
                    name: "Broken.md",
                    details: "The file is not valid UTF-8 text."
                )
            ),
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.handleFolderPickerResult(.success([PreviewSampleData.workspaceRootURL]))
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertEqual(session.workspaceAccessState, .ready(displayName: PreviewSampleData.nestedWorkspace.displayName))
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.lastError)
        XCTAssertNil(restoredSession)
    }

    @MainActor
    func testFailedReconnectFromSettingsKeepsExistingWorkspaceAndEditorState() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: PreviewSampleData.nestedWorkspace.displayName)
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.settings]

        let reconnectError = UserFacingError(
            title: "Can’t Open Folder",
            message: "The selected folder could not be loaded.",
            recoverySuggestion: "Try choosing the folder again."
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: PreviewSampleData.nestedWorkspace,
                selectResult: .failed(reconnectError)
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.handleFolderPickerResult(.success([URL(filePath: "/preview/BrokenWorkspace")]))

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertEqual(session.openDocument?.url, PreviewSampleData.cleanDocument.url)
        XCTAssertEqual(session.path, [.settings])
        XCTAssertEqual(session.lastError, reconnectError)
    }

    @MainActor
    func testForegroundRevalidationMarksMissingOpenDocumentWithoutReconnect() async throws {
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: PreviewSampleData.cleanDocument.relativePath)
        )
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: PreviewSampleData.nestedWorkspace.displayName)
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.editor(PreviewSampleData.cleanDocument.url)]

        let missingDocument = LiveDocumentManager.makeConflictDocument(
            from: PreviewSampleData.cleanDocument,
            kind: .missingOnDisk
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: RestorationDocumentManager(
                openedDocument: PreviewSampleData.cleanDocument,
                revalidatedDocument: missingDocument
            ),
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.handleSceneDidBecomeActive()
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.path, [.editor(PreviewSampleData.cleanDocument.url)])
        XCTAssertEqual(session.openDocument?.conflictState, missingDocument.conflictState)
        XCTAssertNil(session.lastError)
        XCTAssertNil(restoredSession)
    }

    @MainActor
    func testForegroundWorkspaceAccessLossTransitionsToReconnectAndClearsEditorState() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: PreviewSampleData.nestedWorkspace.displayName)
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.folder(PreviewSampleData.year2026URL), .editor(PreviewSampleData.cleanDocument.url)]

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: PreviewSampleData.nestedWorkspace,
                refreshError: .workspaceAccessInvalid(displayName: PreviewSampleData.nestedWorkspace.displayName)
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.handleSceneDidBecomeActive()

        XCTAssertEqual(session.launchState, .workspaceAccessInvalid)
        XCTAssertEqual(
            session.workspaceAccessState,
            .invalid(
                displayName: PreviewSampleData.nestedWorkspace.displayName,
                error: UserFacingError(
                    title: "Workspace Needs Reconnect",
                    message: "The workspace can no longer be accessed.",
                    recoverySuggestion: "Reconnect the folder to continue."
                )
            )
        )
        XCTAssertNil(session.workspaceSnapshot)
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertEqual(session.lastError?.title, "Workspace Needs Reconnect")
    }

    @MainActor
    func testSearchResultOpensCorrectEditorDocument() async throws {
        let container = AppContainer.preview(
            launchState: .workspaceReady,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            snapshot: PreviewSampleData.nestedWorkspace
        )
        let workspaceViewModel = container.workspaceViewModel
        let editorViewModel = container.editorViewModel

        workspaceViewModel.searchQuery = "read"
        let result = try XCTUnwrap(workspaceViewModel.searchResults.first)

        container.session.path = [.editor(result.url)]
        editorViewModel.handleAppear(for: result.url)

        try await waitUntil {
            container.session.openDocument?.url == result.url
        }

        XCTAssertEqual(container.session.openDocument?.displayName, result.displayName)
        XCTAssertEqual(container.session.openDocument?.relativePath, result.relativePath)
        XCTAssertEqual(container.session.path, [.editor(result.url)])
        XCTAssertNil(container.session.editorLoadError)
    }

    @MainActor
    func testWorkspaceViewModelProgrammaticOpenUpdatesNavigationPath() {
        let container = AppContainer.preview(
            launchState: .workspaceReady,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            snapshot: PreviewSampleData.nestedWorkspace
        )
        let workspaceViewModel = container.workspaceViewModel

        workspaceViewModel.openFolder(PreviewSampleData.year2026URL)
        workspaceViewModel.openDocument(PreviewSampleData.cleanDocument.url)

        XCTAssertEqual(
            container.session.path,
            [.folder(PreviewSampleData.year2026URL), .editor(PreviewSampleData.cleanDocument.url)]
        )
    }

    @MainActor
    func testWorkspaceNavigationModeUsesValueLinksOnlyForStackNavigation() {
        XCTAssertTrue(WorkspaceNavigationMode.stackPath.usesValueNavigationLinks)
        XCTAssertFalse(WorkspaceNavigationMode.splitSidebar.usesValueNavigationLinks)
    }

    @MainActor
    func testPullToRefreshWhileSearchIsActiveRerunsFilterAndKeepsOpenDocumentState() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.editor(PreviewSampleData.cleanDocument.url)]

        let refreshedSnapshot = makeWorkspaceSnapshotRemovingFile(url: PreviewSampleData.readmeDocumentURL)
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: refreshedSnapshot
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: RecentFilesStore(initialItems: [])
        )

        workspaceViewModel.searchQuery = "read"
        XCTAssertEqual(workspaceViewModel.searchResults.map(\.displayName), ["README.md"])

        await workspaceViewModel.refreshFromPullToRefresh()

        XCTAssertEqual(session.workspaceSnapshot, refreshedSnapshot)
        XCTAssertTrue(workspaceViewModel.isSearching)
        XCTAssertTrue(workspaceViewModel.searchResults.isEmpty)
        XCTAssertEqual(session.openDocument?.url, PreviewSampleData.cleanDocument.url)
        XCTAssertEqual(session.path, [.editor(PreviewSampleData.cleanDocument.url)])
        XCTAssertNil(session.editorLoadError)
    }

    @MainActor
    func testRecentFileOpenedFromSecondarySurfaceReopensCorrectEditorDocument() async throws {
        let recentItem = RecentFileItem(
            workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
            relativePath: PreviewSampleData.cleanDocument.relativePath,
            displayName: PreviewSampleData.cleanDocument.displayName,
            lastOpenedAt: PreviewSampleData.previewDate
        )
        let container = AppContainer.preview(
            launchState: .workspaceReady,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            snapshot: PreviewSampleData.nestedWorkspace,
            recentFiles: [recentItem]
        )
        let workspaceViewModel = container.workspaceViewModel
        let editorViewModel = container.editorViewModel
        let item = try XCTUnwrap(workspaceViewModel.recentFiles.first)

        workspaceViewModel.presentRecentFiles()
        XCTAssertTrue(workspaceViewModel.isShowingRecentFiles)

        workspaceViewModel.openRecentFile(item)
        XCTAssertFalse(workspaceViewModel.isShowingRecentFiles)

        let resolvedURL = try XCTUnwrap(container.session.path.last?.editorURL)
        editorViewModel.handleAppear(for: resolvedURL)

        try await waitUntil {
            container.session.openDocument?.url == resolvedURL
        }

        XCTAssertEqual(container.session.openDocument?.relativePath, PreviewSampleData.cleanDocument.relativePath)
        XCTAssertEqual(container.session.path, [.editor(resolvedURL)])
        XCTAssertNil(container.session.editorLoadError)
    }

    @MainActor
    func testRefreshWorkspacePrunesMissingRecentFiles() async {
        let staleRecentItem = RecentFileItem(
            workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
            relativePath: "Missing.md",
            displayName: "Missing.md",
            lastOpenedAt: PreviewSampleData.previewDate
        )
        let recentFilesStore = RecentFilesStore(
            initialItems: [
                staleRecentItem,
                RecentFileItem(
                    workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                    relativePath: PreviewSampleData.cleanDocument.relativePath,
                    displayName: PreviewSampleData.cleanDocument.displayName,
                    lastOpenedAt: PreviewSampleData.previewDate.addingTimeInterval(-10)
                ),
            ]
        )
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.refreshWorkspace()

        XCTAssertEqual(recentFilesStore.items.map(\.displayName), ["Inbox.md"])
    }

    @MainActor
    func testRenameUpdatesRecentFileEntry() async {
        let renamedURL = PreviewSampleData.inboxDocumentURL.deletingLastPathComponent().appending(path: "Inbox Renamed.md")
        let recentFilesStore = RecentFilesStore(
            initialItems: [
                RecentFileItem(
                    workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                    relativePath: PreviewSampleData.cleanDocument.relativePath,
                    displayName: PreviewSampleData.cleanDocument.displayName,
                    lastOpenedAt: PreviewSampleData.previewDate
                ),
            ]
        )
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: makeWorkspaceSnapshotReplacingRootFile(
                    oldURL: PreviewSampleData.inboxDocumentURL,
                    with: .file(
                        .init(
                            url: renamedURL,
                            displayName: "Localized Inbox Renamed.md",
                            subtitle: "Root document"
                        )
                    )
                ),
                renameOutcome: .renamedFile(
                    oldURL: PreviewSampleData.inboxDocumentURL,
                    newURL: renamedURL,
                    displayName: "Localized Inbox Renamed.md",
                    relativePath: "Inbox Renamed.md"
                )
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.renameFile(at: PreviewSampleData.inboxDocumentURL, to: "Inbox Renamed")

        XCTAssertEqual(recentFilesStore.items.map(\.displayName), ["Localized Inbox Renamed.md"])
        XCTAssertEqual(recentFilesStore.items.first?.relativePath, "Inbox Renamed.md")
    }

    @MainActor
    func testDeleteRemovesRecentFileEntry() async {
        let recentFilesStore = RecentFilesStore(
            initialItems: [
                RecentFileItem(
                    workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                    relativePath: PreviewSampleData.cleanDocument.relativePath,
                    displayName: PreviewSampleData.cleanDocument.displayName,
                    lastOpenedAt: PreviewSampleData.previewDate
                ),
            ]
        )
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = makeWorkspaceSnapshotRemovingRootFile(url: PreviewSampleData.inboxDocumentURL)

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: makeWorkspaceSnapshotRemovingRootFile(url: PreviewSampleData.inboxDocumentURL),
                deleteOutcome: .deletedFile(
                    url: PreviewSampleData.inboxDocumentURL,
                    displayName: PreviewSampleData.cleanDocument.displayName
                )
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.deleteFile(at: PreviewSampleData.inboxDocumentURL)

        XCTAssertTrue(recentFilesStore.items.isEmpty)
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
    private func makeWorkspaceSnapshotReplacingFile(
        oldURL: URL,
        with replacement: WorkspaceNode
    ) -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            rootURL: PreviewSampleData.nestedWorkspace.rootURL,
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            rootNodes: replacingNode(oldURL: oldURL, with: replacement, in: PreviewSampleData.nestedWorkspace.rootNodes),
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

    @MainActor
    private func makeWorkspaceSnapshotRemovingFile(url: URL) -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            rootURL: PreviewSampleData.nestedWorkspace.rootURL,
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            rootNodes: removingNode(url: url, in: PreviewSampleData.nestedWorkspace.rootNodes),
            lastUpdated: PreviewSampleData.previewDate
        )
    }

    @MainActor
    private func replacingNode(
        oldURL: URL,
        with replacement: WorkspaceNode,
        in nodes: [WorkspaceNode]
    ) -> [WorkspaceNode] {
        nodes.map { node in
            if node.url == oldURL {
                return replacement
            }

            guard case let .folder(folder) = node else {
                return node
            }

            return .folder(
                .init(
                    url: folder.url,
                    displayName: folder.displayName,
                    children: replacingNode(oldURL: oldURL, with: replacement, in: folder.children)
                )
            )
        }
    }

    @MainActor
    private func removingNode(
        url: URL,
        in nodes: [WorkspaceNode]
    ) -> [WorkspaceNode] {
        nodes.compactMap { node in
            if node.url == url {
                return nil
            }

            guard case let .folder(folder) = node else {
                return node
            }

            return .folder(
                .init(
                    url: folder.url,
                    displayName: folder.displayName,
                    children: removingNode(url: url, in: folder.children)
                )
            )
        }
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(20),
        condition: @escaping @MainActor () -> Bool
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

private struct SmokeTestSecurityScopedAccessHandler: SecurityScopedAccessHandling {
    func makeBookmark(for url: URL) throws -> Data {
        Data()
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedSecurityScopedURL {
        ResolvedSecurityScopedURL(url: URL(filePath: "/tmp"), displayName: "tmp", isStale: false)
    }

    func validateAccess(to url: URL) throws {}

    func beginAccess(to url: URL) throws -> SecurityScopedAccessLease {
        SecurityScopedAccessLease(url: url, stopHandler: nil)
    }

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

    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument {
        throw openError
    }

    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument {
        throw openError
    }

    func observeDocumentChanges(for document: OpenDocument) async throws -> AsyncStream<Void> {
        throw openError
    }

    func relocateDocumentSession(
        for document: OpenDocument,
        to url: URL,
        relativePath: String
    ) async {}
}

private actor RestorationDocumentManager: DocumentManager {
    let openedDocument: OpenDocument
    let revalidatedDocument: OpenDocument?

    init(
        openedDocument: OpenDocument,
        revalidatedDocument: OpenDocument? = nil
    ) {
        self.openedDocument = openedDocument
        self.revalidatedDocument = revalidatedDocument
    }

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument {
        openedDocument
    }

    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument {
        openedDocument
    }

    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument {
        revalidatedDocument ?? document
    }

    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument {
        document
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

private actor MutationTrackingDocumentManager: DocumentManager {
    private(set) var savedInputs: [OpenDocument] = []
    private(set) var relocatedInputs: [RelocatedDocumentSession] = []

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument {
        throw AppError.documentUnavailable(name: url.lastPathComponent)
    }

    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument {
        document
    }

    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument {
        document
    }

    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument {
        savedInputs.append(document)
        var savedDocument = document
        savedDocument.isDirty = false
        savedDocument.saveState = .saved(Date(timeIntervalSince1970: 1_710_000_000))
        savedDocument.conflictState = .none
        return savedDocument
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
    ) async {
        relocatedInputs.append(
            RelocatedDocumentSession(
                fromRelativePath: document.relativePath,
                toURL: url,
                toRelativePath: relativePath
            )
        )
    }
}

private actor DelayedOpenDocumentManager: DocumentManager {
    let documents: [URL: OpenDocument]
    let openDelays: [URL: Duration]
    private(set) var observedURLs: [URL] = []

    init(
        documents: [URL: OpenDocument],
        openDelays: [URL: Duration]
    ) {
        self.documents = documents
        self.openDelays = openDelays
    }

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument {
        if let delay = openDelays[url] {
            try await Task.sleep(for: delay)
        }

        guard let document = documents[url] else {
            throw AppError.documentUnavailable(name: url.lastPathComponent)
        }

        return document
    }

    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument {
        document
    }

    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument {
        document
    }

    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument {
        document
    }

    func observeDocumentChanges(for document: OpenDocument) async throws -> AsyncStream<Void> {
        observedURLs.append(document.url)
        return AsyncStream<Void> { continuation in
            continuation.finish()
        }
    }

    func relocateDocumentSession(
        for document: OpenDocument,
        to url: URL,
        relativePath: String
    ) async {}
}

private actor DelayedRevalidationDocumentManager: DocumentManager {
    let revalidatedDocument: OpenDocument
    let revalidationDelay: Duration

    init(
        revalidatedDocument: OpenDocument,
        revalidationDelay: Duration
    ) {
        self.revalidatedDocument = revalidatedDocument
        self.revalidationDelay = revalidationDelay
    }

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument {
        revalidatedDocument
    }

    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument {
        document
    }

    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument {
        try await Task.sleep(for: revalidationDelay)
        return revalidatedDocument
    }

    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument {
        document
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

private struct RelocatedDocumentSession: Equatable, Sendable {
    let fromRelativePath: String
    let toURL: URL
    let toRelativePath: String
}

private actor MutationTestingWorkspaceManager: WorkspaceManager {
    let refreshSnapshot: WorkspaceSnapshot
    let selectResult: WorkspaceRestoreResult?
    let renameOutcome: WorkspaceMutationOutcome?
    let deleteOutcome: WorkspaceMutationOutcome?
    let clearError: AppError?
    let refreshError: AppError?
    private(set) var deleteCalls: [URL] = []

    init(
        refreshSnapshot: WorkspaceSnapshot,
        selectResult: WorkspaceRestoreResult? = nil,
        renameOutcome: WorkspaceMutationOutcome? = nil,
        deleteOutcome: WorkspaceMutationOutcome? = nil,
        clearError: AppError? = nil,
        refreshError: AppError? = nil
    ) {
        self.refreshSnapshot = refreshSnapshot
        self.selectResult = selectResult
        self.renameOutcome = renameOutcome
        self.deleteOutcome = deleteOutcome
        self.clearError = clearError
        self.refreshError = refreshError
    }

    func restoreWorkspace() async -> WorkspaceRestoreResult {
        .ready(refreshSnapshot)
    }

    func selectWorkspace(at url: URL) async -> WorkspaceRestoreResult {
        if let selectResult {
            return selectResult
        }

        return .ready(refreshSnapshot)
    }

    func refreshCurrentWorkspace() async throws -> WorkspaceSnapshot {
        if let refreshError {
            throw refreshError
        }

        return refreshSnapshot
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

    func clearWorkspaceSelection() async throws {
        if let clearError {
            throw clearError
        }
    }
}
