import Foundation
import XCTest
@testable import Downward

final class BookmarkStoreTests: XCTestCase {
    @MainActor
    func testUserDefaultsBookmarkStorePersistsAndClearsBookmark() async throws {
        let suiteName = "BookmarkStoreTests.\(UUID().uuidString)"
        let userDefaults = try makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsBookmarkStore(
            userDefaults: userDefaults,
            bookmarkKey: "test.workspace.bookmark"
        )
        let bookmark = StoredWorkspaceBookmark(
            workspaceName: "Notes",
            lastKnownPath: "/tmp/Notes",
            bookmarkData: Data("bookmark-data".utf8),
            workspaceID: "workspace-id"
        )

        try await store.saveBookmark(bookmark)
        let loadedBookmark = try await store.loadBookmark()

        XCTAssertEqual(loadedBookmark, bookmark)

        try await store.clearBookmark()

        let clearedBookmark = try await store.loadBookmark()
        XCTAssertNil(clearedBookmark)
    }

    @MainActor
    func testUserDefaultsBookmarkStoreMigratesLegacyBookmarkPayloadToWorkspaceID() async throws {
        let suiteName = "BookmarkStoreTests.\(UUID().uuidString)"
        let userDefaults = try makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set(
            [
                "workspaceName": "Notes",
                "lastKnownPath": "/tmp/Notes",
                "bookmarkData": Data("bookmark-data".utf8),
            ],
            forKey: "test.workspace.bookmark"
        )

        let store = UserDefaultsBookmarkStore(
            userDefaults: userDefaults,
            bookmarkKey: "test.workspace.bookmark"
        )

        let loadedBookmark = try await store.loadBookmark()
        let migratedBookmark = try XCTUnwrap(loadedBookmark)
        let persistedPayload = try XCTUnwrap(
            userDefaults.dictionary(forKey: "test.workspace.bookmark")
        )

        XCTAssertEqual(migratedBookmark.workspaceName, "Notes")
        XCTAssertEqual(migratedBookmark.lastKnownPath, "/tmp/Notes")
        XCTAssertEqual(migratedBookmark.bookmarkData, Data("bookmark-data".utf8))
        XCTAssertFalse(migratedBookmark.workspaceID.isEmpty)
        XCTAssertEqual(persistedPayload["workspaceID"] as? String, migratedBookmark.workspaceID)
    }

    @MainActor
    private func makeIsolatedUserDefaults(suiteName: String) throws -> UserDefaults {
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Unable to create isolated UserDefaults suite.")
        }

        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
