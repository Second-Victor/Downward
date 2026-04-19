import Foundation
import Observation

@MainActor
@Observable
final class RecentFilesStore {
    private let userDefaults: UserDefaults?
    private let persistenceKey: String
    private let maximumCount: Int

    private(set) var items: [RecentFileItem]

    init(
        userDefaults: UserDefaults = .standard,
        persistenceKey: String = "recentFiles.items",
        maximumCount: Int = 10
    ) {
        self.userDefaults = userDefaults
        self.persistenceKey = persistenceKey
        self.maximumCount = maximumCount
        self.items = Self.loadItems(
            from: userDefaults,
            key: persistenceKey,
            maximumCount: maximumCount
        )
    }

    init(
        initialItems: [RecentFileItem],
        persistenceKey: String = "recentFiles.items",
        maximumCount: Int = 10
    ) {
        self.userDefaults = nil
        self.persistenceKey = persistenceKey
        self.maximumCount = maximumCount
        self.items = Self.normalizedItems(initialItems, maximumCount: maximumCount)
    }

    func recentItems(for snapshot: WorkspaceSnapshot?) -> [RecentFileItem] {
        guard let snapshot else {
            return []
        }

        return items.filter { Self.belongs($0, to: snapshot) }
    }

    /// Recent files follow the bookmark-owned workspace identity, not just the current resolved path.
    /// That lets moved/restored workspaces keep history once the active workspace adopts legacy items.
    func record(document: OpenDocument, in snapshot: WorkspaceSnapshot, openedAt: Date = .now) {
        let item = RecentFileItem(
            workspaceID: snapshot.workspaceID,
            workspaceRootPath: Self.workspaceRootPath(for: snapshot.rootURL),
            relativePath: document.relativePath,
            displayName: document.displayName,
            lastOpenedAt: openedAt
        )
        upsert(item)
    }

    func pruneInvalidItems(using snapshot: WorkspaceSnapshot) {
        adoptWorkspaceIdentity(using: snapshot)
        let validRelativePaths = Set(
            Self.relativeFilePaths(in: snapshot)
        )
        let previousItems = items

        items = items.filter { item in
            guard Self.belongs(item, to: snapshot) else {
                return true
            }

            return validRelativePaths.contains(item.relativePath)
        }

        if items != previousItems {
            persist()
        }
    }

    func renameItem(
        using snapshot: WorkspaceSnapshot,
        oldRelativePath: String,
        newRelativePath: String,
        displayName: String
    ) {
        adoptWorkspaceIdentity(using: snapshot)
        guard let index = items.firstIndex(where: {
            Self.belongs($0, to: snapshot) && $0.relativePath == oldRelativePath
        }) else {
            return
        }

        let existingItem = items.remove(at: index)
        let renamedItem = RecentFileItem(
            workspaceID: snapshot.workspaceID,
            workspaceRootPath: Self.workspaceRootPath(for: snapshot.rootURL),
            relativePath: newRelativePath,
            displayName: displayName,
            lastOpenedAt: existingItem.lastOpenedAt
        )
        items.insert(renamedItem, at: index)
        persist()
    }

    func renameItemsInFolder(
        using snapshot: WorkspaceSnapshot,
        oldFolderRelativePath: String,
        newFolderRelativePath: String
    ) {
        adoptWorkspaceIdentity(using: snapshot)
        let updatedItems = items.map { item in
            guard
                Self.belongs(item, to: snapshot),
                let rewrittenRelativePath = Self.replacingPathPrefix(
                    item.relativePath,
                    oldPrefix: oldFolderRelativePath,
                    newPrefix: newFolderRelativePath
                )
            else {
                return item
            }

            return RecentFileItem(
                workspaceID: snapshot.workspaceID,
                workspaceRootPath: Self.workspaceRootPath(for: snapshot.rootURL),
                relativePath: rewrittenRelativePath,
                displayName: rewrittenRelativePath.split(separator: "/").last.map(String.init) ?? item.displayName,
                lastOpenedAt: item.lastOpenedAt
            )
        }

        let normalizedItems = Self.normalizedItems(updatedItems, maximumCount: maximumCount)
        guard normalizedItems != items else {
            return
        }

        items = normalizedItems
        persist()
    }

