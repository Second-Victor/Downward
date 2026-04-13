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
            bookmarkData: Data("bookmark-data".utf8)
        )

        try await store.saveBookmark(bookmark)
        let loadedBookmark = try await store.loadBookmark()

        XCTAssertEqual(loadedBookmark, bookmark)

        try await store.clearBookmark()

        let clearedBookmark = try await store.loadBookmark()
        XCTAssertNil(clearedBookmark)
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
