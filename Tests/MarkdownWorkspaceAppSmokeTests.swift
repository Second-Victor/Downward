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
            folderPickerBridge: StubFolderPickerBridge()
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

        try await waitUntil {
            session.editorLoadError != nil
        }

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
        XCTAssertNil(session.workspaceAlertError)
        XCTAssertNil(session.editorAlertError)
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
        XCTAssertEqual(session.workspaceAlertError?.title, "Document Unavailable")
        XCTAssertNil(restoredSession)
    }

    @MainActor
    func testRefreshWorkspaceClearsMissingRegularEditorSelection() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.navigationLayout = .regular
        session.regularDetailSelection = .editor(PreviewSampleData.dirtyDocument.relativePath)

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
        XCTAssertEqual(session.regularDetailSelection, .placeholder)
        XCTAssertNil(session.workspaceAlertError)
    }

    @MainActor
    func testOverlappingRefreshesApplyOnlyNewestSnapshotAndSkipStaleReconciliation() async {
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
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.editor(PreviewSampleData.cleanDocument.url)]

        let olderSnapshot = makeWorkspaceSnapshotRemovingRootFile(url: PreviewSampleData.inboxDocumentURL)
        let newerSnapshot = PreviewSampleData.nestedWorkspace
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: SequencedRefreshWorkspaceManager(
                refreshResponses: [
                    .success(snapshot: olderSnapshot, delay: .milliseconds(180)),
                    .success(snapshot: newerSnapshot, delay: .milliseconds(20)),
                ],
                fallbackSnapshot: newerSnapshot
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        let olderRefreshTask = Task {
            await coordinator.refreshWorkspace()
        }
        try? await Task.sleep(for: .milliseconds(30))
        let newerRefreshResult = await coordinator.refreshWorkspace()
        let olderRefreshResult = await olderRefreshTask.value

        guard case let .success(snapshot)? = newerRefreshResult else {
            return XCTFail("Expected newest refresh to win.")
        }

        XCTAssertEqual(snapshot, newerSnapshot)
        XCTAssertNil(olderRefreshResult)
        XCTAssertEqual(session.workspaceSnapshot, newerSnapshot)
        XCTAssertEqual(session.openDocument?.url, PreviewSampleData.cleanDocument.url)
        XCTAssertEqual(session.path, [.editor(PreviewSampleData.cleanDocument.url)])
        XCTAssertEqual(recentFilesStore.items.map(\.displayName), ["Inbox.md"])
        XCTAssertNil(session.workspaceAlertError)
    }

    @MainActor
    func testForegroundRefreshRaceWithPullToRefreshAppliesOnlyWinningSnapshot() async {
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
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.editor(PreviewSampleData.cleanDocument.url)]

        let olderSnapshot = makeWorkspaceSnapshotRemovingRootFile(url: PreviewSampleData.inboxDocumentURL)
        let newerSnapshot = PreviewSampleData.nestedWorkspace
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: SequencedRefreshWorkspaceManager(
                refreshResponses: [
                    .success(snapshot: olderSnapshot, delay: .milliseconds(180)),
                    .success(snapshot: newerSnapshot, delay: .milliseconds(20)),
                ],
                fallbackSnapshot: newerSnapshot
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: recentFilesStore
        )

        let foregroundTask = Task {
            await coordinator.handleSceneDidBecomeActive()
        }
        try? await Task.sleep(for: .milliseconds(30))
        await workspaceViewModel.refreshFromPullToRefresh()
        await foregroundTask.value

        XCTAssertEqual(session.workspaceSnapshot, newerSnapshot)
        XCTAssertEqual(session.openDocument?.url, PreviewSampleData.cleanDocument.url)
        XCTAssertEqual(session.path, [.editor(PreviewSampleData.cleanDocument.url)])
        XCTAssertEqual(recentFilesStore.items.map(\.displayName), ["Inbox.md"])
        XCTAssertNil(session.workspaceAlertError)
        XCTAssertFalse(workspaceViewModel.isRefreshing)
    }

    @MainActor
    func testRefreshRaceWithRenameAppliesOnlyWinningMutationSnapshotAndReconciliation() async {
        let workspaceRootURL = try! makeTemporaryWorkspace(named: "RenameRaceWorkspace")
        defer { removeItemIfPresent(at: workspaceRootURL) }

        let originalURL = try! createFile(
            named: "Inbox.md",
            contents: "# Inbox\n\nOriginal text.",
            in: workspaceRootURL
        )
        let renamedURL = try! createFile(
            named: "Inbox Renamed.md",
            contents: "# Inbox\n\nRenamed text.",
            in: workspaceRootURL
        )
        let renamedRelativePath = "Inbox Renamed.md"
        let staleRefreshSnapshot = WorkspaceSnapshot(
            rootURL: workspaceRootURL,
            displayName: "RenameRaceWorkspace",
            rootNodes: [
                .file(
                    .init(
                        url: originalURL,
                        displayName: "Inbox.md",
                        subtitle: "Root document"
                    )
                ),
            ],
            lastUpdated: PreviewSampleData.previewDate
        )
        let renamedSnapshot = WorkspaceSnapshot(
            rootURL: workspaceRootURL,
            displayName: "RenameRaceWorkspace",
            rootNodes: [
                .file(
                    .init(
                        url: renamedURL,
                        displayName: "Localized Inbox Renamed.md",
                        subtitle: "Root document"
                    )
                )
            ],
            lastUpdated: PreviewSampleData.previewDate
        )
        let openDocument = OpenDocument(
            url: originalURL,
            workspaceRootURL: workspaceRootURL,
            relativePath: "Inbox.md",
            displayName: "Inbox.md",
            text: "# Inbox\n\nOriginal text.",
            loadedVersion: DocumentVersion(
                contentModificationDate: PreviewSampleData.previewDate,
                fileSize: 22,
                contentDigest: "rename-race-original"
            ),
            isDirty: false,
            saveState: .idle,
            conflictState: .none
        )
        let recentFilesStore = RecentFilesStore(
            initialItems: [
                RecentFileItem(
                    workspaceRootPath: workspaceRootURL.path,
                    relativePath: openDocument.relativePath,
                    displayName: openDocument.displayName,
                    lastOpenedAt: PreviewSampleData.previewDate
                ),
            ]
        )
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = staleRefreshSnapshot
        session.openDocument = openDocument
        session.path = [.editor(originalURL)]

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: SequencedRefreshWorkspaceManager(
                refreshResponses: [
                    .success(snapshot: staleRefreshSnapshot, delay: .milliseconds(180)),
                ],
                fallbackSnapshot: renamedSnapshot,
                renameResponse: .init(
                    result: WorkspaceMutationResult(
                        snapshot: renamedSnapshot,
                        outcome: .renamedFile(
                            oldURL: originalURL,
                            newURL: renamedURL,
                            displayName: "Localized Inbox Renamed.md",
                            relativePath: renamedRelativePath
                        )
                    ),
                    delay: .milliseconds(20)
                )
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        let refreshTask = Task {
            await coordinator.refreshWorkspace()
        }
        try? await Task.sleep(for: .milliseconds(30))
        let renameResult = await coordinator.renameFile(at: originalURL, to: "Inbox Renamed")
        let refreshResult = await refreshTask.value

        guard case .success = renameResult else {
            return XCTFail("Expected rename mutation to succeed.")
        }

        XCTAssertNil(refreshResult)
        XCTAssertEqual(session.workspaceSnapshot, renamedSnapshot)
        XCTAssertEqual(session.openDocument?.url, renamedURL)
        XCTAssertEqual(session.openDocument?.relativePath, renamedRelativePath)
        XCTAssertEqual(session.path, [.editor(renamedURL)])
        XCTAssertEqual(session.visibleEditorRelativePath, renamedRelativePath)
        XCTAssertNil(session.workspaceAlertError)
        XCTAssertEqual(recentFilesStore.items.map(\.displayName), ["Localized Inbox Renamed.md"])
        XCTAssertEqual(recentFilesStore.items.first?.relativePath, renamedRelativePath)
    }

    @MainActor
    func testRefreshRaceWithDeleteAppliesOnlyWinningMutationSnapshot() async {
        let deletedSnapshot = makeWorkspaceSnapshotRemovingRootFile(
            url: PreviewSampleData.cleanDocument.url
        )
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.editor(PreviewSampleData.cleanDocument.url)]

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: SequencedRefreshWorkspaceManager(
                refreshResponses: [
                    .success(snapshot: PreviewSampleData.nestedWorkspace, delay: .milliseconds(180)),
                ],
                fallbackSnapshot: deletedSnapshot,
                deleteResponse: .init(
                    result: WorkspaceMutationResult(
                        snapshot: deletedSnapshot,
                        outcome: .deletedFile(
                            url: PreviewSampleData.cleanDocument.url,
                            displayName: PreviewSampleData.cleanDocument.displayName
                        )
                    ),
                    delay: .milliseconds(20)
                )
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        let refreshTask = Task {
            await coordinator.refreshWorkspace()
        }
        try? await Task.sleep(for: .milliseconds(30))
        let deleteResult = await coordinator.deleteFile(at: PreviewSampleData.cleanDocument.url)
        let refreshResult = await refreshTask.value

        guard case .success = deleteResult else {
            return XCTFail("Expected delete mutation to succeed.")
        }

        XCTAssertNil(refreshResult)
        XCTAssertEqual(session.workspaceSnapshot, deletedSnapshot)
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertEqual(session.workspaceAlertError?.title, "Document Deleted")
    }

    @MainActor
    func testRefreshRaceWithCreateAppliesOnlyWinningMutationSnapshot() async {
        let createdFileURL = PreviewSampleData.workspaceRootURL.appending(path: "Fresh.md")
        let createdSnapshot = makeWorkspaceSnapshotAppendingRootFile(
            .file(
                .init(
                    url: createdFileURL,
                    displayName: "Fresh.md",
                    subtitle: "Root document"
                )
            )
        )
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: SequencedRefreshWorkspaceManager(
                refreshResponses: [
                    .success(snapshot: PreviewSampleData.nestedWorkspace, delay: .milliseconds(180)),
                ],
                fallbackSnapshot: createdSnapshot,
                createResponse: .init(
                    result: WorkspaceMutationResult(
                        snapshot: createdSnapshot,
                        outcome: .createdFile(
                            url: createdFileURL,
                            displayName: "Fresh.md"
                        )
                    ),
                    delay: .milliseconds(20)
                )
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        let refreshTask = Task {
            await coordinator.refreshWorkspace()
        }
        try? await Task.sleep(for: .milliseconds(30))
        let createResult = await coordinator.createFile(named: "Fresh.md", in: nil)
        let refreshResult = await refreshTask.value

        guard case .success = createResult else {
            return XCTFail("Expected create mutation to succeed.")
        }

        XCTAssertNil(refreshResult)
        XCTAssertEqual(session.workspaceSnapshot, createdSnapshot)
        XCTAssertTrue(
            session.workspaceSnapshot?.rootNodes.contains(where: { $0.url == createdFileURL }) == true
        )
    }

    @MainActor
    func testRefreshRaceWithCreateFolderAppliesOnlyWinningMutationSnapshot() async {
        let createdFolderURL = PreviewSampleData.workspaceRootURL.appending(path: "Archive")
        let createdSnapshot = makeWorkspaceSnapshotAppendingRootFile(
            .folder(
                .init(
                    url: createdFolderURL,
                    displayName: "Archive",
                    children: []
                )
            )
        )
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: SequencedRefreshWorkspaceManager(
                refreshResponses: [
                    .success(snapshot: PreviewSampleData.nestedWorkspace, delay: .milliseconds(180)),
                ],
                fallbackSnapshot: createdSnapshot,
                createFolderResponse: .init(
                    result: WorkspaceMutationResult(
                        snapshot: createdSnapshot,
                        outcome: .createdFolder(
                            url: createdFolderURL,
                            displayName: "Archive"
                        )
                    ),
                    delay: .milliseconds(20)
                )
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        let refreshTask = Task {
            await coordinator.refreshWorkspace()
        }
        try? await Task.sleep(for: .milliseconds(30))
        let createResult = await coordinator.createFolder(named: "Archive", in: nil)
        let refreshResult = await refreshTask.value

        guard case .success = createResult else {
            return XCTFail("Expected create folder mutation to succeed.")
        }

        XCTAssertNil(refreshResult)
        XCTAssertEqual(session.workspaceSnapshot, createdSnapshot)
        XCTAssertTrue(
            session.workspaceSnapshot?.rootNodes.contains(where: { $0.url == createdFolderURL }) == true
        )
    }

    @MainActor
    func testCancelledPullToRefreshResetsRefreshingStateAndAllowsRetry() async throws {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: SequencedRefreshWorkspaceManager(
                refreshResponses: [
                    .success(snapshot: PreviewSampleData.nestedWorkspace, delay: .seconds(1)),
                    .success(snapshot: PreviewSampleData.nestedWorkspace, delay: .milliseconds(20)),
                ],
                fallbackSnapshot: PreviewSampleData.nestedWorkspace
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

        let cancelledRefreshTask = Task {
            await workspaceViewModel.refreshFromPullToRefresh()
        }

        try await waitUntil {
            workspaceViewModel.isRefreshing
        }

        cancelledRefreshTask.cancel()
        await cancelledRefreshTask.value

        XCTAssertFalse(workspaceViewModel.isRefreshing)
        XCTAssertFalse(workspaceViewModel.isLoading)

        await workspaceViewModel.refreshFromPullToRefresh()

        XCTAssertFalse(workspaceViewModel.isRefreshing)
        XCTAssertFalse(workspaceViewModel.isLoading)
        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertNil(session.workspaceAlertError)
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
        XCTAssertNil(session.workspaceAlertError)
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
        XCTAssertNil(session.workspaceAlertError)
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
        XCTAssertNil(session.workspaceAlertError)
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
        XCTAssertNil(session.workspaceAlertError)
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
        XCTAssertNil(session.workspaceAlertError)
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
        XCTAssertNil(session.workspaceAlertError)
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
        session.path = [.editor(openDocument.url)]

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
        _ = await coordinator.renameFile(at: openDocument.url, to: "2026-04-13 Renamed")
        let renamedDocument = try XCTUnwrap(session.openDocument)
        let restorableSessionAfterRename = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.workspaceSnapshot, renamedSnapshot)
        XCTAssertEqual(session.path, [.editor(renamedURL)])
        XCTAssertEqual(renamedDocument.url, renamedURL)
        XCTAssertEqual(renamedDocument.relativePath, renamedRelativePath)
        XCTAssertEqual(renamedDocument.displayName, "2026-04-13 Renamed.md")
        XCTAssertEqual(renamedDocument.text, "# Monday\n\nUnsaved edits stay with the renamed file.")
        XCTAssertTrue(renamedDocument.isDirty)
        XCTAssertEqual(renamedDocument.saveState, .unsaved)
        XCTAssertEqual(restorableSessionAfterRename?.relativePath, renamedRelativePath)
        XCTAssertEqual(session.visibleEditorRelativePath, renamedRelativePath)

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
                                    .file(
                                        .init(
                                            url: renamedDocumentURL,
                                            displayName: "2026-04-13.md",
                                            subtitle: "Daily note"
                                        )
                                    ),
                                    .file(
                                        .init(
                                            url: renamedYearURL.appending(path: "Ideas.markdown"),
                                            displayName: "Ideas.markdown",
                                            subtitle: "Scratchpad"
                                        )
                                    ),
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

        XCTAssertEqual(
            session.path,
            [.trustedEditor(renamedDocumentURL, renamedRelativePath)]
        )
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
        XCTAssertEqual(session.workspaceAlertError?.title, "Document Deleted")
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
        XCTAssertEqual(session.workspaceAlertError?.title, "Delete File")
    }

    @MainActor
    func testDeletePendingEditorPresentationClearsStaleRouteAndShowsMessage() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.path = [.trustedEditor(
            PreviewSampleData.cleanDocument.url,
            PreviewSampleData.cleanDocument.relativePath
        )]
        session.pendingEditorPresentation = .init(
            routeURL: PreviewSampleData.cleanDocument.url,
            relativePath: PreviewSampleData.cleanDocument.relativePath
        )

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
        XCTAssertNil(session.pendingEditorPresentation)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.editorLoadError)
        XCTAssertNil(session.editorAlertError)
        XCTAssertEqual(session.workspaceAlertError?.title, "Document Deleted")
    }

    @MainActor
    func testDeletePreviouslyOpenedButUnselectedFileDoesNotShowDeletedPopup() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = []
        session.regularDetailSelection = .placeholder

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
        session.path = [.editor(originalDocument.url)]

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
        XCTAssertEqual(session.path, [.editor(renamedURL)])
    }

    @MainActor
    func testClearWorkspaceResetsAppStateAndNavigation() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: PreviewSampleData.nestedWorkspace.displayName)
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.editorLoadError = PreviewSampleData.failedLoadError
        session.editorAlertError = PreviewSampleData.failedLoadError
        session.path = [.settings, .editor(PreviewSampleData.cleanDocument.url)]
        session.workspaceAlertError = PreviewSampleData.saveFailedError

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
        XCTAssertNil(session.editorAlertError)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.workspaceAlertError)
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
        XCTAssertEqual(session.workspaceAlertError?.title, "Can’t Clear Workspace")
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
        session.workspaceAlertError = PreviewSampleData.saveFailedError

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
        XCTAssertNil(session.workspaceAlertError)
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
        XCTAssertNil(session.workspaceAlertError)
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
        XCTAssertNil(session.workspaceAlertError)
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
        XCTAssertNil(session.workspaceAlertError)
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
        XCTAssertNil(session.workspaceAlertError)
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
        XCTAssertEqual(session.workspaceAlertError, reconnectError)
    }

    @MainActor
    func testFailedWorkspaceReplacementDoesNotOverwriteStoredBookmark() async throws {
        let oldBookmark = StoredWorkspaceBookmark(
            workspaceName: PreviewSampleData.nestedWorkspace.displayName,
            lastKnownPath: PreviewSampleData.nestedWorkspace.rootURL.path,
            bookmarkData: Data("old-workspace-bookmark".utf8)
        )
        let bookmarkStore = StubBookmarkStore(initialBookmark: oldBookmark)
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
                workspaceEnumerator: FailingSmokeWorkspaceEnumerator(
                    error: AppError.workspaceRestoreFailed(
                        details: "The selected folder could not be loaded."
                    )
                )
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.handleFolderPickerResult(.success([URL(filePath: "/preview/BrokenWorkspace")]))
        let bookmark = try await bookmarkStore.loadBookmark()

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertEqual(session.openDocument?.url, PreviewSampleData.cleanDocument.url)
        XCTAssertEqual(session.path, [.settings])
        XCTAssertEqual(bookmark, oldBookmark)
        XCTAssertEqual(session.workspaceAlertError?.title, "Unable to Restore Workspace")
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
        XCTAssertNil(session.workspaceAlertError)
        XCTAssertNil(restoredSession)
    }

    @MainActor
    func testForegroundWorkspaceAccessLossTransitionsToReconnectAndClearsEditorState() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: PreviewSampleData.nestedWorkspace.displayName)
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.editor(PreviewSampleData.cleanDocument.url)]

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
        XCTAssertNil(session.workspaceAlertError)
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

        container.session.path = [.trustedEditor(result.url, result.relativePath)]
        editorViewModel.handleAppear(for: result.url)

        try await waitUntil {
            container.session.openDocument?.url == result.url
        }

        XCTAssertEqual(container.session.openDocument?.displayName, result.displayName)
        XCTAssertEqual(container.session.openDocument?.relativePath, result.relativePath)
        XCTAssertEqual(container.session.path, [.trustedEditor(result.url, result.relativePath)])
        XCTAssertNil(container.session.editorLoadError)
    }

    @MainActor
    func testBrowserRootFileOpenUsesTrustedRelativePathIdentity() async throws {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        let documentManager = RelativePathOnlyDocumentManager(
            documentsByRelativePath: [
                PreviewSampleData.cleanDocument.relativePath: PreviewSampleData.cleanDocument,
            ]
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: documentManager,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: RecentFilesStore(initialItems: [])
        )
        let editorViewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            autosaveDelay: .milliseconds(20)
        )

        workspaceViewModel.openDocument(
            relativePath: PreviewSampleData.cleanDocument.relativePath,
            preferredURL: PreviewSampleData.cleanDocument.url
        )
        let routedURL = try XCTUnwrap(session.path.last?.editorURL)
        editorViewModel.handleAppear(for: routedURL)

        try await waitUntil {
            session.openDocument?.relativePath == PreviewSampleData.cleanDocument.relativePath
        }

        let openedRelativePaths = await documentManager.recordedOpenedRelativePaths()
        let attemptedURLBasedOpenURLs = await documentManager.recordedURLBasedOpenAttempts()

        XCTAssertEqual(session.openDocument?.displayName, PreviewSampleData.cleanDocument.displayName)
        XCTAssertEqual(openedRelativePaths, [PreviewSampleData.cleanDocument.relativePath])
        XCTAssertTrue(attemptedURLBasedOpenURLs.isEmpty)
        XCTAssertNil(session.editorLoadError)
    }

    @MainActor
    func testBrowserNestedFileOpenUsesTrustedRelativePathIdentity() async throws {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        let nestedDocument = makePreviewReadmeDocument()
        let documentManager = RelativePathOnlyDocumentManager(
            documentsByRelativePath: [
                nestedDocument.relativePath: nestedDocument,
            ]
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: documentManager,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: RecentFilesStore(initialItems: [])
        )
        let editorViewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            autosaveDelay: .milliseconds(20)
        )

        workspaceViewModel.openDocument(
            relativePath: nestedDocument.relativePath,
            preferredURL: nestedDocument.url
        )
        let routedURL = try XCTUnwrap(session.path.last?.editorURL)
        editorViewModel.handleAppear(for: routedURL)

        try await waitUntil {
            session.openDocument?.relativePath == nestedDocument.relativePath
        }

        let openedRelativePaths = await documentManager.recordedOpenedRelativePaths()
        let attemptedURLBasedOpenURLs = await documentManager.recordedURLBasedOpenAttempts()

        XCTAssertEqual(session.openDocument?.displayName, nestedDocument.displayName)
        XCTAssertEqual(openedRelativePaths, [nestedDocument.relativePath])
        XCTAssertTrue(attemptedURLBasedOpenURLs.isEmpty)
        XCTAssertNil(session.editorLoadError)
    }

    @MainActor
    func testSearchResultOpenUsesTrustedRelativePathIdentity() async throws {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        let nestedDocument = makePreviewReadmeDocument()
        let documentManager = RelativePathOnlyDocumentManager(
            documentsByRelativePath: [
                nestedDocument.relativePath: nestedDocument,
            ]
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: documentManager,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: RecentFilesStore(initialItems: [])
        )
        let editorViewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            autosaveDelay: .milliseconds(20)
        )

        workspaceViewModel.searchQuery = "read"
        let result = try XCTUnwrap(workspaceViewModel.searchResults.first)

        workspaceViewModel.openSearchResult(result)
        let routedURL = try XCTUnwrap(session.path.last?.editorURL)
        editorViewModel.handleAppear(for: routedURL)

        try await waitUntil {
            session.openDocument?.relativePath == result.relativePath
        }

        let openedRelativePaths = await documentManager.recordedOpenedRelativePaths()
        let attemptedURLBasedOpenURLs = await documentManager.recordedURLBasedOpenAttempts()

        XCTAssertEqual(session.openDocument?.displayName, result.displayName)
        XCTAssertEqual(openedRelativePaths, [result.relativePath])
        XCTAssertTrue(attemptedURLBasedOpenURLs.isEmpty)
        XCTAssertNil(session.editorLoadError)
    }

    @MainActor
    func testTrustedRelativeBrowserOpenDoesNotBecomeNoOpBeforeDocumentLoad() {
        let container = AppContainer.preview(
            launchState: .workspaceReady,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            snapshot: PreviewSampleData.nestedWorkspace
        )

        container.workspaceViewModel.openDocument(
            relativePath: PreviewSampleData.cleanDocument.relativePath,
            preferredURL: PreviewSampleData.cleanDocument.url
        )

        XCTAssertEqual(
            container.session.path,
            [.trustedEditor(
                PreviewSampleData.cleanDocument.url,
                PreviewSampleData.cleanDocument.relativePath
            )]
        )
        XCTAssertEqual(
            container.session.visibleEditorRelativePath,
            PreviewSampleData.cleanDocument.relativePath
        )
    }

    @MainActor
    func testTrustedCompactRouteShowsOpenedDocumentWhenResolvedURLDiffersFromRouteURL() async throws {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        let preferredRouteURL = URL(
            filePath: "\(PreviewSampleData.workspaceRootURL.path)/References/../Inbox.md"
        )
        XCTAssertNotEqual(preferredRouteURL, PreviewSampleData.cleanDocument.url)

        let documentManager = RelativePathOnlyDocumentManager(
            documentsByRelativePath: [
                PreviewSampleData.cleanDocument.relativePath: PreviewSampleData.cleanDocument,
            ]
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: documentManager,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: RecentFilesStore(initialItems: [])
        )
        let editorViewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            autosaveDelay: .milliseconds(20)
        )

        workspaceViewModel.openDocument(
            relativePath: PreviewSampleData.cleanDocument.relativePath,
            preferredURL: preferredRouteURL
        )

        let routedURL = try XCTUnwrap(session.path.last?.editorURL)
        XCTAssertEqual(routedURL, preferredRouteURL)

        editorViewModel.handleAppear(for: routedURL)

        try await waitUntil {
            editorViewModel.currentRouteDocument?.relativePath == PreviewSampleData.cleanDocument.relativePath
        }

        XCTAssertEqual(session.openDocument?.url, PreviewSampleData.cleanDocument.url)
        XCTAssertEqual(
            editorViewModel.currentRouteDocument?.relativePath,
            PreviewSampleData.cleanDocument.relativePath
        )
        XCTAssertNil(session.editorLoadError)
    }

    @MainActor
    func testRegularTreeOpenUsesTrustedRelativeIdentity() async throws {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        let document = makePreviewReadmeDocument()
        let preferredRouteURL = URL(
            filePath: "\(PreviewSampleData.workspaceRootURL.path)/References/../References/README.md"
        )
        XCTAssertNotEqual(preferredRouteURL, document.url)

        let documentManager = RelativePathOnlyDocumentManager(
            documentsByRelativePath: [
                document.relativePath: document,
            ]
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: documentManager,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: RecentFilesStore(initialItems: [])
        )
        let editorViewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            autosaveDelay: .milliseconds(20)
        )

        coordinator.updateNavigationLayout(WorkspaceNavigationLayout.regular)
        workspaceViewModel.openDocument(
            relativePath: document.relativePath,
            preferredURL: preferredRouteURL
        )

        let detailURL = try XCTUnwrap(session.regularWorkspaceDetail.editorURL)
        XCTAssertEqual(detailURL, preferredRouteURL)

        editorViewModel.handleAppear(for: detailURL)

        try await waitUntil {
            session.openDocument?.relativePath == document.relativePath
        }

        let openedRelativePaths = await documentManager.recordedOpenedRelativePaths()
        let attemptedURLBasedOpenURLs = await documentManager.recordedURLBasedOpenAttempts()

        XCTAssertEqual(session.openDocument?.displayName, document.displayName)
        XCTAssertEqual(openedRelativePaths, [document.relativePath])
        XCTAssertTrue(attemptedURLBasedOpenURLs.isEmpty)
        XCTAssertNil(session.editorLoadError)
    }

    @MainActor
    func testRegularPendingEditorLoadUsesRelativeIdentityWhenResolvedDetailURLDiffersFromPreferredRouteURL() async throws {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        let document = makePreviewReadmeDocument()
        let preferredRouteURL = URL(
            filePath: "\(PreviewSampleData.workspaceRootURL.path)/References/../References/README.md"
        )
        let resolvedDetailURL = document.url
        XCTAssertNotEqual(preferredRouteURL, resolvedDetailURL)

        let documentManager = RelativePathOnlyDocumentManager(
            documentsByRelativePath: [
                document.relativePath: document,
            ]
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: documentManager,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        coordinator.updateNavigationLayout(WorkspaceNavigationLayout.regular)
        session.pendingEditorPresentation = .init(
            routeURL: preferredRouteURL,
            relativePath: document.relativePath
        )
        session.regularDetailSelection = .editor(document.relativePath)

        let result = await coordinator.loadDocument(at: resolvedDetailURL)

        guard case let .success(openedDocument) = result else {
            return XCTFail("Expected trusted relative-path open to succeed.")
        }

        let openedRelativePaths = await documentManager.recordedOpenedRelativePaths()
        let attemptedURLBasedOpenURLs = await documentManager.recordedURLBasedOpenAttempts()

        XCTAssertEqual(openedDocument.relativePath, document.relativePath)
        XCTAssertEqual(openedRelativePaths, [document.relativePath])
        XCTAssertTrue(attemptedURLBasedOpenURLs.isEmpty)
    }

    @MainActor
    func testWorkspaceViewModelProgrammaticFileOpenUsesOnlyEditorRoute() {
        let container = AppContainer.preview(
            launchState: .workspaceReady,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            snapshot: PreviewSampleData.nestedWorkspace
        )
        let workspaceViewModel = container.workspaceViewModel

        workspaceViewModel.openDocument(
            relativePath: PreviewSampleData.cleanDocument.relativePath,
            preferredURL: PreviewSampleData.cleanDocument.url
        )

        XCTAssertEqual(
            container.session.path,
            [.trustedEditor(
                PreviewSampleData.cleanDocument.url,
                PreviewSampleData.cleanDocument.relativePath
            )]
        )
    }

    @MainActor
    func testRegularWorkspaceDetailBecomesEditorWhenTreeSelectionOpensFile() {
        let container = AppContainer.preview(
            launchState: .workspaceReady,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            snapshot: PreviewSampleData.nestedWorkspace
        )
        container.coordinator.updateNavigationLayout(.regular)

        container.workspaceViewModel.openDocument(PreviewSampleData.cleanDocument.url)

        XCTAssertEqual(
            container.session.regularWorkspaceDetail,
            .editor(PreviewSampleData.cleanDocument.url)
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
    func testRecentFileOpenedFromSecondarySurfaceUsesTrustedRelativePathIdentity() async throws {
        let workspaceURL = try makeTemporaryWorkspace(named: "RecentFileWorkspace")
        defer { removeItemIfPresent(at: workspaceURL) }
        let canonicalFileURL = try createFile(
            named: "Inbox.md",
            contents: PreviewSampleData.cleanDocument.text,
            in: workspaceURL
        )
        let snapshot = WorkspaceSnapshot(
            rootURL: workspaceURL,
            displayName: "Recent File Workspace",
            rootNodes: [
                .file(
                    .init(
                        url: canonicalFileURL,
                        displayName: "Inbox.md",
                        subtitle: "Root document"
                    )
                ),
            ],
            lastUpdated: PreviewSampleData.previewDate
        )
        let document = OpenDocument(
            url: canonicalFileURL,
            workspaceRootURL: workspaceURL,
            relativePath: "Inbox.md",
            displayName: "Inbox.md",
            text: PreviewSampleData.cleanDocument.text,
            loadedVersion: PreviewSampleData.cleanDocument.loadedVersion,
            isDirty: false,
            saveState: .idle,
            conflictState: .none
        )
        let recentItem = RecentFileItem(
            workspaceID: snapshot.workspaceID,
            workspaceRootPath: workspaceURL.path,
            relativePath: document.relativePath,
            displayName: document.displayName,
            lastOpenedAt: PreviewSampleData.previewDate
        )
        let recentFilesStore = RecentFilesStore(initialItems: [recentItem])
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: snapshot.displayName)
        session.workspaceSnapshot = snapshot
        let documentManager = RelativePathOnlyDocumentManager(
            documentsByRelativePath: [document.relativePath: document]
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: snapshot
            ),
            documentManager: documentManager,
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: recentFilesStore
        )
        let editorViewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            autosaveDelay: .milliseconds(20)
        )
        let item = try XCTUnwrap(workspaceViewModel.recentFiles.first)

        workspaceViewModel.presentRecentFiles()
        XCTAssertTrue(workspaceViewModel.isShowingRecentFiles)

        workspaceViewModel.openRecentFile(item)
        XCTAssertFalse(workspaceViewModel.isShowingRecentFiles)
        XCTAssertEqual(session.path, [.trustedEditor(canonicalFileURL, document.relativePath)])

        let resolvedURL = try XCTUnwrap(session.path.last?.editorURL)
        editorViewModel.handleAppear(for: resolvedURL)

        try await waitUntil {
            session.openDocument?.relativePath == document.relativePath
        }

        let openedRelativePaths = await documentManager.recordedOpenedRelativePaths()
        let attemptedURLBasedOpenURLs = await documentManager.recordedURLBasedOpenAttempts()

        XCTAssertEqual(session.openDocument?.url, canonicalFileURL)
        XCTAssertEqual(session.openDocument?.relativePath, document.relativePath)
        XCTAssertEqual(
            session.path,
            [.trustedEditor(canonicalFileURL, document.relativePath)]
        )
        XCTAssertEqual(openedRelativePaths, [document.relativePath])
        XCTAssertTrue(attemptedURLBasedOpenURLs.isEmpty)
        XCTAssertNil(session.editorLoadError)
    }

    @MainActor
    func testStaleRecentFileOpenRemovesEntryAndShowsRecentSpecificError() async throws {
        let workspaceURL = try makeTemporaryWorkspace(named: "StaleRecentWorkspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let snapshot = WorkspaceSnapshot(
            rootURL: workspaceURL,
            displayName: "Stale Recent Workspace",
            rootNodes: [],
            lastUpdated: PreviewSampleData.previewDate
        )
        let staleItem = RecentFileItem(
            workspaceID: snapshot.workspaceID,
            workspaceRootPath: workspaceURL.path,
            relativePath: "Missing.md",
            displayName: "Missing.md",
            lastOpenedAt: PreviewSampleData.previewDate
        )
        let recentFilesStore = RecentFilesStore(initialItems: [staleItem])
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: snapshot.displayName)
        session.workspaceSnapshot = snapshot
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: snapshot
            ),
            documentManager: RelativePathOnlyDocumentManager(documentsByRelativePath: [:]),
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: recentFilesStore
        )
        let editorViewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            autosaveDelay: .milliseconds(20)
        )

        let item = try XCTUnwrap(workspaceViewModel.recentFiles.first)
        workspaceViewModel.openRecentFile(item)

        let routedURL = try XCTUnwrap(session.path.last?.editorURL)
        editorViewModel.handleAppear(for: routedURL)

        try await waitUntil {
            session.editorLoadError?.title == "Recent File Unavailable"
        }

        XCTAssertTrue(recentFilesStore.items.isEmpty)
        XCTAssertEqual(session.editorLoadError?.title, "Recent File Unavailable")
        XCTAssertEqual(
            session.editorLoadError?.recoverySuggestion,
            "It was removed from Recent Files. Choose another file from the browser."
        )
    }

    @MainActor
    func testRemovingRecentFileFromSheetOnlyRemovesCurrentWorkspaceEntry() {
        let snapshot = PreviewSampleData.nestedWorkspace
        let currentWorkspaceItem = RecentFileItem(
            workspaceID: snapshot.workspaceID,
            workspaceRootPath: snapshot.rootURL.path,
            relativePath: "References/README.md",
            displayName: "README.md",
            lastOpenedAt: PreviewSampleData.previewDate
        )
        let otherWorkspaceItem = RecentFileItem(
            workspaceRootPath: "/preview/OtherWorkspace",
            relativePath: "Elsewhere.md",
            displayName: "Elsewhere.md",
            lastOpenedAt: PreviewSampleData.previewDate.addingTimeInterval(-60)
        )
        let recentFilesStore = RecentFilesStore(
            initialItems: [currentWorkspaceItem, otherWorkspaceItem]
        )
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: snapshot.displayName)
        session.workspaceSnapshot = snapshot
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: AppCoordinator(
                session: session,
                workspaceManager: StubWorkspaceManager(
                    bookmarkStore: StubBookmarkStore(),
                    readySnapshot: snapshot
                ),
                documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
                recentFilesStore: recentFilesStore,
                errorReporter: DefaultErrorReporter(logger: DebugLogger()),
                folderPickerBridge: StubFolderPickerBridge(),
                logger: DebugLogger()
            ),
            recentFilesStore: recentFilesStore
        )

        workspaceViewModel.removeRecentFiles(at: IndexSet(integer: 0))

        XCTAssertTrue(workspaceViewModel.recentFiles.isEmpty)
        XCTAssertEqual(recentFilesStore.items.map(\.displayName), ["Elsewhere.md"])
    }

    @MainActor
    func testRestoreMovedWorkspacePreservesLegacyRecentFilesThroughStableWorkspaceIdentity() async {
        let workspaceID = "workspace-stable-id"
        let oldWorkspaceURL = URL(filePath: "/preview/OriginalWorkspace")
        let movedWorkspaceURL = URL(filePath: "/preview/MovedWorkspace")
        let bookmarkStore = StubBookmarkStore(
            initialBookmark: StoredWorkspaceBookmark(
                workspaceName: "Moved Workspace",
                lastKnownPath: oldWorkspaceURL.path,
                bookmarkData: Data("workspace-bookmark".utf8),
                workspaceID: workspaceID
            )
        )
        let session = AppSession()
        let recentFilesStore = RecentFilesStore(
            initialItems: [
                RecentFileItem(
                    workspaceRootPath: oldWorkspaceURL.path,
                    relativePath: PreviewSampleData.cleanDocument.relativePath,
                    displayName: PreviewSampleData.cleanDocument.displayName,
                    lastOpenedAt: PreviewSampleData.previewDate
                ),
            ]
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: LiveWorkspaceManager(
                bookmarkStore: bookmarkStore,
                securityScopedAccess: RestoringSmokeSecurityScopedAccessHandler(
                    resolvedBookmarks: [
                        Data("workspace-bookmark".utf8): ResolvedSecurityScopedURL(
                            url: movedWorkspaceURL,
                            displayName: "Moved Workspace",
                            isStale: false
                        )
                    ]
                ),
                workspaceEnumerator: StubWorkspaceEnumerator(snapshot: PreviewSampleData.nestedWorkspace)
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: recentFilesStore
        )

        await coordinator.bootstrapIfNeeded()
        let recentFiles = workspaceViewModel.recentFiles

        XCTAssertEqual(session.workspaceSnapshot?.rootURL, movedWorkspaceURL)
        XCTAssertEqual(session.workspaceSnapshot?.workspaceID, workspaceID)
        XCTAssertEqual(recentFiles.map { $0.displayName }, ["Inbox.md"])
        XCTAssertEqual(recentFilesStore.items.first?.workspaceID, workspaceID)
        XCTAssertEqual(recentFilesStore.items.first?.workspaceRootPath, movedWorkspaceURL.path)
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
    private func makeWorkspaceSnapshotRenamingJournalFolder(to folderName: String) -> WorkspaceSnapshot {
        let renamedFolderURL = PreviewSampleData.workspaceRootURL.appending(path: folderName)
        let renamedYearURL = renamedFolderURL.appending(path: "2026")

        return makeWorkspaceSnapshotReplacingFile(
            oldURL: PreviewSampleData.journalURL,
            with: .folder(
                .init(
                    url: renamedFolderURL,
                    displayName: folderName,
                    children: [
                        .folder(
                            .init(
                                url: renamedYearURL,
                                displayName: "2026",
                                children: [
                                    .file(
                                        .init(
                                            url: renamedYearURL.appending(path: "2026-04-13.md"),
                                            displayName: "2026-04-13.md",
                                            subtitle: "Daily note"
                                        )
                                    ),
                                    .file(
                                        .init(
                                            url: renamedYearURL.appending(path: "Ideas.markdown"),
                                            displayName: "Ideas.markdown",
                                            subtitle: "Scratchpad"
                                        )
                                    ),
                                ]
                            )
                        ),
                    ]
                )
            )
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
    private func makeWorkspaceSnapshotAppendingRootFile(_ node: WorkspaceNode) -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            rootURL: PreviewSampleData.nestedWorkspace.rootURL,
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            rootNodes: PreviewSampleData.nestedWorkspace.rootNodes + [node],
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

    private func makeTemporaryWorkspace(named name: String) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "MarkdownWorkspaceAppSmokeTests")
            .appending(path: UUID().uuidString)
            .appending(path: name)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func createFile(
        named name: String,
        contents: String,
        in parentURL: URL
    ) throws -> URL {
        let fileURL = parentURL.appending(path: name)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func removeItemIfPresent(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    private func makePreviewReadmeDocument() -> OpenDocument {
        OpenDocument(
            url: PreviewSampleData.readmeDocumentURL,
            workspaceRootURL: PreviewSampleData.workspaceRootURL,
            relativePath: "References/README.md",
            displayName: "README.md",
            text: """
            # README

            Snapshot-backed open.
            """,
            loadedVersion: PreviewSampleData.cleanDocument.loadedVersion,
            isDirty: false,
            saveState: .saved(PreviewSampleData.previewDate),
            conflictState: .none
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

private struct FailingSmokeWorkspaceEnumerator: WorkspaceEnumerating {
    let error: AppError

    nonisolated func makeSnapshot(rootURL: URL, displayName: String) throws -> WorkspaceSnapshot {
        throw error
    }
}

private struct RestoringSmokeSecurityScopedAccessHandler: SecurityScopedAccessHandling {
    let resolvedBookmarks: [Data: ResolvedSecurityScopedURL]

    func makeBookmark(for url: URL) throws -> Data {
        Data(url.path.utf8)
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedSecurityScopedURL {
        resolvedBookmarks[data] ?? ResolvedSecurityScopedURL(
            url: URL(filePath: "/tmp"),
            displayName: "tmp",
            isStale: false
        )
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
        guard let url = WorkspaceRelativePath.resolveCandidate(relativePath, within: workspaceRootURL) else {
            throw AppError.documentUnavailable(
                name: relativePath.split(separator: "/").last.map(String.init) ?? "Document"
            )
        }

        return try operation(url)
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

private actor RelativePathOnlyDocumentManager: DocumentManager {
    let documentsByRelativePath: [String: OpenDocument]
    private(set) var openedRelativePaths: [String] = []
    private(set) var attemptedURLBasedOpenURLs: [URL] = []

    init(documentsByRelativePath: [String: OpenDocument]) {
        self.documentsByRelativePath = documentsByRelativePath
    }

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument {
        attemptedURLBasedOpenURLs.append(url)
        throw AppError.documentUnavailable(name: url.lastPathComponent)
    }

    func openDocument(
        atRelativePath relativePath: String,
        in workspaceRootURL: URL
    ) async throws -> OpenDocument {
        openedRelativePaths.append(relativePath)

        guard let document = documentsByRelativePath[relativePath] else {
            throw AppError.documentUnavailable(
                name: relativePath.split(separator: "/").last.map(String.init) ?? "Document"
            )
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
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func relocateDocumentSession(
        for document: OpenDocument,
        to url: URL,
        relativePath: String
    ) async {}

    func recordedOpenedRelativePaths() -> [String] {
        openedRelativePaths
    }

    func recordedURLBasedOpenAttempts() -> [URL] {
        attemptedURLBasedOpenURLs
    }
}

private struct RelocatedDocumentSession: Equatable, Sendable {
    let fromRelativePath: String
    let toURL: URL
    let toRelativePath: String
}

private enum SequencedWorkspaceRefreshResponse: Sendable {
    case success(snapshot: WorkspaceSnapshot, delay: Duration)
    case failure(error: AppError, delay: Duration)
}

private struct SequencedWorkspaceMutationResponse: Sendable {
    let result: WorkspaceMutationResult
    let delay: Duration
}

private actor SequencedRefreshWorkspaceManager: WorkspaceManager {
    private var refreshResponses: [SequencedWorkspaceRefreshResponse]
    private let fallbackSnapshot: WorkspaceSnapshot
    private let createResponse: SequencedWorkspaceMutationResponse?
    private let createFolderResponse: SequencedWorkspaceMutationResponse?
    private let renameResponse: SequencedWorkspaceMutationResponse?
    private let deleteResponse: SequencedWorkspaceMutationResponse?

    init(
        refreshResponses: [SequencedWorkspaceRefreshResponse],
        fallbackSnapshot: WorkspaceSnapshot,
        createResponse: SequencedWorkspaceMutationResponse? = nil,
        createFolderResponse: SequencedWorkspaceMutationResponse? = nil,
        renameResponse: SequencedWorkspaceMutationResponse? = nil,
        deleteResponse: SequencedWorkspaceMutationResponse? = nil
    ) {
        self.refreshResponses = refreshResponses
        self.fallbackSnapshot = fallbackSnapshot
        self.createResponse = createResponse
        self.createFolderResponse = createFolderResponse
        self.renameResponse = renameResponse
        self.deleteResponse = deleteResponse
    }

    func restoreWorkspace() async -> WorkspaceRestoreResult {
        .ready(fallbackSnapshot)
    }

    func selectWorkspace(at url: URL) async -> WorkspaceRestoreResult {
        .ready(fallbackSnapshot)
    }

    func refreshCurrentWorkspace() async throws -> WorkspaceSnapshot {
        let response = refreshResponses.isEmpty == false
            ? refreshResponses.removeFirst()
            : .success(snapshot: fallbackSnapshot, delay: .zero)

        switch response {
        case let .success(snapshot, delay):
            try await Task.sleep(for: delay)
            return snapshot
        case let .failure(error, delay):
            try await Task.sleep(for: delay)
            throw error
        }
    }

    func createFile(named proposedName: String, in folderURL: URL?) async throws -> WorkspaceMutationResult {
        if let createResponse {
            try await Task.sleep(for: createResponse.delay)
            return createResponse.result
        }

        return WorkspaceMutationResult(
            snapshot: fallbackSnapshot,
            outcome: .createdFile(
                url: (folderURL ?? fallbackSnapshot.rootURL).appending(path: proposedName),
                displayName: proposedName
            )
        )
    }

    func createFolder(named proposedName: String, in folderURL: URL?) async throws -> WorkspaceMutationResult {
        if let createFolderResponse {
            try await Task.sleep(for: createFolderResponse.delay)
            return createFolderResponse.result
        }

        return WorkspaceMutationResult(
            snapshot: fallbackSnapshot,
            outcome: .createdFolder(
                url: (folderURL ?? fallbackSnapshot.rootURL).appending(path: proposedName),
                displayName: proposedName
            )
        )
    }

    func renameFile(at url: URL, to proposedName: String) async throws -> WorkspaceMutationResult {
        if let renameResponse {
            try await Task.sleep(for: renameResponse.delay)
            return renameResponse.result
        }

        return WorkspaceMutationResult(
            snapshot: fallbackSnapshot,
            outcome: .renamedFile(
                oldURL: url,
                newURL: url.deletingLastPathComponent().appending(path: proposedName),
                displayName: proposedName,
                relativePath: proposedName
            )
        )
    }

    func deleteFile(at url: URL) async throws -> WorkspaceMutationResult {
        if let deleteResponse {
            try await Task.sleep(for: deleteResponse.delay)
            return deleteResponse.result
        }

        return WorkspaceMutationResult(
            snapshot: fallbackSnapshot,
            outcome: .deletedFile(url: url, displayName: url.lastPathComponent)
        )
    }

    func clearWorkspaceSelection() async throws {}
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

    func createFolder(named proposedName: String, in folderURL: URL?) async throws -> WorkspaceMutationResult {
        WorkspaceMutationResult(
            snapshot: refreshSnapshot,
            outcome: .createdFolder(
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
