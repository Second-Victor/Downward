import XCTest
@testable import Downward

final class WorkspaceSnapshotPathResolverTests: XCTestCase {
    @MainActor
    func testFileEntriesCarryCanonicalRelativePathsInSnapshotOrder() {
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
                .file(
                    .init(
                        url: PreviewSampleData.inboxDocumentURL,
                        displayName: "Localized Inbox.md",
                        subtitle: "Root document"
                    )
                ),
            ],
            lastUpdated: PreviewSampleData.previewDate
        )

        XCTAssertEqual(
            snapshot.fileEntries().map(\.relativePath),
            [
                "References/README.md",
                "Inbox.md",
            ]
        )
        XCTAssertEqual(
            snapshot.fileEntries().map(\.displayName),
            [
                "Localized README.md",
                "Localized Inbox.md",
            ]
        )
        XCTAssertEqual(snapshot.relativeFilePaths(), ["References/README.md", "Inbox.md"])
    }
}
