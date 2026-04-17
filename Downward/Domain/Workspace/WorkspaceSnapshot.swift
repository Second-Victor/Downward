import Foundation

struct WorkspaceSnapshot: Equatable, Sendable {
    nonisolated let workspaceID: String
    nonisolated let recentFileLookupPaths: [String]
    nonisolated let rootURL: URL
    nonisolated let displayName: String
    nonisolated let rootNodes: [WorkspaceNode]
    nonisolated let lastUpdated: Date

    nonisolated init(
        workspaceID: String? = nil,
        recentFileLookupPaths: [String]? = nil,
        rootURL: URL,
        displayName: String,
        rootNodes: [WorkspaceNode],
        lastUpdated: Date
    ) {
        let normalizedRootPath = WorkspaceIdentity.normalizedPath(for: rootURL)
        self.workspaceID = workspaceID ?? WorkspaceIdentity.legacyPathID(forPath: normalizedRootPath)
        self.recentFileLookupPaths = Self.normalizedLookupPaths(
            recentFileLookupPaths ?? [normalizedRootPath]
        )
        self.rootURL = rootURL
        self.displayName = displayName
        self.rootNodes = rootNodes
        self.lastUpdated = lastUpdated
    }

    nonisolated var isEmpty: Bool {
        rootNodes.isEmpty
    }

    nonisolated private static func normalizedLookupPaths(_ paths: [String]) -> [String] {
        var seenPaths = Set<String>()
        return paths.compactMap { rawPath in
            let normalizedPath = WorkspaceIdentity.normalizedPath(rawPath)
            guard seenPaths.insert(normalizedPath).inserted else {
                return nil
            }

            return normalizedPath
        }
    }
}
