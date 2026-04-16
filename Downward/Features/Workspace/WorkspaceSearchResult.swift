import Foundation

struct WorkspaceSearchResult: Hashable, Identifiable, Sendable {
    nonisolated let url: URL
    nonisolated let displayName: String
    nonisolated let relativePath: String

    nonisolated var id: String {
        relativePath
    }

    nonisolated var node: WorkspaceNode {
        .file(
            .init(
                url: url,
                displayName: displayName,
                subtitle: relativePath == displayName ? nil : relativePath
            )
        )
    }
}
