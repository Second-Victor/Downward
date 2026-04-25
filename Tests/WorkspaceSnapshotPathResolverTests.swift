import Foundation
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

    func testDuplicateFilenamesInDifferentFoldersResolveToSeparateURLs() {
        let rootURL = URL(filePath: "/tmp/Workspace")
        let notesReadmeURL = rootURL.appending(path: "Notes/README.md")
        let archiveReadmeURL = rootURL.appending(path: "Archive/README.md")
        let snapshot = makeSnapshot(
            rootURL: rootURL,
            rootNodes: [
                folder(
                    url: rootURL.appending(path: "Notes"),
                    children: [
                        file(url: notesReadmeURL),
                    ]
                ),
                folder(
                    url: rootURL.appending(path: "Archive"),
                    children: [
                        file(url: archiveReadmeURL),
                    ]
                ),
            ]
        )

        XCTAssertEqual(snapshot.fileURL(forRelativePath: "Notes/README.md"), notesReadmeURL)
        XCTAssertEqual(snapshot.fileURL(forRelativePath: "Archive/README.md"), archiveReadmeURL)
        XCTAssertEqual(snapshot.relativePath(for: notesReadmeURL), "Notes/README.md")
        XCTAssertEqual(snapshot.relativePath(for: archiveReadmeURL), "Archive/README.md")
        XCTAssertTrue(snapshot.containsFile(relativePath: "Notes/README.md"))
        XCTAssertTrue(snapshot.containsFile(relativePath: "Archive/README.md"))
    }

    func testNestedRelativePathLookupResolvesFileURL() {
        let rootURL = URL(filePath: "/tmp/Workspace")
        let guideURL = rootURL.appending(path: "Projects/Downward/Docs/Guide.md")
        let snapshot = makeSnapshot(
            rootURL: rootURL,
            rootNodes: [
                folder(
                    url: rootURL.appending(path: "Projects"),
                    children: [
                        folder(
                            url: rootURL.appending(path: "Projects/Downward"),
                            children: [
                                folder(
                                    url: rootURL.appending(path: "Projects/Downward/Docs"),
                                    children: [
                                        file(url: guideURL),
                                    ]
                                ),
                            ]
                        ),
                    ]
                ),
            ]
        )

        XCTAssertEqual(snapshot.fileURL(forRelativePath: "Projects/Downward/Docs/Guide.md"), guideURL)
        XCTAssertEqual(snapshot.relativePath(for: guideURL), "Projects/Downward/Docs/Guide.md")
    }

    func testMissingStalePathLookupReturnsNilAndFalse() {
        let rootURL = URL(filePath: "/tmp/Workspace")
        let snapshot = makeSnapshot(
            rootURL: rootURL,
            rootNodes: [
                file(url: rootURL.appending(path: "Inbox.md")),
            ]
        )

        XCTAssertNil(snapshot.fileURL(forRelativePath: "Missing.md"))
        XCTAssertFalse(snapshot.containsFile(relativePath: "Missing.md"))
        XCTAssertNil(snapshot.relativePath(for: rootURL.appending(path: "Missing.md")))
    }

    func testReplacementSnapshotsRebuildIndexesForRenameMoveAndDelete() {
        let rootURL = URL(filePath: "/tmp/Workspace")
        let originalURL = rootURL.appending(path: "Draft.md")
        let renamedURL = rootURL.appending(path: "Draft Renamed.md")
        let movedURL = rootURL.appending(path: "Archive/Draft Renamed.md")

        let originalSnapshot = makeSnapshot(
            rootURL: rootURL,
            rootNodes: [
                file(url: originalURL),
            ]
        )
        let renamedSnapshot = makeSnapshot(
            rootURL: rootURL,
            rootNodes: [
                file(url: renamedURL),
            ]
        )
        let movedSnapshot = makeSnapshot(
            rootURL: rootURL,
            rootNodes: [
                folder(
                    url: rootURL.appending(path: "Archive"),
                    children: [
                        file(url: movedURL),
                    ]
                ),
            ]
        )
        let deletedSnapshot = makeSnapshot(rootURL: rootURL, rootNodes: [])

        XCTAssertEqual(originalSnapshot.fileURL(forRelativePath: "Draft.md"), originalURL)
        XCTAssertNil(renamedSnapshot.fileURL(forRelativePath: "Draft.md"))
        XCTAssertEqual(renamedSnapshot.fileURL(forRelativePath: "Draft Renamed.md"), renamedURL)
        XCTAssertNil(movedSnapshot.fileURL(forRelativePath: "Draft Renamed.md"))
        XCTAssertEqual(movedSnapshot.fileURL(forRelativePath: "Archive/Draft Renamed.md"), movedURL)
        XCTAssertNil(deletedSnapshot.fileURL(forRelativePath: "Archive/Draft Renamed.md"))
        XCTAssertFalse(deletedSnapshot.containsFile(relativePath: "Archive/Draft Renamed.md"))
    }

    func testCaseOnlyRenameUsesExactCaseSensitiveRelativePaths() {
        let rootURL = URL(filePath: "/tmp/Workspace")
        let lowercaseURL = rootURL.appending(path: "readme.md")
        let uppercaseURL = rootURL.appending(path: "README.md")
        let lowercaseSnapshot = makeSnapshot(
            rootURL: rootURL,
            rootNodes: [
                file(url: lowercaseURL),
            ]
        )
        let uppercaseSnapshot = makeSnapshot(
            rootURL: rootURL,
            rootNodes: [
                file(url: uppercaseURL),
            ]
        )

        XCTAssertEqual(lowercaseSnapshot.fileURL(forRelativePath: "readme.md"), lowercaseURL)
        XCTAssertNil(lowercaseSnapshot.fileURL(forRelativePath: "README.md"))
        XCTAssertNil(uppercaseSnapshot.fileURL(forRelativePath: "readme.md"))
        XCTAssertEqual(uppercaseSnapshot.fileURL(forRelativePath: "README.md"), uppercaseURL)
        XCTAssertNil(uppercaseSnapshot.relativePath(for: lowercaseURL))
        XCTAssertEqual(uppercaseSnapshot.relativePath(for: uppercaseURL), "README.md")
    }

    private func makeSnapshot(
        rootURL: URL,
        rootNodes: [WorkspaceNode]
    ) -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            rootURL: rootURL,
            displayName: "Workspace",
            rootNodes: rootNodes,
            lastUpdated: Date(timeIntervalSinceReferenceDate: 0)
        )
    }

    private func folder(url: URL, children: [WorkspaceNode]) -> WorkspaceNode {
        .folder(
            .init(
                url: url,
                displayName: url.lastPathComponent,
                children: children
            )
        )
    }

    private func file(url: URL) -> WorkspaceNode {
        .file(
            .init(
                url: url,
                displayName: url.lastPathComponent,
                subtitle: nil
            )
        )
    }
}
