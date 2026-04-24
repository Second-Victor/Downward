import XCTest
@testable import Downward

final class WorkspaceNavigationModeTests: XCTestCase {
    @MainActor
    func testWorkspaceNavigationModeUsesValueLinksOnlyForStackNavigation() {
        XCTAssertTrue(WorkspaceNavigationMode.stackPath.usesValueNavigationLinks)
        XCTAssertFalse(WorkspaceNavigationMode.splitSidebar.usesValueNavigationLinks)
    }

    @MainActor
    func testRegularWorkspaceDetailDefaultsToPlaceholderWithoutActiveDocument() {
        let (session, _) = makeWorkspaceViewModel()

        XCTAssertEqual(session.regularWorkspaceDetail, .placeholder)
    }

    @MainActor
    func testWorkspaceViewModelRelativePathOpenUsesTrustedEditorRoute() {
        let (session, coordinator, viewModel) = makeWorkspaceSystem()

        viewModel.openDocument(
            relativePath: PreviewSampleData.cleanDocument.relativePath,
            preferredURL: PreviewSampleData.cleanDocument.url
        )

        XCTAssertEqual(
            session.path,
            [.trustedEditor(
                PreviewSampleData.cleanDocument.url,
                PreviewSampleData.cleanDocument.relativePath
            )]
        )
        XCTAssertEqual(session.regularDetailSelection, .placeholder)

        coordinator.updateNavigationLayout(.regular)

        XCTAssertEqual(
            session.regularWorkspaceDetail,
            .editor(PreviewSampleData.cleanDocument.url)
        )
        XCTAssertEqual(session.path, [])
    }

    @MainActor
    func testWorkspaceViewModelJSONOpenUsesTrustedEditorRoute() {
        let (session, _, viewModel) = makeWorkspaceSystem()
        let jsonURL = PreviewSampleData.workspaceRootURL.appending(path: "Theme.json")

        viewModel.openDocument(
            relativePath: "Theme.json",
            preferredURL: jsonURL
        )

        XCTAssertEqual(session.path, [.trustedEditor(jsonURL, "Theme.json")])
        XCTAssertEqual(
            session.pendingEditorPresentation,
            .init(routeURL: jsonURL, relativePath: "Theme.json")
        )
        XCTAssertNil(session.workspaceAlertError)
    }

    @MainActor
    func testTreeStyleProgrammaticOpenInRegularModeUsesTrustedRelativeIdentity() {
        let (session, coordinator, viewModel) = makeWorkspaceSystem()
        let preferredRouteURL = URL(
            filePath: "\(PreviewSampleData.workspaceRootURL.path)/Journal/../Inbox.md"
        )
        XCTAssertNotEqual(preferredRouteURL, PreviewSampleData.cleanDocument.url)

        coordinator.updateNavigationLayout(.regular)
        viewModel.openDocument(
            relativePath: PreviewSampleData.cleanDocument.relativePath,
            preferredURL: preferredRouteURL
        )

        XCTAssertEqual(
            session.pendingEditorPresentation,
            .init(
                routeURL: preferredRouteURL,
                relativePath: PreviewSampleData.cleanDocument.relativePath
            )
        )
        XCTAssertEqual(
            session.regularDetailSelection,
            .editor(PreviewSampleData.cleanDocument.relativePath)
        )
        XCTAssertEqual(
            session.regularWorkspaceDetail,
            .editor(preferredRouteURL)
        )
        XCTAssertEqual(session.path, [])
    }

    @MainActor
    func testFolderExpansionTogglesInlineWithoutChangingNavigationPath() {
        let (session, viewModel) = makeWorkspaceViewModel()

        viewModel.toggleFolderExpansion(at: PreviewSampleData.year2026URL)
        XCTAssertTrue(viewModel.isFolderExpanded(at: PreviewSampleData.year2026URL))
        XCTAssertTrue(session.path.isEmpty)

        viewModel.toggleFolderExpansion(at: URL(filePath: "\(PreviewSampleData.workspaceRootURL.path)/Journal/2026/../2026"))
        XCTAssertFalse(viewModel.isFolderExpanded(at: PreviewSampleData.year2026URL))
        XCTAssertTrue(session.path.isEmpty)
        XCTAssertEqual(session.regularWorkspaceDetail, .placeholder)
    }

