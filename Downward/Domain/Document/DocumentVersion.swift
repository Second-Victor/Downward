import Foundation

/// Captures the last confirmed on-disk state of an open document for conflict checks.
struct DocumentVersion: Equatable, Sendable {
    let contentModificationDate: Date?
    let fileSize: Int
    let contentDigest: String

    nonisolated func matchesCurrentDisk(_ currentVersion: DocumentVersion) -> Bool {
        contentDigest == currentVersion.contentDigest && fileSize == currentVersion.fileSize
    }
}
