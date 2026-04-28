import Foundation

struct WorkspaceMutationOperation {
    let errorContext: String
    let fallbackError: AppError
    let execute: @MainActor () async throws -> WorkspaceMutationResult
}

@MainActor
struct WorkspaceMutationService {
    private let workspaceManager: any WorkspaceManager

    init(workspaceManager: any WorkspaceManager) {
        self.workspaceManager = workspaceManager
    }

    func createFile(
        named proposedName: String,
        in folderURL: URL?,
        initialContent: WorkspaceCreatedFileInitialContent = .empty
    ) -> WorkspaceMutationOperation {
        WorkspaceMutationOperation(
            errorContext: "Creating file",
            fallbackError: WorkspaceMutationErrorPresenter.createFileFallbackError(named: proposedName)
        ) {
            try await workspaceManager.createFile(
                named: proposedName,
                in: folderURL,
                initialContent: initialContent
            )
        }
    }

    func createFolder(
        named proposedName: String,
        in folderURL: URL?
    ) -> WorkspaceMutationOperation {
        WorkspaceMutationOperation(
            errorContext: "Creating folder",
            fallbackError: WorkspaceMutationErrorPresenter.createFolderFallbackError(named: proposedName)
        ) {
            try await workspaceManager.createFolder(named: proposedName, in: folderURL)
        }
    }

    func renameFile(
        at url: URL,
        to proposedName: String,
        targetKind: WorkspaceBrowserItemKind
    ) -> WorkspaceMutationOperation {
        WorkspaceMutationOperation(
            errorContext: "Renaming file",
            fallbackError: WorkspaceMutationErrorPresenter.renameFallbackError(targetKind: targetKind, url: url)
        ) {
            try await workspaceManager.renameFile(at: url, to: proposedName)
        }
    }

    func moveItem(
        at url: URL,
        toFolder destinationFolderURL: URL?,
        targetKind: WorkspaceBrowserItemKind
    ) -> WorkspaceMutationOperation {
        WorkspaceMutationOperation(
            errorContext: "Moving item",
            fallbackError: WorkspaceMutationErrorPresenter.moveFallbackError(targetKind: targetKind, url: url)
        ) {
            try await workspaceManager.moveItem(at: url, toFolder: destinationFolderURL)
        }
    }

    func deleteFile(
        at url: URL,
        targetKind: WorkspaceBrowserItemKind
    ) -> WorkspaceMutationOperation {
        WorkspaceMutationOperation(
            errorContext: "Deleting file",
            fallbackError: WorkspaceMutationErrorPresenter.deleteFallbackError(targetKind: targetKind, url: url)
        ) {
            try await workspaceManager.deleteFile(at: url)
        }
    }
}
