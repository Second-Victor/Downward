import Foundation

enum WorkspaceMutationErrorPresenter {
    static func createFileFallbackError(named proposedName: String) -> AppError {
        AppError.fileOperationFailed(
            action: "Create File",
            name: proposedName.isEmpty ? "Untitled.md" : proposedName,
            details: "The file could not be created."
        )
    }

    static func createFolderFallbackError(named proposedName: String) -> AppError {
        AppError.fileOperationFailed(
            action: "Create Folder",
            name: proposedName.isEmpty ? "Untitled Folder" : proposedName,
            details: "The folder could not be created."
        )
    }

    static func renameFallbackError(targetKind: WorkspaceBrowserItemKind, url: URL) -> AppError {
        AppError.fileOperationFailed(
            action: targetKind.renameActionTitle,
            name: url.lastPathComponent,
            details: targetKind == .folder
                ? "The folder could not be renamed."
                : "The file could not be renamed."
        )
    }

    static func moveFallbackError(targetKind: WorkspaceBrowserItemKind, url: URL) -> AppError {
        AppError.fileOperationFailed(
            action: targetKind.moveActionTitle,
            name: url.lastPathComponent,
            details: targetKind == .folder
                ? "The folder could not be moved."
                : "The file could not be moved."
        )
    }

    static func deleteFallbackError(targetKind: WorkspaceBrowserItemKind, url: URL) -> AppError {
        AppError.fileOperationFailed(
            action: targetKind.deleteActionTitle,
            name: url.lastPathComponent,
            details: targetKind == .folder
                ? "The folder could not be deleted."
                : "The file could not be deleted."
        )
    }
}
