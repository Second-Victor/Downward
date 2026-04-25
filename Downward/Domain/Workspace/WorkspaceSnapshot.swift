import Foundation

struct WorkspaceSnapshot: Equatable, Sendable {
    struct FileEntry: Equatable, Sendable {
        nonisolated let url: URL
        nonisolated let displayName: String
        nonisolated let modifiedAt: Date?
        nonisolated let relativePath: String
    }

    struct LookupIndex: Equatable, Sendable {
        nonisolated let fileEntriesInTraversalOrder: [FileEntry]
        nonisolated private let fileEntryByRelativePath: [String: FileEntry]
        nonisolated private let relativePathByNormalizedNodePath: [String: String]

        nonisolated init(rootNodes: [WorkspaceNode]) {
            var fileEntriesInTraversalOrder: [FileEntry] = []
            var fileEntryByRelativePath: [String: FileEntry] = [:]
            var relativePathByNormalizedNodePath: [String: String] = [:]

            Self.index(
                nodes: rootNodes,
                parentPath: nil,
                fileEntriesInTraversalOrder: &fileEntriesInTraversalOrder,
                fileEntryByRelativePath: &fileEntryByRelativePath,
                relativePathByNormalizedNodePath: &relativePathByNormalizedNodePath
            )

            self.fileEntriesInTraversalOrder = fileEntriesInTraversalOrder
            self.fileEntryByRelativePath = fileEntryByRelativePath
            self.relativePathByNormalizedNodePath = relativePathByNormalizedNodePath
        }

        nonisolated func relativePath(forNormalizedNodePath normalizedPath: String) -> String? {
            relativePathByNormalizedNodePath[normalizedPath]
        }

        nonisolated func fileURL(forRelativePath relativePath: String) -> URL? {
            fileEntryByRelativePath[relativePath]?.url
        }

        nonisolated func containsFile(relativePath: String) -> Bool {
            fileEntryByRelativePath[relativePath] != nil
        }

        nonisolated private static func index(
            nodes: [WorkspaceNode],
            parentPath: String?,
            fileEntriesInTraversalOrder: inout [FileEntry],
            fileEntryByRelativePath: inout [String: FileEntry],
            relativePathByNormalizedNodePath: inout [String: String]
        ) {
            for node in nodes {
                let currentPath = joinedPath(parentPath, node.url.lastPathComponent)
                let normalizedNodePath = WorkspaceIdentity.normalizedPath(for: node.url)

                // Keep the first pre-order match so indexed lookup mirrors the recursive fallback.
                if relativePathByNormalizedNodePath[normalizedNodePath] == nil {
                    relativePathByNormalizedNodePath[normalizedNodePath] = currentPath
                }

                switch node {
                case let .folder(folder):
                    index(
                        nodes: folder.children,
                        parentPath: currentPath,
                        fileEntriesInTraversalOrder: &fileEntriesInTraversalOrder,
                        fileEntryByRelativePath: &fileEntryByRelativePath,
                        relativePathByNormalizedNodePath: &relativePathByNormalizedNodePath
                    )
                case let .file(file):
                    let entry = FileEntry(
                        url: file.url,
                        displayName: file.displayName,
                        modifiedAt: file.modifiedAt,
                        relativePath: currentPath
                    )
                    fileEntriesInTraversalOrder.append(entry)

                    if fileEntryByRelativePath.keys.contains(currentPath) == false {
                        fileEntryByRelativePath[currentPath] = entry
                    }
                }
            }
        }

        nonisolated private static func joinedPath(_ parentPath: String?, _ component: String) -> String {
            guard let parentPath, parentPath.isEmpty == false else {
                return component
            }

            return "\(parentPath)/\(component)"
        }
    }

    nonisolated let workspaceID: String
    nonisolated let recentFileLookupPaths: [String]
    nonisolated let rootURL: URL
    nonisolated let displayName: String
    nonisolated let rootNodes: [WorkspaceNode]
    nonisolated let lastUpdated: Date
    nonisolated let lookupIndex: LookupIndex

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
        self.lookupIndex = LookupIndex(rootNodes: rootNodes)
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
