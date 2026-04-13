import Foundation

struct RestorableDocumentSession: Equatable, Sendable {
    let relativePath: String
}

/// Persists only the minimal document identity needed to reopen the last editor session safely.
protocol SessionStore: Sendable {
    func loadRestorableDocumentSession() async throws -> RestorableDocumentSession?
    func saveRestorableDocumentSession(_ session: RestorableDocumentSession) async throws
    func clearRestorableDocumentSession() async throws
}

struct UserDefaultsSessionStore: SessionStore {
    private let userDefaults: UserDefaults
    private let sessionKey: String

    init(
        userDefaults: UserDefaults = .standard,
        sessionKey: String = "session.lastOpenDocument"
    ) {
        self.userDefaults = userDefaults
        self.sessionKey = sessionKey
    }

    func loadRestorableDocumentSession() async throws -> RestorableDocumentSession? {
        guard let payload = userDefaults.dictionary(forKey: sessionKey) else {
            return nil
        }

        guard let relativePath = payload["relativePath"] as? String else {
            return nil
        }

        let trimmedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.isEmpty == false else {
            return nil
        }

        return RestorableDocumentSession(relativePath: trimmedPath)
    }

    func saveRestorableDocumentSession(_ session: RestorableDocumentSession) async throws {
        userDefaults.set(
            [
                "relativePath": session.relativePath,
            ],
            forKey: sessionKey
        )
    }

    func clearRestorableDocumentSession() async throws {
        userDefaults.removeObject(forKey: sessionKey)
    }
}

actor StubSessionStore: SessionStore {
    private var session: RestorableDocumentSession?

    init(initialSession: RestorableDocumentSession? = nil) {
        self.session = initialSession
    }

    func loadRestorableDocumentSession() async throws -> RestorableDocumentSession? {
        session
    }

    func saveRestorableDocumentSession(_ session: RestorableDocumentSession) async throws {
        self.session = session
    }

    func clearRestorableDocumentSession() async throws {
        session = nil
    }
}
