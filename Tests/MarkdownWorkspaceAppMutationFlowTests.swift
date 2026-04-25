import XCTest
@testable import Downward

final class MarkdownWorkspaceAppMutationFlowTests: MarkdownWorkspaceAppTestCase {
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

        let refreshedSnapshot = makeWorkspaceSnapshotRemovingRootFile(url: PreviewSampleData.cleanDocument.url)
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(refreshSnapshot: refreshedSnapshot),
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
            workspaceManager: MutationTestingWorkspaceManager(refreshSnapshot: refreshedSnapshot),
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

        let olderRefreshTask = Task { await coordinator.refreshWorkspace() }
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
        XCTAssertEqual(session.path, trustedEditorPath(for: PreviewSampleData.cleanDocument))
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

        let foregroundTask = Task { await coordinator.handleSceneDidBecomeActive() }
        try? await Task.sleep(for: .milliseconds(30))
        await workspaceViewModel.refreshFromPullToRefresh()
        await foregroundTask.value

        XCTAssertEqual(session.workspaceSnapshot, newerSnapshot)
        XCTAssertEqual(session.openDocument?.url, PreviewSampleData.cleanDocument.url)
        XCTAssertEqual(session.path, trustedEditorPath(for: PreviewSampleData.cleanDocument))
        XCTAssertEqual(recentFilesStore.items.map(\.displayName), ["Inbox.md"])
        XCTAssertNil(session.workspaceAlertError)
        XCTAssertFalse(workspaceViewModel.isRefreshing)
    }

    @MainActor
    func testRefreshRaceWithRenameAppliesOnlyWinningMutationSnapshotAndReconciliation() async {
        let workspaceRootURL = try! makeTemporaryWorkspace(named: "RenameRaceWorkspace")
        defer { removeItemIfPresent(at: workspaceRootURL) }

        let originalURL = try! createFile(named: "Inbox.md", contents: "# Inbox\n\nOriginal text.", in: workspaceRootURL)
        let renamedURL = try! createFile(named: "Inbox Renamed.md", contents: "# Inbox\n\nRenamed text.", in: workspaceRootURL)
        let renamedRelativePath = "Inbox Renamed.md"
        let staleRefreshSnapshot = WorkspaceSnapshot(
            rootURL: workspaceRootURL,
            displayName: "RenameRaceWorkspace",
            rootNodes: [.file(.init(url: originalURL, displayName: "Inbox.md", subtitle: "Root document"))],
            lastUpdated: PreviewSampleData.previewDate
        )
        let renamedSnapshot = WorkspaceSnapshot(
            rootURL: workspaceRootURL,
            displayName: "RenameRaceWorkspace",
            rootNodes: [.file(.init(url: renamedURL, displayName: "Localized Inbox Renamed.md", subtitle: "Root document"))],
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

        let refreshTask = Task { await coordinator.refreshWorkspace() }
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
        let deletedSnapshot = makeWorkspaceSnapshotRemovingRootFile(url: PreviewSampleData.cleanDocument.url)
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

        let refreshTask = Task { await coordinator.refreshWorkspace() }
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
            .file(.init(url: createdFileURL, displayName: "Fresh.md", subtitle: "Root document"))
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
                        outcome: .createdFile(url: createdFileURL, displayName: "Fresh.md")
                    ),
                    delay: .milliseconds(20)
                )
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        let refreshTask = Task { await coordinator.refreshWorkspace() }
        try? await Task.sleep(for: .milliseconds(30))
        let createResult = await coordinator.createFile(named: "Fresh.md", in: nil)
        let refreshResult = await refreshTask.value

        guard case .success = createResult else {
            return XCTFail("Expected create mutation to succeed.")
        }

        XCTAssertNil(refreshResult)
        XCTAssertEqual(session.workspaceSnapshot, createdSnapshot)
        XCTAssertTrue(session.workspaceSnapshot?.rootNodes.contains(where: { $0.url == createdFileURL }) == true)
    }

    @MainActor
    func testRefreshRaceWithCreateFolderAppliesOnlyWinningMutationSnapshot() async {
        let createdFolderURL = PreviewSampleData.workspaceRootURL.appending(path: "Archive")
        let createdSnapshot = makeWorkspaceSnapshotAppendingRootFile(
            .folder(.init(url: createdFolderURL, displayName: "Archive", children: []))
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
                        outcome: .createdFolder(url: createdFolderURL, displayName: "Archive")
                    ),
                    delay: .milliseconds(20)
                )
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        let refreshTask = Task { await coordinator.refreshWorkspace() }
        try? await Task.sleep(for: .milliseconds(30))
        let createResult = await coordinator.createFolder(named: "Archive", in: nil)
        let refreshResult = await refreshTask.value

        guard case .success = createResult else {
            return XCTFail("Expected create folder mutation to succeed.")
        }

        XCTAssertNil(refreshResult)
        XCTAssertEqual(session.workspaceSnapshot, createdSnapshot)
        XCTAssertTrue(session.workspaceSnapshot?.rootNodes.contains(where: { $0.url == createdFolderURL }) == true)
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

        let cancelledRefreshTask = Task { await workspaceViewModel.refreshFromPullToRefresh() }
        try await waitUntil { workspaceViewModel.isRefreshing }
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
            workspaceManager: MutationTestingWorkspaceManager(refreshSnapshot: PreviewSampleData.nestedWorkspace),
            documentManager: DelayedRevalidationDocumentManager(
                revalidatedDocument: revalidatedOriginalDocument,
                revalidationDelay: .milliseconds(150)
            ),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        let foregroundTask = Task { await coordinator.handleSceneDidBecomeActive() }
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
    func testPullToRefreshWhileSearchIsActiveRerunsFilterAndKeepsOpenDocumentState() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.editor(PreviewSampleData.cleanDocument.url)]

        let refreshedSnapshot = makeWorkspaceSnapshotRemovingFile(url: PreviewSampleData.readmeDocumentURL)
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(refreshSnapshot: refreshedSnapshot),
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
        XCTAssertEqual(session.path, trustedEditorPath(for: PreviewSampleData.cleanDocument))
        XCTAssertNil(session.editorLoadError)
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
            with: .file(.init(url: renamedURL, displayName: "Renamed.md", subtitle: "Root document"))
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
    func testMoveFolderContainingOpenDocumentUpdatesEditorStateAndRecents() async throws {
        let movedFolderURL = PreviewSampleData.archiveURL.appending(path: "Journal")
        let movedYearURL = movedFolderURL.appending(path: "2026")
        let movedDocumentURL = movedYearURL.appending(path: "2026-04-13.md")
        let movedRelativePath = "Archive/Journal/2026/2026-04-13.md"
        let movedSnapshot = makeWorkspaceSnapshotMovingJournalFolder(to: movedFolderURL)
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
                refreshSnapshot: movedSnapshot,
                renameOutcome: .renamedFolder(
                    oldURL: PreviewSampleData.journalURL,
                    newURL: movedFolderURL,
                    displayName: "Journal",
                    relativePath: "Archive/Journal"
                )
            ),
            documentManager: documentManager,
            sessionStore: sessionStore,
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.moveItem(
            at: PreviewSampleData.journalURL,
            toFolder: PreviewSampleData.archiveURL
        )
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()
        let relocatedInputs = await documentManager.relocatedInputs

        XCTAssertEqual(session.workspaceSnapshot, movedSnapshot)
        XCTAssertEqual(session.openDocument?.url, movedDocumentURL)
        XCTAssertEqual(session.openDocument?.relativePath, movedRelativePath)
        XCTAssertEqual(session.path, [.editor(movedDocumentURL)])
        XCTAssertEqual(session.visibleEditorRelativePath, movedRelativePath)
        XCTAssertEqual(restoredSession?.relativePath, movedRelativePath)
        XCTAssertEqual(relocatedInputs.map(\.toURL), [movedDocumentURL])
        XCTAssertEqual(relocatedInputs.map(\.toRelativePath), [movedRelativePath])
        XCTAssertEqual(recentFilesStore.items.map(\.relativePath), [movedRelativePath])
        XCTAssertNil(movedSnapshot.fileURL(forRelativePath: PreviewSampleData.dirtyDocument.relativePath))
        XCTAssertEqual(movedSnapshot.fileURL(forRelativePath: movedRelativePath), movedDocumentURL)
    }

    @MainActor
    func testDeleteActiveOpenDocumentClosesEditorAndShowsExplicitMessage() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.editor(PreviewSampleData.cleanDocument.url)]

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
        XCTAssertEqual(session.path, [])
        XCTAssertEqual(session.workspaceAlertError?.title, "Document Deleted")
    }

    @MainActor
    func testDeleteAncestorFolderOfOpenDocumentClosesEditorClearsRestoreStateAndRecents() async throws {
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

        let deletedSnapshot = makeWorkspaceSnapshotRemovingFile(url: PreviewSampleData.year2026URL)
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: deletedSnapshot,
                deleteOutcome: .deletedFolder(
                    url: PreviewSampleData.year2026URL,
                    displayName: "2026"
                )
            ),
            documentManager: MutationTrackingDocumentManager(),
            sessionStore: sessionStore,
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.deleteFile(at: PreviewSampleData.year2026URL)
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.workspaceSnapshot, deletedSnapshot)
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertEqual(session.workspaceAlertError?.title, "Document Deleted")
        XCTAssertNil(restoredSession)
        XCTAssertTrue(recentFilesStore.items.isEmpty)
        XCTAssertFalse(deletedSnapshot.containsFile(relativePath: PreviewSampleData.dirtyDocument.relativePath))
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
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.editorLoadError)
        XCTAssertNil(session.editorAlertError)
        XCTAssertEqual(session.workspaceAlertError?.title, "Document Deleted")
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

        let workspaceManager = MutationTestingWorkspaceManager(refreshSnapshot: PreviewSampleData.nestedWorkspace)
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
    private func makeWorkspaceSnapshotMovingJournalFolder(to folderURL: URL) -> WorkspaceSnapshot {
        let movedYearURL = folderURL.appending(path: "2026")

        return WorkspaceSnapshot(
            rootURL: PreviewSampleData.workspaceRootURL,
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            rootNodes: [
                .folder(
                    .init(
                        url: PreviewSampleData.referencesURL,
                        displayName: "References",
                        children: [
                            .file(
                                .init(
                                    url: PreviewSampleData.readmeDocumentURL,
                                    displayName: "README.md",
                                    subtitle: "Project overview"
                                )
                            ),
                        ]
                    )
                ),
                .folder(
                    .init(
                        url: PreviewSampleData.archiveURL,
                        displayName: "Archive",
                        children: [
                            .folder(
                                .init(
                                    url: folderURL,
                                    displayName: "Journal",
                                    children: [
                                        .folder(
                                            .init(
                                                url: movedYearURL,
                                                displayName: "2026",
                                                children: [
                                                    .file(
                                                        .init(
                                                            url: movedYearURL.appending(path: "2026-04-13.md"),
                                                            displayName: "2026-04-13.md",
                                                            subtitle: "Daily note"
                                                        )
                                                    ),
                                                    .file(
                                                        .init(
                                                            url: movedYearURL.appending(path: "Ideas.markdown"),
                                                            displayName: "Ideas.markdown",
                                                            subtitle: "Scratchpad"
                                                        )
                                                    ),
                                                ]
                                            )
                                        ),
                                    ]
                                )
                            ),
                        ]
                    )
                ),
                .file(
                    .init(
                        url: PreviewSampleData.inboxDocumentURL,
                        displayName: "Inbox.md",
                        subtitle: "Root document"
                    )
                ),
            ],
            lastUpdated: PreviewSampleData.previewDate
        )
    }
}
