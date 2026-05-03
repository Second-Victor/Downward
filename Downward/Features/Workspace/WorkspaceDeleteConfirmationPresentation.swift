import Foundation

struct WorkspaceDeleteConfirmationPresentation: Equatable {
    nonisolated let title: String
    nonisolated let message: String
    nonisolated let destructiveButtonTitle: String
    nonisolated let deleteActionAccessibilityHint: String
    nonisolated let requiresStrongerConfirmation: Bool

    nonisolated init(node: WorkspaceNode) {
        if node.isFolder {
            let includesContents = node.hasChildItems
            title = includesContents ? "Permanently Delete Folder and Contents?" : "Permanently Delete Folder?"
            message = includesContents
                ? "\(node.displayName) and all of its contents will be permanently deleted from Files and the underlying workspace. This cannot be undone."
                : "\(node.displayName) will be permanently deleted from Files and the underlying workspace. This cannot be undone."
            destructiveButtonTitle = includesContents
                ? "Permanently Delete Folder and Contents"
                : "Permanently Delete Folder"
            deleteActionAccessibilityHint = includesContents
                ? "Permanently deletes this folder and all of its contents from Files and the underlying workspace."
                : "Permanently deletes this folder from Files and the underlying workspace."
            requiresStrongerConfirmation = includesContents
        } else {
            title = "Permanently Delete File?"
            message = "\(node.displayName) will be permanently deleted from Files and the underlying workspace. This cannot be undone."
            destructiveButtonTitle = "Permanently Delete File"
            deleteActionAccessibilityHint = "Permanently deletes this file from Files and the underlying workspace."
            requiresStrongerConfirmation = false
        }
    }
}
