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

        var visitedRelativePaths: [String] = []
        snapshot.forEachFile { entry in
            visitedRelativePaths.append(entry.relativePath)
        }
        XCTAssertEqual(visitedRelativePaths, ["References/README.md", "Inbox.md"])
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

    func testKnownFileURLResolvesToWorkspaceRelativePath() {
        let rootURL = URL(filePath: "/tmp/Workspace")
        let draftURL = rootURL.appending(path: "Drafts/Today.md")
        let snapshot = makeSnapshot(
            rootURL: rootURL,
            rootNodes: [
                folder(
                    url: rootURL.appending(path: "Drafts"),
                    children: [
                        file(url: draftURL),
                    ]
                ),
            ]
        )

        XCTAssertEqual(snapshot.relativePath(for: draftURL), "Drafts/Today.md")
    }

    func testFileURLLookupRemainsFileOnly() {
        let rootURL = URL(filePath: "/tmp/Workspace")
        let notesURL = rootURL.appending(path: "Notes")
        let snapshot = makeSnapshot(
            rootURL: rootURL,
            rootNodes: [
                folder(
                    url: notesURL,
                    children: [
                        file(url: notesURL.appending(path: "README.md")),
                    ]
                ),
            ]
        )

        XCTAssertEqual(snapshot.relativePath(for: notesURL), "Notes")
        XCTAssertNil(snapshot.fileURL(forRelativePath: "Notes"))
        XCTAssertFalse(snapshot.containsFile(relativePath: "Notes"))
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

    func testReplacementSnapshotsRebuildIndexesForFolderRename() {
        let rootURL = URL(filePath: "/tmp/Workspace")
        let oldFileURL = rootURL.appending(path: "OldFolder/Note.md")
        let newFileURL = rootURL.appending(path: "NewFolder/Note.md")
        let originalSnapshot = makeSnapshot(
            rootURL: rootURL,
            rootNodes: [
                folder(
                    url: rootURL.appending(path: "OldFolder"),
                    children: [
                        file(url: oldFileURL),
                    ]
                ),
            ]
        )
        let renamedSnapshot = makeSnapshot(
            rootURL: rootURL,
            rootNodes: [
                folder(
                    url: rootURL.appending(path: "NewFolder"),
                    children: [
                        file(url: newFileURL),
                    ]
                ),
            ]
        )

        XCTAssertEqual(originalSnapshot.fileURL(forRelativePath: "OldFolder/Note.md"), oldFileURL)
        XCTAssertEqual(originalSnapshot.relativePath(for: oldFileURL), "OldFolder/Note.md")
        XCTAssertNil(renamedSnapshot.fileURL(forRelativePath: "OldFolder/Note.md"))
        XCTAssertFalse(renamedSnapshot.containsFile(relativePath: "OldFolder/Note.md"))
        XCTAssertNil(renamedSnapshot.relativePath(for: oldFileURL))
        XCTAssertEqual(renamedSnapshot.fileURL(forRelativePath: "NewFolder/Note.md"), newFileURL)
        XCTAssertEqual(renamedSnapshot.relativePath(for: newFileURL), "NewFolder/Note.md")
    }

    func testReplacementSnapshotsRebuildIndexesForFolderMoveWithDuplicateNames() {
        let rootURL = URL(filePath: "/tmp/Workspace")
        let originalURL = rootURL.appending(path: "Projects/App/README.md")
        let movedURL = rootURL.appending(path: "Archive/App/README.md")
        let duplicateURL = rootURL.appending(path: "Projects/API/README.md")
        let originalSnapshot = makeSnapshot(
            rootURL: rootURL,
            rootNodes: [
                folder(
                    url: rootURL.appending(path: "Projects"),
                    children: [
                        folder(
                            url: rootURL.appending(path: "Projects/App"),
                            children: [
                                file(url: originalURL),
                            ]
                        ),
                        folder(
                            url: rootURL.appending(path: "Projects/API"),
                            children: [
                                file(url: duplicateURL),
                            ]
                        ),
                    ]
                ),
                folder(url: rootURL.appending(path: "Archive"), children: []),
            ]
        )
        let movedSnapshot = makeSnapshot(
            rootURL: rootURL,
            rootNodes: [
                folder(
                    url: rootURL.appending(path: "Projects"),
                    children: [
                        folder(
                            url: rootURL.appending(path: "Projects/API"),
                            children: [
                                file(url: duplicateURL),
                            ]
                        ),
                    ]
                ),
                folder(
                    url: rootURL.appending(path: "Archive"),
                    children: [
                        folder(
                            url: rootURL.appending(path: "Archive/App"),
                            children: [
                                file(url: movedURL),
                            ]
                        ),
                    ]
                ),
            ]
        )

        XCTAssertEqual(originalSnapshot.fileURL(forRelativePath: "Projects/App/README.md"), originalURL)
        XCTAssertNil(movedSnapshot.fileURL(forRelativePath: "Projects/App/README.md"))
        XCTAssertFalse(movedSnapshot.containsFile(relativePath: "Projects/App/README.md"))
        XCTAssertNil(movedSnapshot.relativePath(for: originalURL))
        XCTAssertEqual(movedSnapshot.fileURL(forRelativePath: "Archive/App/README.md"), movedURL)
        XCTAssertEqual(movedSnapshot.relativePath(for: movedURL), "Archive/App/README.md")
        XCTAssertEqual(movedSnapshot.fileURL(forRelativePath: "Projects/API/README.md"), duplicateURL)
        XCTAssertEqual(movedSnapshot.relativePath(for: duplicateURL), "Projects/API/README.md")
    }

    func testReplacementSnapshotsRebuildIndexesAfterAncestorFolderDelete() {
        let rootURL = URL(filePath: "/tmp/Workspace")
        let openFileURL = rootURL.appending(path: "Notes/Daily/Today.md")
        let originalSnapshot = makeSnapshot(
            rootURL: rootURL,
            rootNodes: [
                folder(
                    url: rootURL.appending(path: "Notes"),
                    children: [
                        folder(
                            url: rootURL.appending(path: "Notes/Daily"),
                            children: [
                                file(url: openFileURL),
                            ]
                        ),
                    ]
                ),
            ]
        )
        let deletedAncestorSnapshot = makeSnapshot(
            rootURL: rootURL,
            rootNodes: [
                folder(
                    url: rootURL.appending(path: "Archive"),
                    children: [
                        file(url: rootURL.appending(path: "Archive/Today.md")),
                    ]
                ),
            ]
        )

        XCTAssertEqual(originalSnapshot.fileURL(forRelativePath: "Notes/Daily/Today.md"), openFileURL)
        XCTAssertEqual(originalSnapshot.relativePath(for: openFileURL), "Notes/Daily/Today.md")
        XCTAssertNil(deletedAncestorSnapshot.fileURL(forRelativePath: "Notes/Daily/Today.md"))
        XCTAssertFalse(deletedAncestorSnapshot.containsFile(relativePath: "Notes/Daily/Today.md"))
        XCTAssertNil(deletedAncestorSnapshot.relativePath(for: openFileURL))
    }

    func testLargeSyntheticTreeLookupsRemainPathSpecificAndTraversalOrdered() {
        let rootURL = URL(filePath: "/tmp/Workspace")
        let rootNodes = (0..<24).map { folderIndex in
            folder(
                url: rootURL.appending(path: "Folder-\(folderIndex)"),
                children: (0..<12).map { childIndex in
                    folder(
                        url: rootURL.appending(path: "Folder-\(folderIndex)/Child-\(childIndex)"),
                        children: (0..<5).map { fileIndex in
                            file(
                                url: rootURL.appending(
                                    path: "Folder-\(folderIndex)/Child-\(childIndex)/Note-\(fileIndex).md"
                                )
                            )
                        }
                    )
                }
            )
        }
        let snapshot = makeSnapshot(rootURL: rootURL, rootNodes: rootNodes)
        let targetRelativePath = "Folder-23/Child-11/Note-4.md"
        let targetURL = rootURL.appending(path: targetRelativePath)

        XCTAssertEqual(snapshot.fileEntries().count, 1_440)
        XCTAssertEqual(snapshot.fileEntries().first?.relativePath, "Folder-0/Child-0/Note-0.md")
        XCTAssertEqual(snapshot.fileEntries().last?.relativePath, targetRelativePath)
        XCTAssertEqual(snapshot.fileURL(forRelativePath: targetRelativePath), targetURL)
        XCTAssertEqual(snapshot.relativePath(for: targetURL), targetRelativePath)
        XCTAssertNil(snapshot.fileURL(forRelativePath: "Folder-23/Child-11/Missing.md"))
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
