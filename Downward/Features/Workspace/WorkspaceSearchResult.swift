import Foundation

struct WorkspaceSearchResult: Hashable, Identifiable, Sendable {
    nonisolated let url: URL
    nonisolated let displayName: String
    nonisolated let relativePath: String
    nonisolated let modifiedAt: Date?

    nonisolated var id: String {
        relativePath
    }

    nonisolated var fullRelativePathText: String {
        relativePath
    }

    nonisolated var isAtWorkspaceRoot: Bool {
        relativePath.split(separator: "/", omittingEmptySubsequences: true).count <= 1
    }

    /// Search results need concise folder context so duplicate filenames remain easy to scan.
    nonisolated var pathContextText: String {
        guard isAtWorkspaceRoot == false else {
            return "Workspace root"
        }

        return relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .dropLast()
            .joined(separator: "/")
    }

    nonisolated var pathContextSymbolName: String {
        isAtWorkspaceRoot ? "tray.full" : "folder"
    }
}
