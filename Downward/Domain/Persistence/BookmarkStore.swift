import Foundation

struct StoredWorkspaceBookmark: Equatable, Sendable {
    let workspaceName: String
    let lastKnownPath: String
    let bookmarkData: Data
    let workspaceID: String

    nonisolated init(
        workspaceName: String,
        lastKnownPath: String,
        bookmarkData: Data,
        workspaceID: String = WorkspaceIdentity.makePersistentID()
    ) {
        self.workspaceName = workspaceName
        self.lastKnownPath = lastKnownPath
        self.bookmarkData = bookmarkData
        self.workspaceID = workspaceID
    }
}

/// Persists the selected workspace bookmark and minimal metadata needed for restore messaging.
protocol BookmarkStore: Sendable {
    func loadBookmark() async throws -> StoredWorkspaceBookmark?
    func saveBookmark(_ bookmark: StoredWorkspaceBookmark) async throws
    func clearBookmark() async throws
}

struct UserDefaultsBookmarkStore: BookmarkStore {
    private let userDefaults: UserDefaults
    private let bookmarkKey: String

    init(
        userDefaults: UserDefaults = .standard,
        bookmarkKey: String = "workspace.bookmark"
    ) {
        self.userDefaults = userDefaults
        self.bookmarkKey = bookmarkKey
    }

    func loadBookmark() async throws -> StoredWorkspaceBookmark? {
        guard let payload = userDefaults.dictionary(forKey: bookmarkKey) else {
            return nil
        }

        guard
            let workspaceName = payload["workspaceName"] as? String,
            let lastKnownPath = payload["lastKnownPath"] as? String,
            let bookmarkData = payload["bookmarkData"] as? Data
        else {
            throw AppError.workspaceRestoreFailed(details: "Saved workspace data is unreadable.")
        }

        if let workspaceID = payload["workspaceID"] as? String {
            return StoredWorkspaceBookmark(
                workspaceName: workspaceName,
                lastKnownPath: lastKnownPath,
                bookmarkData: bookmarkData,
                workspaceID: workspaceID
            )
        }

        // Migrate old bookmark payloads in place so the restored workspace gets a stable identity
        // that survives later reconnects, path moves, and stale bookmark refreshes.
        let upgradedBookmark = StoredWorkspaceBookmark(
            workspaceName: workspaceName,
            lastKnownPath: lastKnownPath,
            bookmarkData: bookmarkData
        )
        try await saveBookmark(upgradedBookmark)

        return upgradedBookmark
    }

    func saveBookmark(_ bookmark: StoredWorkspaceBookmark) async throws {
        userDefaults.set(
            [
                "workspaceName": bookmark.workspaceName,
                "lastKnownPath": bookmark.lastKnownPath,
                "bookmarkData": bookmark.bookmarkData,
                "workspaceID": bookmark.workspaceID,
            ],
            forKey: bookmarkKey
        )
    }

    func clearBookmark() async throws {
        userDefaults.removeObject(forKey: bookmarkKey)
    }
}

actor StubBookmarkStore: BookmarkStore {
    private var bookmark: StoredWorkspaceBookmark?

    init(initialBookmark: StoredWorkspaceBookmark? = nil) {
        self.bookmark = initialBookmark
    }

    func loadBookmark() async throws -> StoredWorkspaceBookmark? {
        bookmark
    }

    func saveBookmark(_ bookmark: StoredWorkspaceBookmark) async throws {
        self.bookmark = bookmark
    }

    func clearBookmark() async throws {
        bookmark = nil
    }
}
