import XCTest
@testable import Downward

final class WorkspaceSearchTests: XCTestCase {
    @MainActor
    func testWorkspaceViewModelCachesSearchResultsOutsideRepeatedReads() {
        let container = AppContainer.preview(
            launchState: .workspaceReady,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            snapshot: PreviewSampleData.nestedWorkspace
        )
        let searcher = CountingWorkspaceSearcher()
        let viewModel = WorkspaceViewModel(
            session: container.session,
            coordinator: container.coordinator,
            recentFilesStore: RecentFilesStore(initialItems: []),
            searcher: searcher
        )

        viewModel.searchQuery = "read"

        XCTAssertEqual(viewModel.searchResults.map(\.displayName), ["README.md"])
        XCTAssertEqual(viewModel.searchResults.map(\.displayName), ["README.md"])
        XCTAssertEqual(searcher.invocationCount, 1)

        viewModel.searchQuery = "read"

        XCTAssertEqual(viewModel.searchResults.map(\.displayName), ["README.md"])
        XCTAssertEqual(searcher.invocationCount, 1)
    }

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
    func testSearchBuildsCanonicalRelativePathsFromURLsInsteadOfDisplayNames() {
        let snapshot = WorkspaceSnapshot(
            rootURL: PreviewSampleData.workspaceRootURL,
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            rootNodes: [
                .folder(
                    .init(
                        url: PreviewSampleData.referencesURL,
                        displayName: "Localized References",
                        children: [
                            .file(
                                .init(
                                    url: PreviewSampleData.readmeDocumentURL,
                                    displayName: "Localized README.md",
                                    subtitle: "Project overview"
                                )
                            ),
                        ]
                    )
                ),
            ],
            lastUpdated: PreviewSampleData.previewDate
        )

        let results = WorkspaceSearchEngine.results(
            in: snapshot,
            matching: "references/readme"
        )

        XCTAssertEqual(results.map(\.displayName), ["Localized README.md"])
        XCTAssertEqual(results.map(\.relativePath), ["References/README.md"])
    }

    @MainActor
    func testSearchResultsKeepDuplicateFilenamesDisambiguatedByPathContext() {
        let referencesResult = WorkspaceSearchResult(
            url: PreviewSampleData.readmeDocumentURL,
            displayName: "README.md",
            relativePath: "References/README.md",
            modifiedAt: PreviewSampleData.previewDate
        )
        let archiveResult = WorkspaceSearchResult(
            url: PreviewSampleData.archiveURL.appending(path: "README.md"),
            displayName: "README.md",
            relativePath: "Archive/README.md",
            modifiedAt: PreviewSampleData.previewDate.addingTimeInterval(-3_600)
        )

        XCTAssertEqual(referencesResult.pathContextText, "References")
        XCTAssertEqual(archiveResult.pathContextText, "Archive")
    }

    @MainActor
    func testSearchPathContextUsesParentFoldersAndWorkspaceRootLabel() {
        let nestedResult = WorkspaceSearchResult(
            url: PreviewSampleData.readmeDocumentURL,
            displayName: "README.md",
            relativePath: "Projects/Client A/2026/Q2/Launch Prep/Meeting Notes/README.md",
            modifiedAt: PreviewSampleData.previewDate
        )
        let rootResult = WorkspaceSearchResult(
            url: PreviewSampleData.inboxDocumentURL,
            displayName: "Inbox.md",
            relativePath: "Inbox.md",
            modifiedAt: PreviewSampleData.previewDate
        )

        XCTAssertEqual(
            nestedResult.pathContextText,
            "Projects/Client A/2026/Q2/Launch Prep/Meeting Notes"
        )
        XCTAssertEqual(rootResult.pathContextText, "Workspace root")
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

        RunLoop.main.run(until: Date().addingTimeInterval(0.01))

        XCTAssertTrue(viewModel.isSearching)
        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }
}

private final class CountingWorkspaceSearcher: @unchecked Sendable, WorkspaceSearching {
    private let lock = NSLock()
    private var count = 0

    var invocationCount: Int {
        lock.withLock { count }
    }

    func results(
        in snapshot: WorkspaceSnapshot,
        matching rawQuery: String
    ) -> [WorkspaceSearchResult] {
        lock.withLock {
            count += 1
        }
        return WorkspaceSearchEngine.results(in: snapshot, matching: rawQuery)
    }
}
