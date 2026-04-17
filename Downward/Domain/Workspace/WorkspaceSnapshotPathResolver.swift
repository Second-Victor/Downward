import Foundation

/// Resolves relative-path identity from the already-accepted in-memory workspace tree.
///
/// This is intentionally separate from `WorkspaceRelativePath`, which is the stronger filesystem
/// trust boundary. Coordinator/session/navigation code can use snapshot-backed identity for URLs
/// that are already present in `WorkspaceSnapshot` without re-validating against live disk state.
extension WorkspaceSnapshot {
    nonisolated func relativePath(for url: URL) -> String? {
        relativePath(for: url.standardizedFileURL, in: rootNodes, parentPath: nil)
    }

    nonisolated func fileURL(forRelativePath relativePath: String) -> URL? {
        nodeURL(forRelativePath: relativePath, matchingFolder: false, in: rootNodes, parentPath: nil)
    }

    nonisolated func containsFile(relativePath: String) -> Bool {
        fileURL(forRelativePath: relativePath) != nil
    }

    nonisolated private func relativePath(
        for url: URL,
        in nodes: [WorkspaceNode],
        parentPath: String?
    ) -> String? {
        for node in nodes {
            let currentPath = joinedPath(parentPath, node.url.lastPathComponent)
            if node.url.standardizedFileURL == url {
                return currentPath
            }

            if let children = node.children,
               let descendantPath = relativePath(
                   for: url,
                   in: children,
                   parentPath: currentPath
               ) {
                return descendantPath
            }
        }

        return nil
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
