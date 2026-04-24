import Foundation

enum WorkspaceMutationPolicy {
    static func browserItemKind(for url: URL, in snapshot: WorkspaceSnapshot?) -> WorkspaceBrowserItemKind {
        guard
            let snapshot,
            let node = workspaceNode(at: url, in: snapshot.rootNodes)
        else {
            return .file
        }

        return node.isFolder ? .folder : .file
    }

    static func blockingEditorMutationError(
        action: WorkspaceMutationAction,
        targetKind: WorkspaceBrowserItemKind,
        targetURL: URL,
        targetRelativePath: String?,
        openDocument: OpenDocument?
    ) -> UserFacingError? {
        guard let openDocument else {
            return nil
        }

        let isTargetingOpenDocument = openDocument.url == targetURL
            || targetRelativePath.map { isSameOrDescendantPath(openDocument.relativePath, of: $0) } == true
        guard isTargetingOpenDocument else {
            return nil
        }

        if openDocument.saveState == .saving {
            return UserFacingError(
                title: action.title(for: targetKind),
                message: "\(openDocument.displayName) is still saving.",
                recoverySuggestion: action.savingRecoverySuggestion
            )
        }

        switch action {
        case .rename, .move:
            guard openDocument.conflictState.isConflicted else {
                return nil
            }

            return UserFacingError(
                title: action.title(for: targetKind),
                message: targetKind == .folder
                    ? "Resolve the current conflict before \(action.verb) the folder containing \(openDocument.displayName)."
                    : "Resolve the current conflict before \(action.verb) \(openDocument.displayName).",
                recoverySuggestion: "Finish resolving the document, then try again."
            )
        case .delete:
            guard openDocument.isDirty || openDocument.conflictState.isConflicted else {
                return nil
            }

            return UserFacingError(
                title: action.title(for: targetKind),
                message: targetKind == .folder
                    ? "Finish with \(openDocument.displayName) before deleting its folder from the browser."
                    : "Finish with \(openDocument.displayName) before deleting it from the browser.",
                recoverySuggestion: "Let it save or resolve the conflict first."
            )
        }
    }

    private static func isSameOrDescendantPath(_ path: String, of prefix: String) -> Bool {
        path == prefix || path.hasPrefix("\(prefix)/")
    }

    private static func workspaceNode(at url: URL, in nodes: [WorkspaceNode]) -> WorkspaceNode? {
        for node in nodes {
            if WorkspaceIdentity.normalizedPath(for: node.url) == WorkspaceIdentity.normalizedPath(for: url) {
                return node
            }

            guard case let .folder(folder) = node,
                  let descendant = workspaceNode(at: url, in: folder.children) else {
                continue
            }

            return descendant
        }

        return nil
    }
}

enum WorkspaceMutationAction {
    case rename
    case move
    case delete

    var verb: String {
        switch self {
        case .rename:
            "renaming"
        case .move:
            "moving"
        case .delete:
            "deleting"
        }
    }

    var savingRecoverySuggestion: String {
        switch self {
        case .rename:
            "Wait for the current save to finish, then try renaming it again."
        case .move:
            "Wait for the current save to finish, then try moving it again."
        case .delete:
            "Wait for the current save to finish, then try deleting it again."
        }
    }

    func title(for targetKind: WorkspaceBrowserItemKind) -> String {
        switch self {
        case .rename:
            targetKind.renameActionTitle
        case .move:
            targetKind.moveActionTitle
        case .delete:
            targetKind.deleteActionTitle
        }
    }
}

enum WorkspaceBrowserItemKind: Equatable {
    case file
    case folder

    var moveActionTitle: String {
        switch self {
        case .file:
            "Move File"
        case .folder:
            "Move Folder"
        }
    }

    var renameActionTitle: String {
        switch self {
        case .file:
            "Rename File"
        case .folder:
            "Rename Folder"
        }
    }

    var deleteActionTitle: String {
        switch self {
        case .file:
            "Delete File"
        case .folder:
            "Delete Folder"
        }
    }
}
