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

        let workspaceRootPath = Self.workspaceRootPath(for: snapshot.rootURL)
        return items.filter { $0.workspaceRootPath == workspaceRootPath }
    }

    func record(document: OpenDocument, openedAt: Date = .now) {
        let item = RecentFileItem(
            workspaceRootPath: Self.workspaceRootPath(for: document.workspaceRootURL),
            relativePath: document.relativePath,
            displayName: document.displayName,
            lastOpenedAt: openedAt
        )
        upsert(item)
    }

    func pruneInvalidItems(using snapshot: WorkspaceSnapshot) {
        let workspaceRootPath = Self.workspaceRootPath(for: snapshot.rootURL)
        let validRelativePaths = Set(
            Self.relativeFilePaths(
                in: snapshot.rootNodes,
                within: snapshot.rootURL
            )
        )
        let previousItems = items

        items = items.filter { item in
            guard item.workspaceRootPath == workspaceRootPath else {
                return true
            }

            return validRelativePaths.contains(item.relativePath)
        }

        if items != previousItems {
            persist()
        }
    }

    func renameItem(
        workspaceRootURL: URL,
        oldRelativePath: String,
        newRelativePath: String,
        displayName: String
    ) {
        let workspaceRootPath = Self.workspaceRootPath(for: workspaceRootURL)
        guard let index = items.firstIndex(where: {
            $0.workspaceRootPath == workspaceRootPath && $0.relativePath == oldRelativePath
        }) else {
            return
        }

        let existingItem = items.remove(at: index)
        let renamedItem = RecentFileItem(
            workspaceRootPath: workspaceRootPath,
            relativePath: newRelativePath,
            displayName: displayName,
            lastOpenedAt: existingItem.lastOpenedAt
        )
        items.insert(renamedItem, at: index)
        persist()
    }

    func removeItem(workspaceRootURL: URL, relativePath: String) {
        let workspaceRootPath = Self.workspaceRootPath(for: workspaceRootURL)
        let previousItems = items
        items.removeAll {
            $0.workspaceRootPath == workspaceRootPath && $0.relativePath == relativePath
        }

        if items != previousItems {
            persist()
        }
    }

    nonisolated static func workspaceRootPath(for url: URL) -> String {
        url.standardizedFileURL.path
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

    private static func relativeFilePaths(
        in nodes: [WorkspaceNode],
        within workspaceRootURL: URL
    ) -> [String] {
        nodes.flatMap { node in
            switch node {
            case let .folder(folder):
                return relativeFilePaths(in: folder.children, within: workspaceRootURL)
            case let .file(file):
                if let relativePath = WorkspaceRelativePath.make(
                    for: file.url,
                    within: workspaceRootURL
                ) {
                    return [relativePath]
                } else {
                    return []
                }
            }
        }
    }
}
