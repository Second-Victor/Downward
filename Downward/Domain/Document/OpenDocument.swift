import Foundation

struct OpenDocument: Equatable, Identifiable, Sendable {
    nonisolated var url: URL
    nonisolated let workspaceRootURL: URL
    nonisolated var relativePath: String
    nonisolated var displayName: String
    nonisolated var text: String
    nonisolated var loadedVersion: DocumentVersion
    nonisolated var isDirty: Bool
    nonisolated var saveState: DocumentSaveState
    nonisolated var conflictState: DocumentConflictState

    nonisolated var id: URL {
        url
    }
}