    func removeItem(using snapshot: WorkspaceSnapshot, relativePath: String) {
        adoptWorkspaceIdentity(using: snapshot)
        let previousItems = items
        items.removeAll {
            Self.belongs($0, to: snapshot) && $0.relativePath == relativePath
        }

        if items != previousItems {
            persist()
        }
    }

    func removeItemsInFolder(using snapshot: WorkspaceSnapshot, folderRelativePath: String) {
        adoptWorkspaceIdentity(using: snapshot)
        let previousItems = items
        items.removeAll {
            Self.belongs($0, to: snapshot)
                && Self.isSameOrDescendantPath($0.relativePath, of: folderRelativePath)
        }

        if items != previousItems {
            persist()
        }
    }

    func adoptWorkspaceIdentity(using snapshot: WorkspaceSnapshot) {
        let updatedItems = items.map { item in
            guard item.workspaceID != snapshot.workspaceID, Self.belongs(item, to: snapshot) else {
                return item
            }

            return RecentFileItem(
                workspaceID: snapshot.workspaceID,
                workspaceRootPath: Self.workspaceRootPath(for: snapshot.rootURL),
                relativePath: item.relativePath,
                displayName: item.displayName,
                lastOpenedAt: item.lastOpenedAt
            )
        }

        let normalizedItems = Self.normalizedItems(updatedItems, maximumCount: maximumCount)
        guard normalizedItems != items else {
            return
        }

        items = normalizedItems
        persist()
    }

    nonisolated static func workspaceRootPath(for url: URL) -> String {
        WorkspaceIdentity.normalizedPath(for: url)
    }

    private func upsert(_ item: RecentFileItem) {
        items.removeAll {
            $0.workspaceRootPath == item.workspaceRootPath && $0.relativePath == item.relativePath
        }
        items.insert(item, at: 0)
        items = Self.normalizedItems(items, maximumCount: maximumCount)
        persist()
    }

    private func persist() {
        guard let userDefaults else {
            return
        }

        guard let payload = try? JSONEncoder().encode(items) else {
            return
        }

        userDefaults.set(payload, forKey: persistenceKey)
    }

    private static func loadItems(
        from userDefaults: UserDefaults,
        key: String,
        maximumCount: Int
    ) -> [RecentFileItem] {
        guard let data = userDefaults.data(forKey: key) else {
            return []
        }

        guard let decodedItems = try? JSONDecoder().decode([RecentFileItem].self, from: data) else {
            return []
        }

        return normalizedItems(decodedItems, maximumCount: maximumCount)
    }

    private static func normalizedItems(
        _ items: [RecentFileItem],
        maximumCount: Int
    ) -> [RecentFileItem] {
        var seenKeys = Set<String>()
        let deduplicatedItems = items
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
            .filter { item in
                let key = item.id
                let inserted = seenKeys.insert(key).inserted
                return inserted
            }

        return Array(deduplicatedItems.prefix(maximumCount))
    }

    private static func belongs(
        _ item: RecentFileItem,
        to snapshot: WorkspaceSnapshot
    ) -> Bool {
        item.workspaceID == snapshot.workspaceID
            || snapshot.recentFileLookupPaths.contains(item.workspaceRootPath)
    }

    private static func relativeFilePaths(in snapshot: WorkspaceSnapshot) -> [String] {
        flattenFileURLs(in: snapshot.rootNodes).compactMap { snapshot.relativePath(for: $0) }
    }

    private static func flattenFileURLs(in nodes: [WorkspaceNode]) -> [URL] {
        nodes.flatMap { node in
            switch node {
            case let .folder(folder):
                return flattenFileURLs(in: folder.children)
            case let .file(file):
                return [file.url]
            }
        }
    }

    private static func isSameOrDescendantPath(_ path: String, of folderPath: String) -> Bool {
        path == folderPath || path.hasPrefix("\(folderPath)/")
    }

    private static func replacingPathPrefix(
        _ path: String,
        oldPrefix: String,
        newPrefix: String
    ) -> String? {
        guard isSameOrDescendantPath(path, of: oldPrefix) else {
            return nil
        }

        if path == oldPrefix {
            return newPrefix
        }

        let suffix = path.dropFirst(oldPrefix.count + 1)
        return "\(newPrefix)/\(suffix)"
    }
}
