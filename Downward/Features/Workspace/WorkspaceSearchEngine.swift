import Foundation

/// Filters the current in-memory workspace snapshot without touching the file system.
enum WorkspaceSearchEngine {
    nonisolated static func results(
        in snapshot: WorkspaceSnapshot,
        matching rawQuery: String
    ) -> [WorkspaceSearchResult] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            return []
        }

        var results: [WorkspaceSearchResult] = []
        appendMatches(
            from: snapshot.rootNodes,
            query: query,
            within: snapshot.rootURL,
            results: &results
        )
        return results
    }

    nonisolated private static func appendMatches(
        from nodes: [WorkspaceNode],
        query: String,
        within workspaceRootURL: URL,
        results: inout [WorkspaceSearchResult]
    ) {
        for node in nodes {
            switch node {
            case let .folder(folder):
                appendMatches(
                    from: folder.children,
                    query: query,
                    within: workspaceRootURL,
                    results: &results
                )
            case let .file(file):
                guard let relativePath = WorkspaceRelativePath.make(
                    for: file.url,
                    within: workspaceRootURL
                ) else {
                    continue
                }

                guard matches(fileName: file.displayName, relativePath: relativePath, query: query) else {
                    continue
                }

                results.append(
                    WorkspaceSearchResult(
                        url: file.url,
                        displayName: file.displayName,
                        relativePath: relativePath,
                        modifiedAt: file.modifiedAt
                    )
                )
            }
        }
    }

    nonisolated private static func matches(
        fileName: String,
        relativePath: String,
        query: String
    ) -> Bool {
        fileName.localizedStandardContains(query) || relativePath.localizedStandardContains(query)
    }
}
