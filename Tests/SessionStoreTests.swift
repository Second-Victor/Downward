import Foundation
import XCTest
@testable import Downward

final class SessionStoreTests: XCTestCase {
    @MainActor
    func testUserDefaultsSessionStorePersistsAndClearsLastOpenDocument() async throws {
        let suiteName = "SessionStoreTests.\(UUID().uuidString)"
        let userDefaults = try makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsSessionStore(
            userDefaults: userDefaults,
            sessionKey: "test.session.lastOpenDocument"
        )
        let session = RestorableDocumentSession(relativePath: "Journal/2026/Entry.md")

        try await store.saveRestorableDocumentSession(session)
        let loadedSession = try await store.loadRestorableDocumentSession()

        XCTAssertEqual(loadedSession, session)

        try await store.clearRestorableDocumentSession()
        let clearedSession = try await store.loadRestorableDocumentSession()
        XCTAssertNil(clearedSession)
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
