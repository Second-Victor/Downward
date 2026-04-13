import Foundation

/// Centralized sample fixtures for previews and stub managers during the scaffold phases.
enum PreviewSampleData {
    static let previewDate = Date(timeIntervalSince1970: 1_710_000_000)

    static let workspaceRootURL = URL(filePath: "/preview/MarkdownWorkspace")
    static let journalURL = workspaceRootURL.appending(path: "Journal")
    static let year2026URL = journalURL.appending(path: "2026")
    static let referencesURL = workspaceRootURL.appending(path: "References")
    static let archiveURL = workspaceRootURL.appending(path: "Archive")
    static let deepWorkspaceURL = URL(filePath: "/preview/DeepWorkspace")
    static let deepWorkspaceRootFolderURL = deepWorkspaceURL.appending(path: "Projects")
    static let largeWorkspaceURL = URL(filePath: "/preview/LargeWorkspace")

    static let todayDocumentURL = year2026URL.appending(path: "2026-04-13.md")
    static let ideasDocumentURL = year2026URL.appending(path: "Ideas.markdown")
    static let inboxDocumentURL = workspaceRootURL.appending(path: "Inbox.md")
    static let readmeDocumentURL = referencesURL.appending(path: "README.md")
    static let preservedConflictDocumentURL = referencesURL.appending(path: "ConflictPreserved.md")
    static let emptyWorkspaceURL = URL(filePath: "/preview/EmptyWorkspace")
    static let failedLoadDocumentURL = workspaceRootURL.appending(path: "Missing.md")

    static let invalidWorkspaceError = UserFacingError(
        title: "Workspace Needs Reconnect",
        message: "The previous folder can no longer be restored.",
        recoverySuggestion: "Reconnect the folder or clear the stored selection."
    )

    static let failedLaunchError = UserFacingError(
        title: "Unable to Restore Workspace",
        message: "The app could not finish the initial workspace restore.",
        recoverySuggestion: "Try again or use the sample workspace."
    )

    static let saveFailedError = UserFacingError(
        title: "Save Failed",
        message: "The most recent save did not complete.",
        recoverySuggestion: "Keep editing for now. Save wiring arrives in Phase 2."
    )

    static let failedLoadError = UserFacingError(
        title: "Can’t Open Document",
        message: "Missing.md could not be loaded.",
        recoverySuggestion: "Return to the browser and try again."
    )

    static let conflictError = UserFacingError(
        title: "Conflict Detected",
        message: "This file changed elsewhere after it was loaded.",
        recoverySuggestion: "Reload or choose how to resolve the newer version later."
    )

    static let emptyWorkspace = WorkspaceSnapshot(
        rootURL: emptyWorkspaceURL,
        displayName: "Empty Workspace",
        rootNodes: [],
        lastUpdated: previewDate
    )