    @MainActor
    func testExpandFolderAndAncestorsUsesCanonicalFolderIdentity() {
        let (_, viewModel) = makeWorkspaceViewModel()

        viewModel.expandFolderAndAncestors(
            at: URL(filePath: "\(PreviewSampleData.workspaceRootURL.path)/Journal/2026/../2026")
        )

        XCTAssertTrue(viewModel.isFolderExpanded(at: PreviewSampleData.journalURL))
        XCTAssertTrue(viewModel.isFolderExpanded(at: PreviewSampleData.year2026URL))
    }

    @MainActor
    func testSyncExpandedFoldersPreservesExistingFoldersAndDropsMissingOnes() {
        let (session, viewModel) = makeWorkspaceViewModel()

        viewModel.expandFolderAndAncestors(at: PreviewSampleData.year2026URL)
        viewModel.expandFolderAndAncestors(at: PreviewSampleData.referencesURL)

        session.workspaceSnapshot = WorkspaceSnapshot(
            rootURL: PreviewSampleData.workspaceRootURL,
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            rootNodes: [
                .folder(
                    .init(
                        url: PreviewSampleData.journalURL,
                        displayName: "Journal",
                        children: [
                            .folder(
                                .init(
                                    url: PreviewSampleData.year2026URL,
                                    displayName: "2026",
                                    children: []
                                )
                            ),
                        ]
                    )
                ),
            ],
            lastUpdated: PreviewSampleData.previewDate
        )

        viewModel.syncExpandedFoldersToCurrentSnapshot()

        XCTAssertTrue(viewModel.isFolderExpanded(at: PreviewSampleData.journalURL))
        XCTAssertTrue(viewModel.isFolderExpanded(at: PreviewSampleData.year2026URL))
        XCTAssertFalse(viewModel.isFolderExpanded(at: PreviewSampleData.referencesURL))
    }

    @MainActor
    func testRenamedExpandedFolderStaysExpanded() async throws {
        let renamedFolderURL = PreviewSampleData.workspaceRootURL.appending(path: "Logbook")
        let renamedSnapshot = makeWorkspaceSnapshotReplacingJournalFolder(
            withFolderURL: renamedFolderURL
        )
        let renameOutcome = WorkspaceMutationOutcome.renamedFolder(
            oldURL: PreviewSampleData.journalURL,
            newURL: renamedFolderURL,
            displayName: "Logbook",
            relativePath: "Logbook"
        )
        let (session, _, viewModel) = makeWorkspaceSystem(
            workspaceManager: ViewModelRenameTestingWorkspaceManager(
                refreshSnapshot: renamedSnapshot,
                renameOutcome: renameOutcome
            )
        )
        session.launchState = .workspaceReady
        let journalNode = try XCTUnwrap(
            session.workspaceSnapshot?.rootNodes.first(where: { $0.url == PreviewSampleData.journalURL })
        )

        viewModel.toggleFolderExpansion(at: PreviewSampleData.journalURL)
        viewModel.presentRename(for: journalNode)
        viewModel.renameItemName = "Logbook"
        viewModel.renameItem()

        try await waitUntil {
            viewModel.isPerformingFileOperation == false
        }

        XCTAssertTrue(viewModel.isFolderExpanded(at: renamedFolderURL))
        XCTAssertFalse(viewModel.isFolderExpanded(at: PreviewSampleData.journalURL))
    }

