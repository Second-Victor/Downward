import Foundation

enum WorkspaceNode: Hashable, Identifiable, Sendable {
    case folder(Folder)
    case file(File)

    struct Folder: Hashable, Sendable {
        nonisolated let url: URL
        nonisolated let displayName: String
        nonisolated let children: [WorkspaceNode]
        nonisolated let containsAnyFilesystemItems: Bool

        nonisolated init(
            url: URL,
            displayName: String,
            children: [WorkspaceNode],
            containsAnyFilesystemItems: Bool? = nil
        ) {
            self.url = url
            self.displayName = displayName
            self.children = children
            self.containsAnyFilesystemItems = containsAnyFilesystemItems ?? (children.isEmpty == false)
        }
    }

    struct File: Hashable, Sendable {
        nonisolated let url: URL
        nonisolated let displayName: String
        nonisolated let subtitle: String?
        nonisolated let modifiedAt: Date?

        nonisolated init(
            url: URL,
            displayName: String,
            subtitle: String?,
            modifiedAt: Date? = nil
        ) {
            self.url = url
            self.displayName = displayName
            self.subtitle = subtitle
            self.modifiedAt = modifiedAt
        }
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

    nonisolated var itemCount: Int? {
        if case let .folder(folder) = self {
            return folder.children.count
        }

        return nil
    }

    nonisolated var hasChildItems: Bool {
        if case let .folder(folder) = self {
            return folder.containsAnyFilesystemItems
        }

        return false
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

    nonisolated var modifiedAt: Date? {
        if case let .file(file) = self {
            return file.modifiedAt
        }

        return nil
    }
}
