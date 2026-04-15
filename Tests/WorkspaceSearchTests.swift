import XCTest
@testable import Downward

final class WorkspaceSearchTests: XCTestCase {
    @MainActor
    func testSearchMatchesFilesByFilenameAndRelativePathInSnapshotOrder() {
        let results = WorkspaceSearchEngine.results(
            in: PreviewSampleData.nestedWorkspace,
            matching: "md"
        )

        XCTAssertEqual(
            results.map(\.displayName),
            ["2026-04-13.md", "README.md", "Inbox.md"]
        )
        XCTAssertEqual(
            results.map(\.relativePath),
            [
                "Journal/2026/2026-04-13.md",
                "References/README.md",
                "Inbox.md",
            ]
        )

        let pathMatchedResults = WorkspaceSearchEngine.results(
            in: PreviewSampleData.nestedWorkspace,
            matching: "references/read"
        )

        XCTAssertEqual(pathMatchedResults.map(\.displayName), ["README.md"])
        XCTAssertEqual(pathMatchedResults.first?.relativePath, "References/README.md")
    }

    @MainActor
    func testClearingSearchReturnsToNormalWorkspaceState() {
        let container = AppContainer.preview(
            launchState: .workspaceReady,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            snapshot: PreviewSampleData.nestedWorkspace
        )
        let viewModel = container.workspaceViewModel

        viewModel.searchQuery = "read"

        XCTAssertTrue(viewModel.isSearching)
        XCTAssertEqual(viewModel.searchResults.map(\.displayName), ["README.md"])

        viewModel.searchQuery = ""

        XCTAssertFalse(viewModel.isSearching)
        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertEqual(viewModel.nodes(in: nil).map(\.displayName), PreviewSampleData.nestedWorkspace.rootNodes.map(\.displayName))
    }

    @MainActor
    func testSearchResultsRerunAgainstUpdatedSnapshot() {
        let container = AppContainer.preview(
            launchState: .workspaceReady,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            snapshot: PreviewSampleData.nestedWorkspace
        )
        let viewModel = container.workspaceViewModel

        viewModel.searchQuery = "read"
        XCTAssertEqual(viewModel.searchResults.map(\.displayName), ["README.md"])

        container.session.workspaceSnapshot = WorkspaceSnapshot(
            rootURL: PreviewSampleData.nestedWorkspace.rootURL,
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            rootNodes: [
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

        XCTAssertTrue(viewModel.isSearching)
        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }
}
