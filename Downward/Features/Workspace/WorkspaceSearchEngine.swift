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
        snapshot.forEachFile { entry in
            guard matches(fileName: entry.displayName, relativePath: entry.relativePath, query: query) else {
                return
            }

            results.append(
                WorkspaceSearchResult(
                    url: entry.url,
                    displayName: entry.displayName,
                    relativePath: entry.relativePath,
                    modifiedAt: entry.modifiedAt
                )
            )
        }
        return results
    }

    nonisolated private static func matches(
        fileName: String,
        relativePath: String,
        query: String
    ) -> Bool {
        fileName.localizedStandardContains(query) || relativePath.localizedStandardContains(query)
    }
}
