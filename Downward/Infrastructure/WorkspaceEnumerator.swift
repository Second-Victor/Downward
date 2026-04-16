import Foundation

protocol WorkspaceEnumerating: Sendable {
    nonisolated func makeSnapshot(rootURL: URL, displayName: String) throws -> WorkspaceSnapshot
}

/// Walks the workspace recursively, keeping all real folders while filtering files down to supported types.
struct LiveWorkspaceEnumerator: WorkspaceEnumerating {
    nonisolated func makeSnapshot(rootURL: URL, displayName: String) throws -> WorkspaceSnapshot {
        let rootNodes = try makeNodes(in: rootURL, allowsPartialFailure: false) ?? []

        return WorkspaceSnapshot(
            rootURL: rootURL,
            displayName: displayName,
            rootNodes: rootNodes,
            lastUpdated: Date()
        )
    }

    /// Enumeration policy:
    /// - unreadable workspace root: fail the refresh because there is no trustworthy workspace view
    /// - unreadable descendant: skip that node/subtree and keep remaining siblings
    /// - hidden/package descendants: skip intentionally because they are not part of the user-facing tree
    nonisolated private func makeNodes(
        in directoryURL: URL,
        allowsPartialFailure: Bool
    ) throws -> [WorkspaceNode]? {
        try Task.checkCancellation()

        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isHiddenKey,
            .isPackageKey,
            .localizedNameKey,
            .nameKey,
            .contentModificationDateKey,
        ]

        let childURLs: [URL]
        do {
            childURLs = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: []
            )
        } catch {
            guard allowsPartialFailure else {
                throw error
            }

            guard Self.shouldSkipDescendantFailure(error) else {
                throw error
            }

            return nil
        }

        var nodes: [WorkspaceNode] = []
        nodes.reserveCapacity(childURLs.count)

        for childURL in childURLs {
            try Task.checkCancellation()

            let resourceValues: URLResourceValues
            do {
                resourceValues = try childURL.resourceValues(forKeys: resourceKeys)
            } catch {
                guard Self.shouldSkipDescendantFailure(error) else {
                    throw error
                }

                continue
            }
            let displayName = resourceValues.localizedName ?? resourceValues.name ?? childURL.lastPathComponent

            guard Self.shouldSkipNode(
                at: childURL,
                displayName: displayName,
                resourceValues: resourceValues
            ) == false else {
                continue
            }

            if resourceValues.isDirectory == true {
                guard let children = try makeNodes(in: childURL, allowsPartialFailure: true) else {
                    continue
                }
                nodes.append(
                    .folder(
                        .init(
                            url: childURL,
                            displayName: displayName,
                            children: children
                        )
                    )
                )
                continue
            }

            guard resourceValues.isRegularFile == true else {
                continue
            }

            guard SupportedFileType.isSupported(url: childURL) else {
                continue
            }

            nodes.append(
                .file(
                    .init(
                        url: childURL,
                        displayName: displayName,
                        subtitle: nil,
                        modifiedAt: resourceValues.contentModificationDate
                    )
                )
            )
        }

        return nodes.sorted(by: workspaceNodeSortPredicate)
    }

    nonisolated private static func shouldSkipNode(
        at url: URL,
        displayName: String,
        resourceValues: URLResourceValues
    ) -> Bool {
        if resourceValues.isHidden == true || displayName.hasPrefix(".") {
            return true
        }

        if resourceValues.isPackage == true {
            return true
        }

        return false
    }

    nonisolated private static func shouldSkipDescendantFailure(_ error: Error) -> Bool {
        (error is CancellationError) == false
    }
}

struct StubWorkspaceEnumerator: WorkspaceEnumerating {
    let snapshot: WorkspaceSnapshot

    nonisolated func makeSnapshot(rootURL: URL, displayName: String) throws -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            rootURL: rootURL,
            displayName: displayName,
            rootNodes: snapshot.rootNodes,
            lastUpdated: snapshot.lastUpdated
        )
    }
}

nonisolated private func workspaceNodeSortPredicate(_ lhs: WorkspaceNode, _ rhs: WorkspaceNode) -> Bool {
    switch (lhs, rhs) {
    case (.folder, .file):
        return true
    case (.file, .folder):
        return false
    default:
        let nameComparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
    }
}
