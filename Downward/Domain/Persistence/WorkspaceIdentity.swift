import Foundation

/// Owns the small amount of workspace identity logic needed by bookmark-backed restore and recents.
enum WorkspaceIdentity {
    nonisolated static func makePersistentID() -> String {
        UUID().uuidString.lowercased()
    }

    /// Legacy recents were keyed by absolute workspace path. Keep that deterministic identity around
    /// only as a migration fallback until the item can be adopted into a bookmark-owned workspace ID.
    nonisolated static func legacyPathID(forPath path: String) -> String {
        "legacy:\(normalizedPath(path))"
    }

    nonisolated static func normalizedPath(_ path: String) -> String {
        URL(filePath: path).standardizedFileURL.path
    }

    nonisolated static func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}
