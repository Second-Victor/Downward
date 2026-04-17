import Foundation

struct WorkspaceSearchResult: Hashable, Identifiable, Sendable {
    nonisolated let url: URL
    nonisolated let displayName: String
    nonisolated let relativePath: String
    nonisolated let modifiedAt: Date?

    nonisolated var id: String {
        relativePath
    }

    /// Search results need explicit path context so duplicate filenames remain distinguishable.
    nonisolated var pathContextText: String {
        relativePath == displayName ? "Workspace root" : relativePath
    }
}
