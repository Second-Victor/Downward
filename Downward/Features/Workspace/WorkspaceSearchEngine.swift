import Foundation

protocol WorkspaceSearching: Sendable {
    nonisolated func results(
        in snapshot: WorkspaceSnapshot,
        matching rawQuery: String
    ) -> [WorkspaceSearchResult]
}

struct LiveWorkspaceSearcher: WorkspaceSearching {
    nonisolated func results(
        in snapshot: WorkspaceSnapshot,
        matching rawQuery: String
    ) -> [WorkspaceSearchResult] {
        WorkspaceSearchEngine.results(in: snapshot, matching: rawQuery)
    }
}

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
            in: snapshot,
            results: &results
        )
        return results
    }

    nonisolated private static func appendMatches(
        from nodes: [WorkspaceNode],
        query: String,
        in snapshot: WorkspaceSnapshot,
        results: inout [WorkspaceSearchResult]
    ) {
        for node in nodes {
            switch node {
            case let .folder(folder):
                appendMatches(
                    from: folder.children,
                    query: query,
                    in: snapshot,
                    results: &results
                )
            case let .file(file):
                guard let relativePath = snapshot.relativePath(for: file.url) else {
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