    @MainActor
    func testExpandedDescendantsUnderRenamedAncestorStayExpanded() async throws {
        let renamedFolderURL = PreviewSampleData.workspaceRootURL.appending(path: "Logbook")
        let renamedYearURL = renamedFolderURL.appending(path: "2026")
        let renamedSnapshot = makeWorkspaceSnapshotReplacingJournalFolder(
            withFolderURL: renamedFolderURL
        )
        let renameOutcome = WorkspaceMutationOutcome.renamedFolder(
            oldURL: PreviewSampleData.journalURL,
            newURL: renamedFolderURL,
            displayName: "Logbook",
            relativePath: "Logbook"
        )
        let (session, _, viewModel) = makeWorkspaceSystem(
            workspaceManager: ViewModelRenameTestingWorkspaceManager(
                refreshSnapshot: renamedSnapshot,
                renameOutcome: renameOutcome
            )
        )
        session.launchState = .workspaceReady
        let journalNode = try XCTUnwrap(
            session.workspaceSnapshot?.rootNodes.first(where: { $0.url == PreviewSampleData.journalURL })
        )

        viewModel.expandFolderAndAncestors(at: PreviewSampleData.year2026URL)
        viewModel.presentRename(for: journalNode)
        viewModel.renameItemName = "Logbook"
        viewModel.renameItem()

        try await waitUntil {
            viewModel.isPerformingFileOperation == false
        }

        XCTAssertTrue(viewModel.isFolderExpanded(at: renamedFolderURL))
        XCTAssertTrue(viewModel.isFolderExpanded(at: renamedYearURL))
        XCTAssertFalse(viewModel.isFolderExpanded(at: PreviewSampleData.journalURL))
        XCTAssertFalse(viewModel.isFolderExpanded(at: PreviewSampleData.year2026URL))
    }

    @MainActor
    func testMovedExpandedFolderAndDescendantsStayExpandedAtDestination() async throws {
        let movedFolderURL = PreviewSampleData.archiveURL.appending(path: "Journal")
        let movedYearURL = movedFolderURL.appending(path: "2026")
        let movedSnapshot = makeWorkspaceSnapshotMovingJournalFolder(to: movedFolderURL)
        let moveOutcome = WorkspaceMutationOutcome.renamedFolder(
            oldURL: PreviewSampleData.journalURL,
            newURL: movedFolderURL,
            displayName: "Journal",
            relativePath: "Archive/Journal"
        )
        let (session, _, viewModel) = makeWorkspaceSystem(
            workspaceManager: ViewModelRenameTestingWorkspaceManager(
                refreshSnapshot: movedSnapshot,
                renameOutcome: moveOutcome
            )
        )
        session.launchState = .workspaceReady
        let journalNode = try XCTUnwrap(
            session.workspaceSnapshot?.rootNodes.first(where: { $0.url == PreviewSampleData.journalURL })
        )

        viewModel.expandFolderAndAncestors(at: PreviewSampleData.year2026URL)
        viewModel.presentMove(for: journalNode)
        viewModel.moveItem(toFolderRelativePath: "Archive")

        try await waitUntil {
            viewModel.isPerformingFileOperation == false
        }

        XCTAssertTrue(viewModel.isFolderExpanded(at: PreviewSampleData.archiveURL))
        XCTAssertTrue(viewModel.isFolderExpanded(at: movedFolderURL))
        XCTAssertTrue(viewModel.isFolderExpanded(at: movedYearURL))
        XCTAssertFalse(viewModel.isFolderExpanded(at: PreviewSampleData.journalURL))
        XCTAssertFalse(viewModel.isFolderExpanded(at: PreviewSampleData.year2026URL))
    }

    @MainActor
    func testSecondMutationRequestDuringInFlightMutationSurfacesBusyErrorInsteadOfSilentlyNoOping() async throws {
        let (session, _, viewModel) = makeWorkspaceSystem(
            workspaceManager: DelayedViewModelMutationWorkspaceManager(
                refreshSnapshot: PreviewSampleData.nestedWorkspace,
                createFileDelay: .milliseconds(200)
            )
        )
        session.launchState = .workspaceReady

        viewModel.presentCreateFile(in: nil)
        viewModel.createItemName = "Scratch.md"
        viewModel.createItem()

        try await waitUntil {
            viewModel.isPerformingFileOperation
        }

        viewModel.presentCreateFolder(in: nil)
        viewModel.createItemName = "Scratch Folder"
        viewModel.createItem()

        XCTAssertEqual(session.workspaceAlertError?.title, "Operation in Progress")
        XCTAssertEqual(
            session.workspaceAlertError?.message,
            "Finish the current workspace change before starting another one."
        )

        try await waitUntil {
            viewModel.isPerformingFileOperation == false
        }
    }

