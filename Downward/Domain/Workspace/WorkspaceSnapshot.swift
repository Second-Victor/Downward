import Foundation

struct WorkspaceSnapshot: Equatable, Sendable {
    nonisolated let rootURL: URL
    nonisolated let displayName: String
    nonisolated let rootNodes: [WorkspaceNode]
    nonisolated let lastUpdated: Date

    nonisolated var isEmpty: Bool {
        rootNodes.isEmpty
    }
}
