import Foundation

protocol WorkspaceEnumerating: Sendable {
    nonisolated func makeSnapshot(rootURL: URL, displayName: String) throws -> WorkspaceSnapshot
}

/// Walks the workspace recursively, keeping all real folders while filtering files down to supported types.
struct LiveWorkspaceEnumerator: WorkspaceEnumerating {
    nonisolated func makeSnapshot(rootURL: URL, displayName: String) throws -> WorkspaceSnapshot {
        let rootNodes = try makeNodes(in: rootURL)

        return WorkspaceSnapshot(
            rootURL: rootURL,
            displayName: displayName,
            rootNodes: rootNodes,
            lastUpdated: Date()
        )
    }

    nonisolated private func makeNodes(in directoryURL: URL) throws -> [WorkspaceNode] {
        try Task.checkCancellation()

        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .localizedNameKey,
            .nameKey,
        ]

        let childURLs = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        )

        var nodes: [WorkspaceNode] = []
        nodes.reserveCapacity(childURLs.count)

        for childURL in childURLs {
            try Task.checkCancellation()

            let resourceValues = try childURL.resourceValues(forKeys: resourceKeys)
            let displayName = resourceValues.localizedName ?? resourceValues.name ?? childURL.lastPathComponent

            if resourceValues.isDirectory == true {
                let children = try makeNodes(in: childURL)
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
                        subtitle: nil
                    )
                )
            )
        }

        return nodes.sorted(by: workspaceNodeSortPredicate)
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