    @MainActor
    func testRowActionsAreDisabledWhileBusy() async throws {
        let (session, _, viewModel) = makeWorkspaceSystem(
            workspaceManager: DelayedViewModelMutationWorkspaceManager(
                refreshSnapshot: PreviewSampleData.nestedWorkspace,
                createFileDelay: .milliseconds(200)
            )
        )
        session.launchState = .workspaceReady

        XCTAssertFalse(viewModel.areRowActionsDisabled)

        viewModel.presentCreateFile(in: nil)
        viewModel.createItemName = "Scratch.md"
        viewModel.createItem()

        try await waitUntil {
            viewModel.isPerformingFileOperation
        }

        XCTAssertTrue(viewModel.areRowActionsDisabled)

        try await waitUntil {
            viewModel.isPerformingFileOperation == false
        }

        XCTAssertFalse(viewModel.areRowActionsDisabled)
    }

    @MainActor
    func testRegularWorkspaceDetailShowsSettingsFromExplicitSelection() {
        let (session, coordinator, _) = makeWorkspaceSystem()
        coordinator.updateNavigationLayout(.regular)
        session.regularDetailSelection = .settings

        XCTAssertEqual(session.regularWorkspaceDetail, .settings)
    }

    @MainActor
    func testPresentSettingsUsesSheetInsteadOfCompactNavigationPush() {
        let (session, coordinator, _) = makeWorkspaceSystem()
        session.path = [.trustedEditor(
            PreviewSampleData.cleanDocument.url,
            PreviewSampleData.cleanDocument.relativePath
        )]

        coordinator.presentSettings()

        XCTAssertTrue(session.isSettingsPresented)
        XCTAssertEqual(
            session.path,
            [.trustedEditor(
                PreviewSampleData.cleanDocument.url,
                PreviewSampleData.cleanDocument.relativePath
            )]
        )
    }

    @MainActor
    func testRegularWorkspaceDetailPrefersPendingRouteURLForSelectedRelativePath() {
        let (session, coordinator, _) = makeWorkspaceSystem()
        let preferredRouteURL = URL(
            filePath: "\(PreviewSampleData.workspaceRootURL.path)/References/../Inbox.md"
        )
        XCTAssertNotEqual(preferredRouteURL, PreviewSampleData.cleanDocument.url)

        coordinator.updateNavigationLayout(.regular)
        session.pendingEditorPresentation = .init(
            routeURL: preferredRouteURL,
            relativePath: PreviewSampleData.cleanDocument.relativePath
        )
        session.regularDetailSelection = .editor(PreviewSampleData.cleanDocument.relativePath)

        XCTAssertEqual(
            session.regularWorkspaceDetail,
            .editor(preferredRouteURL)
        )
    }

    @MainActor
    func testCompactToRegularWithOpenEditorPromotesEditorSelectionAndClearsCompactPath() {
        let (session, coordinator, _) = makeWorkspaceSystem()
        session.path = [.editor(PreviewSampleData.cleanDocument.url)]

        coordinator.updateNavigationLayout(.regular)

        XCTAssertEqual(
            session.regularDetailSelection,
            .editor(PreviewSampleData.cleanDocument.relativePath)
        )
        XCTAssertEqual(
            session.regularWorkspaceDetail,
            .editor(PreviewSampleData.cleanDocument.url)
        )
        XCTAssertEqual(session.path, [])
    }

    @MainActor
    func testRegularToCompactKeepsOnlyVisibleEditorAfterSettingsThenEditor() {
        let (session, coordinator, _) = makeWorkspaceSystem()
        coordinator.updateNavigationLayout(.regular)

        coordinator.presentSettings()
        coordinator.presentEditor(for: PreviewSampleData.cleanDocument.url)

        XCTAssertEqual(
            session.regularDetailSelection,
            .editor(PreviewSampleData.cleanDocument.relativePath)
        )
        XCTAssertEqual(session.path, [])

        coordinator.updateNavigationLayout(.compact)

        XCTAssertEqual(
            session.path,
            [.trustedEditor(
                PreviewSampleData.cleanDocument.url,
                PreviewSampleData.cleanDocument.relativePath
            )]
        )
        XCTAssertEqual(session.regularDetailSelection, .placeholder)
    }

