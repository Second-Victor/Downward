import Foundation

struct RecentFileItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    let workspaceRootPath: String
    let relativePath: String
    let displayName: String
    let lastOpenedAt: Date

    nonisolated var id: String {
        "\(workspaceRootPath)::\(relativePath)"
    }

    nonisolated func url(in workspaceRootURL: URL) -> URL {
        WorkspaceRelativePath.resolve(relativePath, within: workspaceRootURL)
    }

    nonisolated func node(in workspaceRootURL: URL) -> WorkspaceNode {
        .file(
            .init(
                url: url(in: workspaceRootURL),
                displayName: displayName,
                subtitle: relativePath == displayName ? nil : relativePath
            )
        )
    }
}
