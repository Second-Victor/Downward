import XCTest
@testable import Downward

final class WorkspaceNavigationModeTests: XCTestCase {
    @MainActor
    func testWorkspaceNavigationModeUsesValueLinksOnlyForStackNavigation() {
        XCTAssertTrue(WorkspaceNavigationMode.stackPath.usesValueNavigationLinks)
        XCTAssertFalse(WorkspaceNavigationMode.splitSidebar.usesValueNavigationLinks)
    }

    @MainActor
    func testWorkspaceViewModelProgrammaticOpenUpdatesNavigationPath() {
        let session = AppSession()
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
        let viewModel = WorkspaceViewModel(session: session, coordinator: coordinator)

        viewModel.openFolder(PreviewSampleData.year2026URL)
        viewModel.openDocument(PreviewSampleData.cleanDocument.url)

        XCTAssertEqual(
            session.path,
            [.folder(PreviewSampleData.year2026URL), .editor(PreviewSampleData.cleanDocument.url)]
        )
    }
}