    @MainActor
    func testRepeatedSettingsAndEditorTogglingDoesNotAccumulateHiddenCompactStateInRegularMode() {
        let (session, coordinator, _) = makeWorkspaceSystem()
        coordinator.updateNavigationLayout(.regular)

        coordinator.presentSettings()
        coordinator.presentEditor(for: PreviewSampleData.cleanDocument.url)
        coordinator.presentSettings()
        coordinator.presentEditor(for: PreviewSampleData.dirtyDocument.url)

        XCTAssertEqual(
            session.regularDetailSelection,
            .editor(PreviewSampleData.dirtyDocument.relativePath)
        )
        XCTAssertEqual(session.path, [])

        coordinator.updateNavigationLayout(.compact)

        XCTAssertEqual(
            session.path,
            [.trustedEditor(
                PreviewSampleData.dirtyDocument.url,
                PreviewSampleData.dirtyDocument.relativePath
            )]
        )
    }

    @MainActor
    func testCompactToRegularDropsHiddenCompactHistoryInsteadOfResurrectingItOnReturn() {
        let (session, coordinator, _) = makeWorkspaceSystem()
        session.path = [.settings, .editor(PreviewSampleData.cleanDocument.url)]

        coordinator.updateNavigationLayout(.regular)
        XCTAssertEqual(
            session.regularDetailSelection,
            .editor(PreviewSampleData.cleanDocument.relativePath)
        )
        XCTAssertEqual(session.path, [])

        coordinator.updateNavigationLayout(.compact)

        XCTAssertEqual(
            session.path,
            [.trustedEditor(
                PreviewSampleData.cleanDocument.url,
                PreviewSampleData.cleanDocument.relativePath
            )]
        )
    }

    @MainActor
    private func makeWorkspaceViewModel() -> (AppSession, WorkspaceViewModel) {
        let (session, _, viewModel) = makeWorkspaceSystem()
        return (session, viewModel)
    }

    @MainActor
    private func makeWorkspaceSystem(
        workspaceManager: (any WorkspaceManager)? = nil
    ) -> (AppSession, AppCoordinator, WorkspaceViewModel) {
        let session = AppSession()
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        let recentFilesStore = RecentFilesStore(initialItems: [])
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: workspaceManager ?? StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let viewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: recentFilesStore
        )

        return (session, coordinator, viewModel)
    }

    @MainActor
    private func makeWorkspaceSnapshotReplacingJournalFolder(withFolderURL folderURL: URL) -> WorkspaceSnapshot {
        let renamedYearURL = folderURL.appending(path: "2026")

        return WorkspaceSnapshot(
            rootURL: PreviewSampleData.workspaceRootURL,
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            rootNodes: [
                .folder(
                    .init(
                        url: folderURL,
                        displayName: folderURL.lastPathComponent,
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
                                                subtitle: "Daily note",
                                                modifiedAt: PreviewSampleData.previewDate.addingTimeInterval(-600)
                                            )
                                        ),
                                        .file(
                                            .init(
                                                url: renamedYearURL.appending(path: "Ideas.markdown"),
                                                displayName: "Ideas.markdown",
                                                subtitle: "Scratchpad",
                                                modifiedAt: PreviewSampleData.previewDate.addingTimeInterval(-3_600)
                                            )
                                        ),
                                    ]
                                )
                            ),
                        ]
                    )
                ),
                .folder(
                    .init(
                        url: PreviewSampleData.referencesURL,
                        displayName: "References",
                        children: [
                            .file(
                                .init(
                                    url: PreviewSampleData.readmeDocumentURL,
                                    displayName: "README.md",
                                    subtitle: "Project overview",
                                    modifiedAt: PreviewSampleData.previewDate.addingTimeInterval(-7_200)
                                )
                            ),
                        ]
                    )
                ),
                .folder(
                    .init(
                        url: PreviewSampleData.archiveURL,
                        displayName: "Archive",
                        children: []
                    )
                ),
                .file(
                    .init(
                        url: PreviewSampleData.inboxDocumentURL,
                        displayName: "Inbox.md",
                        subtitle: "Root document",
                        modifiedAt: PreviewSampleData.previewDate
                    )
                ),
            ],
            lastUpdated: PreviewSampleData.previewDate
        )
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
                                    subtitle: "Project overview",
                                    modifiedAt: PreviewSampleData.previewDate.addingTimeInterval(-7_200)
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
                                                            subtitle: "Daily note",
                                                            modifiedAt: PreviewSampleData.previewDate.addingTimeInterval(-600)
                                                        )
                                                    ),
                                                    .file(
                                                        .init(
                                                            url: movedYearURL.appending(path: "Ideas.markdown"),
                                                            displayName: "Ideas.markdown",
                                                            subtitle: "Scratchpad",
                                                            modifiedAt: PreviewSampleData.previewDate.addingTimeInterval(-3_600)
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
                        subtitle: "Root document",
                        modifiedAt: PreviewSampleData.previewDate
                    )
                ),
            ],
            lastUpdated: PreviewSampleData.previewDate
        )
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

