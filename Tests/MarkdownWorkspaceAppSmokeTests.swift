import XCTest
@testable import Downward

final class MarkdownWorkspaceAppSmokeTests: MarkdownWorkspaceAppTestCase {
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
            folderPickerBridge: StubFolderPickerBridge()
        )

        await container.coordinator.bootstrapIfNeeded()

        XCTAssertEqual(container.session.launchState, RootLaunchState.noWorkspaceSelected)
        XCTAssertEqual(container.session.workspaceAccessState, WorkspaceAccessState.noneSelected)
        XCTAssertNil(container.session.workspaceSnapshot)
    }

    @MainActor
    func testFastLaunchWorkspaceRestoreDoesNotShowDelayedSpinner() async {
        let container = makeBootstrapContainer(
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace,
                forcedRestoreResult: .ready(PreviewSampleData.nestedWorkspace)
            )
        )

        await container.rootViewModel.handleFirstAppear()

        XCTAssertEqual(container.session.launchState, .workspaceReady)
        XCTAssertFalse(container.rootViewModel.isRestoringWorkspace)
        XCTAssertFalse(container.rootViewModel.shouldShowRestoreSpinner)
        XCTAssertFalse(container.rootViewModel.shouldShowSlowRestoreMessage)
    }

    @MainActor
    func testSlowLaunchWorkspaceRestoreShowsDelayedMinimalSpinner() async {
        let workspaceManager = DelayedRestoreWorkspaceManager(
            result: .ready(PreviewSampleData.nestedWorkspace),
            delay: .milliseconds(500),
            fallbackSnapshot: PreviewSampleData.nestedWorkspace
        )
        let container = makeBootstrapContainer(workspaceManager: workspaceManager)

        let restoreTask = Task { @MainActor in
            await container.rootViewModel.handleFirstAppear()
        }

        XCTAssertTrue(container.rootViewModel.shouldShowInitialRestoreShell)
        XCTAssertFalse(container.rootViewModel.shouldShowRestoreSpinner)

        try? await Task.sleep(for: .milliseconds(350))

        XCTAssertTrue(container.rootViewModel.shouldShowInitialRestoreShell)
        XCTAssertTrue(container.rootViewModel.shouldShowRestoreSpinner)
        XCTAssertFalse(container.rootViewModel.shouldShowSlowRestoreMessage)

        await restoreTask.value

        XCTAssertEqual(container.session.launchState, .workspaceReady)
        XCTAssertFalse(container.rootViewModel.shouldShowInitialRestoreShell)
        XCTAssertFalse(container.rootViewModel.shouldShowRestoreSpinner)
        XCTAssertFalse(container.rootViewModel.shouldShowSlowRestoreMessage)
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
    func testEditorLoadFailureDoesNotOverwriteExistingWorkspaceAlert() async throws {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.workspaceAlertError = PreviewSampleData.saveFailedError
        session.path = [.editor(PreviewSampleData.cleanDocument.url)]

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
        let viewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            autosaveDelay: .milliseconds(20)
        )

        viewModel.handleAppear(for: PreviewSampleData.cleanDocument.url)

        try await waitUntil { session.editorLoadError != nil }

        XCTAssertEqual(session.workspaceAlertError, PreviewSampleData.saveFailedError)
        XCTAssertEqual(session.editorLoadError?.title, "Document Unavailable")
        XCTAssertNil(session.editorAlertError)
    }

    @MainActor
    func testActivatingLoadedDocumentClearsOnlyEditorOwnedErrors() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.workspaceAlertError = PreviewSampleData.saveFailedError
        session.editorLoadError = PreviewSampleData.failedLoadError
        session.editorAlertError = PreviewSampleData.failedLaunchError

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.activateLoadedDocument(PreviewSampleData.cleanDocument)

        XCTAssertEqual(session.workspaceAlertError, PreviewSampleData.saveFailedError)
        XCTAssertNil(session.editorLoadError)
        XCTAssertNil(session.editorAlertError)
    }

    @MainActor
    func testDismissingRootAlertDoesNotClearEditorAlert() {
        let container = AppContainer.preview(
            launchState: .workspaceReady,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            snapshot: PreviewSampleData.nestedWorkspace
        )
        container.session.workspaceAlertError = PreviewSampleData.saveFailedError
        container.session.editorAlertError = PreviewSampleData.failedLoadError

        XCTAssertEqual(container.rootViewModel.alertError, PreviewSampleData.saveFailedError)

        container.rootViewModel.dismissAlert()

        XCTAssertNil(container.session.workspaceAlertError)
        XCTAssertEqual(container.session.editorAlertError, PreviewSampleData.failedLoadError)
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

        try await waitUntil { session.openDocument?.url == secondDocument.url }
        try await Task.sleep(for: .milliseconds(220))
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()
        let observedURLs = await documentManager.observedURLs

        XCTAssertEqual(session.openDocument?.url, secondDocument.url)
        XCTAssertEqual(session.openDocument?.displayName, secondDocument.displayName)
        XCTAssertEqual(session.path, [.editor(secondDocument.url)])
        XCTAssertNil(session.editorLoadError)
        XCTAssertNil(session.workspaceAlertError)
        XCTAssertNil(session.editorAlertError)
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
            documents: [PreviewSampleData.cleanDocument.url: PreviewSampleData.cleanDocument],
            openDelays: [PreviewSampleData.cleanDocument.url: .milliseconds(180)]
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
        XCTAssertNil(session.workspaceAlertError)
        XCTAssertNil(session.editorAlertError)
        XCTAssertTrue(observedURLs.isEmpty)
        XCTAssertNil(restoredSession)
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
        XCTAssertEqual(session.path, trustedEditorPath(for: PreviewSampleData.cleanDocument))
        XCTAssertNil(session.workspaceAlertError)
    }

    @MainActor
    func testBootstrapRestoresLastOpenJSONDocumentAsEditorDocument() async throws {
        let workspaceURL = try makeTemporaryWorkspace(named: "RestoreJSONWorkspace")
        defer { removeItemIfPresent(at: workspaceURL) }
        let jsonText = #"{"lastOpen":"ordinary workspace JSON"}"#
        let jsonURL = try createFile(named: "Theme.json", contents: jsonText, in: workspaceURL)
        let snapshot = WorkspaceSnapshot(
            rootURL: workspaceURL,
            displayName: "Restore JSON Workspace",
            rootNodes: [
                .file(
                    .init(
                        url: jsonURL,
                        displayName: "Theme.json",
                        subtitle: "Root document"
                    )
                ),
            ],
            lastUpdated: PreviewSampleData.previewDate
        )
        let document = OpenDocument(
            url: jsonURL,
            workspaceRootURL: workspaceURL,
            relativePath: "Theme.json",
            displayName: "Theme.json",
            text: jsonText,
            loadedVersion: PreviewSampleData.cleanDocument.loadedVersion,
            isDirty: false,
            saveState: .idle,
            conflictState: .none
        )
        let existingTheme = Self.makeTheme(name: "Existing Theme")
        let themeStore = ThemeStore(fileURL: try makeTemporaryThemeURL())
        await themeStore.waitForInitialLoad()
        let didAddExistingTheme = await themeStore.add(existingTheme)
        XCTAssertTrue(didAddExistingTheme)
        let documentManager = RelativePathOnlyDocumentManager(
            documentsByRelativePath: [document.relativePath: document]
        )
        let container = AppContainer(
            logger: DebugLogger(),
            bookmarkStore: StubBookmarkStore(),
            sessionStore: StubSessionStore(
                initialSession: RestorableDocumentSession(relativePath: document.relativePath)
            ),
            recentFilesStore: RecentFilesStore(initialItems: []),
            editorAppearanceStore: EditorAppearanceStore(),
            themeStore: themeStore,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: snapshot,
                forcedRestoreResult: .ready(snapshot)
            ),
            documentManager: documentManager,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge()
        )

        await container.coordinator.bootstrapIfNeeded()

        let openedRelativePaths = await documentManager.recordedOpenedRelativePaths()

        XCTAssertEqual(container.session.launchState, .workspaceReady)
        XCTAssertEqual(container.session.workspaceSnapshot, snapshot)
        XCTAssertEqual(container.session.openDocument, document)
        XCTAssertEqual(container.session.path, [.trustedEditor(jsonURL, document.relativePath)])
        XCTAssertEqual(openedRelativePaths, [document.relativePath])
        XCTAssertEqual(themeStore.themes, [existingTheme])
        XCTAssertNil(themeStore.lastError)
        XCTAssertNil(container.session.workspaceAlertError)
    }

    @MainActor
    func testRenameFolderContainingOpenDocumentUpdatesEditorStateAndRecents() async throws {
        let renamedFolderURL = PreviewSampleData.workspaceRootURL.appending(path: "Logbook")
        let renamedYearURL = renamedFolderURL.appending(path: "2026")
        let renamedDocumentURL = renamedYearURL.appending(path: "2026-04-13.md")
        let renamedRelativePath = "Logbook/2026/2026-04-13.md"
        let renamedSnapshot = makeWorkspaceSnapshotReplacingFile(
            oldURL: PreviewSampleData.journalURL,
            with: .folder(
                .init(
                    url: renamedFolderURL,
                    displayName: "Logbook",
                    children: [
                        .folder(
                            .init(
                                url: renamedYearURL,
                                displayName: "2026",
                                children: [
                                    .file(.init(url: renamedDocumentURL, displayName: "2026-04-13.md", subtitle: "Daily note")),
                                    .file(.init(url: renamedYearURL.appending(path: "Ideas.markdown"), displayName: "Ideas.markdown", subtitle: "Scratchpad")),
                                ]
                            )
                        ),
                    ]
                )
            )
        )
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: PreviewSampleData.dirtyDocument.relativePath)
        )
        let recentFilesStore = RecentFilesStore(
            initialItems: [
                RecentFileItem(
                    workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                    relativePath: PreviewSampleData.dirtyDocument.relativePath,
                    displayName: PreviewSampleData.dirtyDocument.displayName,
                    lastOpenedAt: PreviewSampleData.previewDate
                ),
            ]
        )
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.dirtyDocument
        session.path = [.editor(PreviewSampleData.dirtyDocument.url)]

        let documentManager = MutationTrackingDocumentManager()
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: renamedSnapshot,
                renameOutcome: .renamedFolder(
                    oldURL: PreviewSampleData.journalURL,
                    newURL: renamedFolderURL,
                    displayName: "Logbook",
                    relativePath: "Logbook"
                )
            ),
            documentManager: documentManager,
            sessionStore: sessionStore,
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.renameFile(at: PreviewSampleData.journalURL, to: "Logbook")
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()
        let relocatedInputs = await documentManager.relocatedInputs

        XCTAssertEqual(session.workspaceSnapshot, renamedSnapshot)
        XCTAssertEqual(session.openDocument?.url, renamedDocumentURL)
        XCTAssertEqual(session.openDocument?.relativePath, renamedRelativePath)
        XCTAssertEqual(session.path, [.editor(renamedDocumentURL)])
        XCTAssertEqual(restoredSession?.relativePath, renamedRelativePath)
        XCTAssertEqual(relocatedInputs.map(\.toURL), [renamedDocumentURL])
        XCTAssertEqual(relocatedInputs.map(\.toRelativePath), [renamedRelativePath])
        XCTAssertEqual(recentFilesStore.items.map(\.relativePath), [renamedRelativePath])
    }

    @MainActor
    func testRenameFolderPendingEditorPresentationWithNonCanonicalPreferredURLUsesTrustedReplacementURL() async {
        let renamedFolderURL = PreviewSampleData.workspaceRootURL.appending(path: "Logbook")
        let renamedYearURL = renamedFolderURL.appending(path: "2026")
        let renamedDocumentURL = renamedYearURL.appending(path: "2026-04-13.md")
        let renamedRelativePath = "Logbook/2026/2026-04-13.md"
        let aliasedRouteURL = URL(filePath: "/alias-root/Journal/2026/2026-04-13.md")
        let renamedSnapshot = makeWorkspaceSnapshotRenamingJournalFolder(to: "Logbook")
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.pendingEditorPresentation = .init(
            routeURL: aliasedRouteURL,
            relativePath: PreviewSampleData.dirtyDocument.relativePath
        )

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: renamedSnapshot,
                renameOutcome: .renamedFolder(
                    oldURL: PreviewSampleData.journalURL,
                    newURL: renamedFolderURL,
                    displayName: "Logbook",
                    relativePath: "Logbook"
                )
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.renameFile(at: PreviewSampleData.journalURL, to: "Logbook")

        XCTAssertEqual(session.pendingEditorPresentation?.relativePath, renamedRelativePath)
        XCTAssertEqual(session.pendingEditorPresentation?.routeURL, renamedDocumentURL)
    }

    @MainActor
    func testRenameFolderCompactTrustedRouteUsesSnapshotURLWhenExistingRouteDiffersLexically() async {
        let renamedFolderURL = PreviewSampleData.workspaceRootURL.appending(path: "Logbook")
        let renamedYearURL = renamedFolderURL.appending(path: "2026")
        let renamedDocumentURL = renamedYearURL.appending(path: "2026-04-13.md")
        let renamedRelativePath = "Logbook/2026/2026-04-13.md"
        let aliasedRouteURL = URL(filePath: "/alias-root/Journal/2026/2026-04-13.md")
        let renamedSnapshot = makeWorkspaceSnapshotRenamingJournalFolder(to: "Logbook")
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.path = [.trustedEditor(
            aliasedRouteURL,
            PreviewSampleData.dirtyDocument.relativePath
        )]

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: renamedSnapshot,
                renameOutcome: .renamedFolder(
                    oldURL: PreviewSampleData.journalURL,
                    newURL: renamedFolderURL,
                    displayName: "Logbook",
                    relativePath: "Logbook"
                )
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.renameFile(at: PreviewSampleData.journalURL, to: "Logbook")

        XCTAssertEqual(session.path, [.trustedEditor(renamedDocumentURL, renamedRelativePath)])
    }

    @MainActor
    func testRenameFolderRegularNavigationRewritesRelativeSelectionAndCanonicalizesOpenDocumentURL() async throws {
        let renamedFolderURL = PreviewSampleData.workspaceRootURL.appending(path: "Logbook")
        let renamedYearURL = renamedFolderURL.appending(path: "2026")
        let renamedDocumentURL = renamedYearURL.appending(path: "2026-04-13.md")
        let renamedRelativePath = "Logbook/2026/2026-04-13.md"
        let aliasedRouteURL = URL(filePath: "/alias-root/Journal/2026/2026-04-13.md")
        let renamedSnapshot = makeWorkspaceSnapshotRenamingJournalFolder(to: "Logbook")
        let session = AppSession()
        session.launchState = .workspaceReady
        session.navigationLayout = .regular
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        var aliasedOpenDocument = PreviewSampleData.dirtyDocument
        aliasedOpenDocument.url = aliasedRouteURL
        session.openDocument = aliasedOpenDocument
        session.regularDetailSelection = .editor(aliasedOpenDocument.relativePath)

        let documentManager = MutationTrackingDocumentManager()
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: renamedSnapshot,
                renameOutcome: .renamedFolder(
                    oldURL: PreviewSampleData.journalURL,
                    newURL: renamedFolderURL,
                    displayName: "Logbook",
                    relativePath: "Logbook"
                )
            ),
            documentManager: documentManager,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.renameFile(at: PreviewSampleData.journalURL, to: "Logbook")
        let relocatedInputs = await documentManager.relocatedInputs

        XCTAssertEqual(session.regularDetailSelection, .editor(renamedRelativePath))
        XCTAssertEqual(session.regularWorkspaceDetail, .editor(renamedDocumentURL))
        XCTAssertEqual(session.openDocument?.url, renamedDocumentURL)
        XCTAssertEqual(session.openDocument?.relativePath, renamedRelativePath)
        XCTAssertEqual(relocatedInputs.map(\.toURL), [renamedDocumentURL])
        XCTAssertEqual(relocatedInputs.map(\.toRelativePath), [renamedRelativePath])
    }

    @MainActor
    func testDeleteNestedOpenDocumentClosesEditorAndClearsRestoreState() async throws {
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
        session.path = [.editor(openDocument.url)]

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
        XCTAssertEqual(session.path, [])
        XCTAssertEqual(session.workspaceAlertError?.title, "Document Deleted")
        XCTAssertNil(restoredSession)
    }

    @MainActor
    func testDeleteFolderContainingOpenDocumentClosesEditorClearsRestoreStateAndRecents() async throws {
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: PreviewSampleData.dirtyDocument.relativePath)
        )
        let recentFilesStore = RecentFilesStore(
            initialItems: [
                RecentFileItem(
                    workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                    relativePath: PreviewSampleData.dirtyDocument.relativePath,
                    displayName: PreviewSampleData.dirtyDocument.displayName,
                    lastOpenedAt: PreviewSampleData.previewDate
                ),
            ]
        )
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace

        var openDocument = PreviewSampleData.dirtyDocument
        openDocument.isDirty = false
        openDocument.saveState = .saved(PreviewSampleData.previewDate)
        session.openDocument = openDocument
        session.path = [.editor(openDocument.url)]

        let deletedSnapshot = makeWorkspaceSnapshotRemovingFile(url: PreviewSampleData.journalURL)
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: deletedSnapshot,
                deleteOutcome: .deletedFolder(
                    url: PreviewSampleData.journalURL,
                    displayName: "Journal"
                )
            ),
            documentManager: MutationTrackingDocumentManager(),
            sessionStore: sessionStore,
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.deleteFile(at: PreviewSampleData.journalURL)
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.workspaceSnapshot, deletedSnapshot)
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertEqual(session.workspaceAlertError?.title, "Document Deleted")
        XCTAssertNil(restoredSession)
        XCTAssertTrue(recentFilesStore.items.isEmpty)
    }

    @MainActor
    func testDeletePreviouslyOpenedButUnselectedFileDoesNotShowDeletedPopup() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = []
        session.regularDetailSelection = .placeholder

        let deletedSnapshot = makeWorkspaceSnapshotRemovingRootFile(url: PreviewSampleData.cleanDocument.url)
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
        XCTAssertNil(session.workspaceAlertError)
        XCTAssertEqual(session.path, [])
        XCTAssertEqual(session.regularDetailSelection, .placeholder)
    }

    @MainActor
    func testDeleteHiddenPendingPresentationDoesNotShowDeletedPopup() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.path = [.settings]
        session.pendingEditorPresentation = .init(
            routeURL: PreviewSampleData.cleanDocument.url,
            relativePath: PreviewSampleData.cleanDocument.relativePath
        )

        let deletedSnapshot = makeWorkspaceSnapshotRemovingRootFile(url: PreviewSampleData.cleanDocument.url)
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
        XCTAssertNil(session.pendingEditorPresentation)
        XCTAssertEqual(session.path, [.settings])
        XCTAssertNil(session.workspaceAlertError)
    }

    @MainActor
    func testDeleteUnmappedFileWithoutVisibleEditorDoesNotShowDeletedPopup() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.path = []
        session.regularDetailSelection = .placeholder

        let unmappedURL = PreviewSampleData.workspaceRootURL.appending(path: "Ghost.md")
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: PreviewSampleData.nestedWorkspace,
                deleteOutcome: .deletedFile(
                    url: unmappedURL,
                    displayName: "Ghost.md"
                )
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.deleteFile(at: unmappedURL)

        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertNil(session.workspaceAlertError)
        XCTAssertEqual(session.path, [])
        XCTAssertEqual(session.regularDetailSelection, .placeholder)
    }

    private func makeTemporaryThemeURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "MarkdownWorkspaceSmokeThemeStore-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appending(path: "themes.json")
    }

    @MainActor
    private func makeBootstrapContainer(workspaceManager: any WorkspaceManager) -> AppContainer {
        AppContainer(
            logger: DebugLogger(),
            bookmarkStore: StubBookmarkStore(),
            recentFilesStore: RecentFilesStore(initialItems: []),
            editorAppearanceStore: EditorAppearanceStore(),
            workspaceManager: workspaceManager,
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge()
        )
    }

    private static func makeTheme(id: UUID = UUID(), name: String) -> CustomTheme {
        CustomTheme(
            id: id,
            name: name,
            background: HexColor(hex: "#1E1E1E"),
            text: HexColor(hex: "#D4D4D4"),
            tint: HexColor(hex: "#569CD6"),
            boldItalicMarker: HexColor(hex: "#72727F"),
            strikethrough: HexColor(hex: "#808080"),
            inlineCode: HexColor(hex: "#CE9178"),
            codeBackground: HexColor(hex: "#2D2D2D"),
            horizontalRule: HexColor(hex: "#404040"),
            checkboxUnchecked: HexColor(hex: "#F44747"),
            checkboxChecked: HexColor(hex: "#6A9955")
        )
    }
}

