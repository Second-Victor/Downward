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
    func testWorkspaceViewModelProgrammaticFileOpenUsesOnlyEditorRoute() {
        let (session, viewModel) = makeWorkspaceViewModel()

        viewModel.openDocument(PreviewSampleData.cleanDocument.url)

        XCTAssertEqual(
            session.path,
            [.editor(PreviewSampleData.cleanDocument.url)]
        )
        XCTAssertEqual(
            session.regularWorkspaceDetail,
            .editor(PreviewSampleData.cleanDocument.url)
        )
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
    func testRegularWorkspaceDetailShowsSettingsWhenSettingsRouteIsTopmost() {
        let (session, _) = makeWorkspaceViewModel()
        session.path = [.settings]

        XCTAssertEqual(session.regularWorkspaceDetail, .settings)
    }

    @MainActor
    func testRegularWorkspaceDetailIgnoresLegacyFolderRouteWithoutEditor() {
        let (session, _) = makeWorkspaceViewModel()
        session.path = [.folder(PreviewSampleData.year2026URL)]

        XCTAssertEqual(session.regularWorkspaceDetail, .placeholder)
    }

    @MainActor
    func testRegularWorkspaceDetailFallsBackToOpenDocumentWhenNoEditorRouteExists() {
        let (session, _) = makeWorkspaceViewModel()
        session.openDocument = PreviewSampleData.cleanDocument

        XCTAssertEqual(
            session.regularWorkspaceDetail,
            .editor(PreviewSampleData.cleanDocument.url)
        )
    }

    @MainActor
    private func makeWorkspaceViewModel() -> (AppSession, WorkspaceViewModel) {
        let session = AppSession()
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        let recentFilesStore = RecentFilesStore(initialItems: [])
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
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

        return (session, viewModel)
    }
}