private actor ViewModelRenameTestingWorkspaceManager: WorkspaceManager {
    let refreshSnapshot: WorkspaceSnapshot
    let renameOutcome: WorkspaceMutationOutcome

    init(
        refreshSnapshot: WorkspaceSnapshot,
        renameOutcome: WorkspaceMutationOutcome
    ) {
        self.refreshSnapshot = refreshSnapshot
        self.renameOutcome = renameOutcome
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
            outcome: renameOutcome
        )
    }

    func moveItem(at url: URL, toFolder destinationFolderURL: URL?) async throws -> WorkspaceMutationResult {
        WorkspaceMutationResult(
            snapshot: refreshSnapshot,
            outcome: renameOutcome
        )
    }

    func deleteFile(at url: URL) async throws -> WorkspaceMutationResult {
        WorkspaceMutationResult(
            snapshot: refreshSnapshot,
            outcome: .deletedFile(url: url, displayName: url.lastPathComponent)
        )
    }

    func clearWorkspaceSelection() async throws {}
}

private actor DelayedViewModelMutationWorkspaceManager: WorkspaceManager {
    let refreshSnapshot: WorkspaceSnapshot
    let createFileDelay: Duration

    init(
        refreshSnapshot: WorkspaceSnapshot,
        createFileDelay: Duration
    ) {
        self.refreshSnapshot = refreshSnapshot
        self.createFileDelay = createFileDelay
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
        try await Task.sleep(for: createFileDelay)
        return WorkspaceMutationResult(
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
            outcome: .renamedFile(
                oldURL: url,
                newURL: url.deletingLastPathComponent().appending(path: proposedName),
                displayName: proposedName,
                relativePath: proposedName
            )
        )
    }

    func moveItem(at url: URL, toFolder destinationFolderURL: URL?) async throws -> WorkspaceMutationResult {
        let destinationFolderURL = destinationFolderURL ?? refreshSnapshot.rootURL
        let destinationURL = destinationFolderURL.appending(path: url.lastPathComponent)
        let relativePath = WorkspaceRelativePath.make(
            for: destinationURL,
            within: refreshSnapshot.rootURL
        ) ?? destinationURL.lastPathComponent

        return WorkspaceMutationResult(
            snapshot: refreshSnapshot,
            outcome: .renamedFile(
                oldURL: url,
                newURL: destinationURL,
                displayName: destinationURL.lastPathComponent,
                relativePath: relativePath
            )
        )
    }

    func deleteFile(at url: URL) async throws -> WorkspaceMutationResult {
        WorkspaceMutationResult(
            snapshot: refreshSnapshot,
            outcome: .deletedFile(url: url, displayName: url.lastPathComponent)
        )
    }

    func clearWorkspaceSelection() async throws {}
}
