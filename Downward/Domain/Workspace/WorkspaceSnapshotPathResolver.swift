import Foundation

/// Resolves relative-path identity from the already-accepted in-memory workspace tree.
///
/// This is intentionally separate from `WorkspaceRelativePath`, which is the stronger filesystem
/// trust boundary. Coordinator/session/navigation code can use snapshot-backed identity for URLs
/// that are already present in `WorkspaceSnapshot` without re-validating against live disk state.
extension WorkspaceSnapshot {
    nonisolated func relativePath(for url: URL) -> String? {
        let normalizedPath = WorkspaceIdentity.normalizedPath(for: url)
        return indexedRelativePath(forNormalizedNodePath: normalizedPath) ?? relativePath(
            forNormalizedURL: normalizedPath,
            in: rootNodes,
            parentPath: nil
        )
    }

    nonisolated func fileEntries() -> [FileEntry] {
        indexedFileEntries()
    }

    nonisolated func relativeFilePaths() -> [String] {
        indexedFileEntries().map(\.relativePath)
    }

    nonisolated func fileURL(forRelativePath relativePath: String) -> URL? {
        indexedFileURL(forRelativePath: relativePath) ?? nodeURL(
            forRelativePath: relativePath,
            matchingFolder: false,
            in: rootNodes,
            parentPath: nil
        )
    }

    nonisolated func containsFile(relativePath: String) -> Bool {
        indexedContainsFile(relativePath: relativePath) || nodeURL(
            forRelativePath: relativePath,
            matchingFolder: false,
            in: rootNodes,
            parentPath: nil
        ) != nil
    }

    /// Hot-path callers that already traverse the snapshot tree should carry relative paths
    /// forward from the traversal itself rather than resolving them later with another tree walk.
    nonisolated func forEachFile(
        _ visit: (FileEntry) -> Void
    ) {
        for entry in indexedFileEntries() {
            visit(entry)
        }
    }

    nonisolated private func relativePath(
        forNormalizedURL normalizedURL: String,
        in nodes: [WorkspaceNode],
        parentPath: String?
    ) -> String? {
        for node in nodes {
            let currentPath = joinedPath(parentPath, node.url.lastPathComponent)
            if WorkspaceIdentity.normalizedPath(for: node.url) == normalizedURL {
                return currentPath
            }

            if let children = node.children,
               let descendantPath = relativePath(
                   forNormalizedURL: normalizedURL,
                   in: children,
                   parentPath: currentPath
               ) {
                return descendantPath
            }
        }

        return nil
    }

    nonisolated private func forEachFile(
        in nodes: [WorkspaceNode],
        parentPath: String?,
        visit: (FileEntry) -> Void
    ) {
        for node in nodes {
            let currentPath = joinedPath(parentPath, node.url.lastPathComponent)

            switch node {
            case let .folder(folder):
                forEachFile(
                    in: folder.children,
                    parentPath: currentPath,
                    visit: visit
                )
            case let .file(file):
                visit(
                    FileEntry(
                        url: file.url,
                        displayName: file.displayName,
                        modifiedAt: file.modifiedAt,
                        relativePath: currentPath
                    )
                )
            }
        }
    }

    nonisolated private func nodeURL(
        forRelativePath relativePath: String,
        matchingFolder: Bool,
        in nodes: [WorkspaceNode],
        parentPath: String?
    ) -> URL? {
        for node in nodes {
            let currentPath = joinedPath(parentPath, node.url.lastPathComponent)
            if currentPath == relativePath, node.isFolder == matchingFolder {
                return node.url
            }

            if let children = node.children,
               let descendantURL = nodeURL(
                   forRelativePath: relativePath,
                   matchingFolder: matchingFolder,
                   in: children,
                   parentPath: currentPath
               ) {
                return descendantURL
            }
        }

        return nil
    }

    nonisolated private func joinedPath(_ parentPath: String?, _ component: String) -> String {
        guard let parentPath, parentPath.isEmpty == false else {
            return component
        }

        return "\(parentPath)/\(component)"
    }
}