    static let nestedWorkspace = WorkspaceSnapshot(
        rootURL: workspaceRootURL,
        displayName: "MarkdownWorkspace",
        rootNodes: [
            .folder(
                .init(
                    url: journalURL,
                    displayName: "Journal",
                    children: [
                        .folder(
                            .init(
                                url: year2026URL,
                                displayName: "2026",
                                children: [
                                    .file(
                                        .init(
                                            url: todayDocumentURL,
                                            displayName: "2026-04-13.md",
                                            subtitle: "Daily note"
                                        )
                                    ),
                                    .file(
                                        .init(
                                            url: ideasDocumentURL,
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
            .folder(
                .init(
                    url: referencesURL,
                    displayName: "References",
                    children: [
                        .file(
                            .init(
                                url: readmeDocumentURL,
                                displayName: "README.md",
                                subtitle: "Project overview"
                            )
                        ),
                    ]
                )
            ),
            .folder(
                .init(
                    url: archiveURL,
                    displayName: "Archive",
                    children: []
                )
            ),
            .file(
                .init(
                    url: inboxDocumentURL,
                    displayName: "Inbox.md",
                    subtitle: "Root document"
                )
            ),
        ],
        lastUpdated: previewDate
    )

    static let deepWorkspace = WorkspaceSnapshot(
        rootURL: deepWorkspaceURL,
        displayName: "Deep Workspace",
        rootNodes: [
            .folder(
                .init(
                    url: deepWorkspaceRootFolderURL,
                    displayName: "Projects",
                    children: [
                        .folder(
                            .init(
                                url: deepWorkspaceRootFolderURL.appending(path: "iOS"),
                                displayName: "iOS",
                                children: [
                                    .folder(
                                        .init(
                                            url: deepWorkspaceRootFolderURL.appending(path: "iOS/Downward"),
                                            displayName: "Downward",
                                            children: [
                                                .folder(
                                                    .init(
                                                        url: deepWorkspaceRootFolderURL.appending(path: "iOS/Downward/Notes"),
                                                        displayName: "Notes",
                                                        children: [
                                                            .file(
                                                                .init(
                                                                    url: deepWorkspaceRootFolderURL.appending(path: "iOS/Downward/Notes/Roadmap.md"),
                                                                    displayName: "Roadmap.md",
                                                                    subtitle: "Sprint notes"
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
                    ]
                )
            ),
        ],
        lastUpdated: previewDate
    )

    static let largeWorkspace = WorkspaceSnapshot(
        rootURL: largeWorkspaceURL,
        displayName: "Large Workspace",
        rootNodes: largeWorkspaceNodes(),
        lastUpdated: previewDate
    )

    static let cleanDocument = OpenDocument(
        url: inboxDocumentURL,
        workspaceRootURL: workspaceRootURL,
        relativePath: "Inbox.md",
        displayName: "Inbox.md",
        text: """
        # Inbox

        - Capture loose ideas quickly.
        - Keep the editor plain and dependable.
        """,
        loadedVersion: makeVersion("preview-v1", fileSize: 96),
        isDirty: false,
        saveState: .saved(previewDate),
        conflictState: .none
    )

    static let dirtyDocument = OpenDocument(
        url: todayDocumentURL,
        workspaceRootURL: workspaceRootURL,
        relativePath: "Journal/2026/2026-04-13.md",
        displayName: "2026-04-13.md",
        text: """
        # Monday

        Shipping the navigation skeleton today.

        - Root launch states
        - Workspace browser shell
        - Editor placeholder flow
        """,
        loadedVersion: makeVersion("preview-v2", fileSize: 128),
        isDirty: true,
        saveState: .unsaved,
        conflictState: .none
    )

    static let failedSaveDocument = OpenDocument(
        url: ideasDocumentURL,
        workspaceRootURL: workspaceRootURL,
        relativePath: "Journal/2026/Ideas.markdown",
        displayName: "Ideas.markdown",
        text: """
        # Ideas

        Save is not wired yet, but failure UI is scaffolded.
        """,
        loadedVersion: makeVersion("preview-v3", fileSize: 72),
        isDirty: true,
        saveState: .failed(saveFailedError),
        conflictState: .none
    )

    static let conflictDocument = OpenDocument(
        url: readmeDocumentURL,
        workspaceRootURL: workspaceRootURL,
        relativePath: "References/README.md",
        displayName: "README.md",
        text: """
        # README

        A newer disk version exists in the future save pipeline.
        """,
        loadedVersion: makeVersion("preview-v4", fileSize: 80),
        isDirty: true,
        saveState: .idle,
        conflictState: .needsResolution(
            DocumentConflict(
                kind: .modifiedOnDisk,
                error: conflictError
            )
        )
    )

    static let preservedConflictDocument = OpenDocument(
        url: preservedConflictDocumentURL,
        workspaceRootURL: workspaceRootURL,
        relativePath: "References/ConflictPreserved.md",
        displayName: "ConflictPreserved.md",
        text: """
        # Conflict Preserved

        Local edits are preserved, but the disk version still needs an explicit decision.
        """,
        loadedVersion: makeVersion("preview-v5", fileSize: 108),
        isDirty: true,
        saveState: .unsaved,
        conflictState: .preservingEdits(
            DocumentConflict(
                kind: .modifiedOnDisk,
                error: conflictError
            )
        )
    )

    static let missingDocument = OpenDocument(
        url: failedLoadDocumentURL,
        workspaceRootURL: workspaceRootURL,
        relativePath: "Missing.md",
        displayName: "Missing.md",
        text: """
        # Missing

        These edits only exist in memory after the file disappeared on disk.
        """,
        loadedVersion: makeVersion("preview-v6", fileSize: 90),
        isDirty: true,
        saveState: .unsaved,
        conflictState: .needsResolution(
            DocumentConflict(
                kind: .missingOnDisk,
                error: UserFacingError(
                    title: "File No Longer Exists",
                    message: "Missing.md was moved or deleted outside the app.",
                    recoverySuggestion: "Reload if it returns, overwrite to recreate it, or keep your edits in memory for now."
                )
            )
        )
    )

    static let sampleDocumentsByURL: [URL: OpenDocument] = [
        cleanDocument.url: cleanDocument,
        dirtyDocument.url: dirtyDocument,
        failedSaveDocument.url: failedSaveDocument,
        conflictDocument.url: conflictDocument,
        preservedConflictDocument.url: preservedConflictDocument,
        missingDocument.url: missingDocument,
    ]

    private static func makeVersion(_ digest: String, fileSize: Int) -> DocumentVersion {
        DocumentVersion(
            contentModificationDate: previewDate,
            fileSize: fileSize,
            contentDigest: digest
        )
    }

    private static func largeWorkspaceNodes() -> [WorkspaceNode] {
        let folders = (1...8).map { section -> WorkspaceNode in
            let folderURL = largeWorkspaceURL.appending(path: "Section \(section)")
            let children = (1...6).map { item -> WorkspaceNode in
                WorkspaceNode.file(
                    .init(
                        url: folderURL.appending(path: "Note \(item).md"),
                        displayName: "Note \(item).md",
                        subtitle: "Section \(section)"
                    )
                )
            }

            return .folder(
                .init(
                    url: folderURL,
                    displayName: "Section \(section)",
                    children: children
                )
            )
        }

        let rootFiles = (1...4).map { item -> WorkspaceNode in
            WorkspaceNode.file(
                .init(
                    url: largeWorkspaceURL.appending(path: "Inbox \(item).md"),
                    displayName: "Inbox \(item).md",
                    subtitle: "Root"
                )
            )
        }

        return folders + rootFiles
    }
}