private actor DelayedRestoreWorkspaceManager: WorkspaceManager {
    private let result: WorkspaceRestoreResult
    private let delay: Duration
    private let fallbackSnapshot: WorkspaceSnapshot

    init(result: WorkspaceRestoreResult, delay: Duration, fallbackSnapshot: WorkspaceSnapshot) {
        self.result = result
        self.delay = delay
        self.fallbackSnapshot = fallbackSnapshot
    }

    func restoreWorkspace() async -> WorkspaceRestoreResult {
        try? await Task.sleep(for: delay)
        return result
    }

    func selectWorkspace(at url: URL) async -> WorkspaceRestoreResult {
        result
    }

    func refreshCurrentWorkspace() async throws -> WorkspaceSnapshot {
        fallbackSnapshot
    }

    func createFile(
        named proposedName: String,
        in folderURL: URL?,
        initialContent: WorkspaceCreatedFileInitialContent
    ) async throws -> WorkspaceMutationResult {
        WorkspaceMutationResult(
            snapshot: fallbackSnapshot,
            outcome: .createdFile(
                url: (folderURL ?? fallbackSnapshot.rootURL).appending(path: proposedName),
                displayName: proposedName
            )
        )
    }

    func createFolder(named proposedName: String, in folderURL: URL?) async throws -> WorkspaceMutationResult {
        WorkspaceMutationResult(
            snapshot: fallbackSnapshot,
            outcome: .createdFolder(
                url: (folderURL ?? fallbackSnapshot.rootURL).appending(path: proposedName),
                displayName: proposedName
            )
        )
    }

    func renameFile(at url: URL, to proposedName: String) async throws -> WorkspaceMutationResult {
        WorkspaceMutationResult(
            snapshot: fallbackSnapshot,
            outcome: .renamedFile(
                oldURL: url,
                newURL: url.deletingLastPathComponent().appending(path: proposedName),
                displayName: proposedName,
                relativePath: proposedName
            )
        )
    }

    func moveItem(at url: URL, toFolder destinationFolderURL: URL?) async throws -> WorkspaceMutationResult {
        WorkspaceMutationResult(
            snapshot: fallbackSnapshot,
            outcome: .renamedFile(
                oldURL: url,
                newURL: (destinationFolderURL ?? fallbackSnapshot.rootURL).appending(path: url.lastPathComponent),
                displayName: url.lastPathComponent,
                relativePath: url.lastPathComponent
            )
        )
    }

    func deleteFile(at url: URL) async throws -> WorkspaceMutationResult {
        WorkspaceMutationResult(
            snapshot: fallbackSnapshot,
            outcome: .deletedFile(url: url, displayName: url.lastPathComponent)
        )
    }

    func clearWorkspaceSelection() async throws {}
}
