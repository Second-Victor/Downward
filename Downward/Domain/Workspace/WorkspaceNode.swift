import Foundation

enum WorkspaceNode: Hashable, Identifiable, Sendable {
    case folder(Folder)
    case file(File)

    struct Folder: Hashable, Sendable {
        nonisolated let url: URL
        nonisolated let displayName: String
        nonisolated let children: [WorkspaceNode]
    }

    struct File: Hashable, Sendable {
        nonisolated let url: URL
        nonisolated let displayName: String
        nonisolated let subtitle: String?
    }

    nonisolated var id: URL {
        url
    }

    nonisolated var url: URL {
        switch self {
        case let .folder(folder):
            folder.url
        case let .file(file):
            file.url
        }
    }

    nonisolated var displayName: String {
        switch self {
        case let .folder(folder):
            folder.displayName
        case let .file(file):
            file.displayName
        }
    }

    nonisolated var subtitle: String? {
        if case let .file(file) = self {
            return file.subtitle
        }

        return nil
    }

    nonisolated var children: [WorkspaceNode]? {
        if case let .folder(folder) = self {
            return folder.children
        }

        return nil
    }

    nonisolated var isFolder: Bool {
        if case .folder = self {
            return true
        }

        return false
    }

    nonisolated var isFile: Bool {
        if case .file = self {
            return true
        }

        return false
    }
}
