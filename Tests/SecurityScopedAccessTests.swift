import Foundation
import XCTest
@testable import Downward

final class SecurityScopedAccessTests: XCTestCase {
    func testMakeBookmarkUsesSecurityScopedBookmarkCreationOptions() throws {
        let bookmarks = RecordingSecurityScopedBookmarking()
        let resources = RecordingSecurityScopedResourceAccess()
        let handler = LiveSecurityScopedAccessHandler(
            bookmarking: bookmarks,
            resourceAccess: resources
        )
        let url = URL(filePath: "/tmp/Workspace")

        _ = try handler.makeBookmark(for: url)

        XCTAssertEqual(bookmarks.creationOptions, expectedBookmarkCreationOptions())
        XCTAssertEqual(resources.startedURLs, [url])
        XCTAssertEqual(resources.stoppedURLs, [url])
    }

    func testResolveBookmarkUsesSecurityScopedBookmarkResolutionOptions() throws {
        let bookmarks = RecordingSecurityScopedBookmarking()
        let handler = LiveSecurityScopedAccessHandler(
            bookmarking: bookmarks,
            resourceAccess: RecordingSecurityScopedResourceAccess()
        )

        _ = try handler.resolveBookmark(Data("bookmark".utf8))

        XCTAssertEqual(bookmarks.resolutionOptions, expectedBookmarkResolutionOptions())
    }

    func testBeginAccessLeaseStopsSecurityScopeExactlyOnce() throws {
        let resources = RecordingSecurityScopedResourceAccess()
        let handler = LiveSecurityScopedAccessHandler(
            bookmarking: RecordingSecurityScopedBookmarking(),
            resourceAccess: resources
        )
        let url = URL(filePath: "/tmp/Workspace")

        let lease = try handler.beginAccess(to: url)
        lease.endAccess()
        lease.endAccess()

        XCTAssertEqual(resources.startedURLs, [url])
        XCTAssertEqual(resources.stoppedURLs, [url])
    }

    private func expectedBookmarkCreationOptions() -> URL.BookmarkCreationOptions {
        #if os(macOS)
        [.withSecurityScope]
        #else
        []
        #endif
    }

    private func expectedBookmarkResolutionOptions() -> URL.BookmarkResolutionOptions {
        #if os(macOS)
        [.withSecurityScope]
        #else
        [.withoutImplicitStartAccessing]
        #endif
    }
}

private final class RecordingSecurityScopedBookmarking: @unchecked Sendable, SecurityScopedBookmarking {
    private let lock = NSLock()
    private var storedCreationOptions: URL.BookmarkCreationOptions?
    private var storedResolutionOptions: URL.BookmarkResolutionOptions?

    var creationOptions: URL.BookmarkCreationOptions? {
        lock.withLock { storedCreationOptions }
    }

    var resolutionOptions: URL.BookmarkResolutionOptions? {
        lock.withLock { storedResolutionOptions }
    }

    func makeBookmark(
        for url: URL,
        options: URL.BookmarkCreationOptions
    ) throws -> Data {
        lock.withLock {
            storedCreationOptions = options
        }
        return Data(url.path.utf8)
    }

    func resolveBookmark(
        _ data: Data,
        options: URL.BookmarkResolutionOptions
    ) throws -> ResolvedSecurityScopedURL {
        lock.withLock {
            storedResolutionOptions = options
        }
        return ResolvedSecurityScopedURL(
            url: URL(filePath: "/tmp/Workspace"),
            displayName: "Workspace",
            isStale: false
        )
    }
}

private final class RecordingSecurityScopedResourceAccess: @unchecked Sendable, SecurityScopedResourceAccessing {
    private let lock = NSLock()
    private var started: [URL] = []
    private var stopped: [URL] = []

    var startedURLs: [URL] {
        lock.withLock { started }
    }

    var stoppedURLs: [URL] {
        lock.withLock { stopped }
    }

    func startAccessing(_ url: URL) -> Bool {
        lock.withLock {
            started.append(url)
        }
        return true
    }

    func stopAccessing(_ url: URL) {
        lock.withLock {
            stopped.append(url)
        }
    }
}

private extension NSLock {
    func withLock<Value>(_ operation: () -> Value) -> Value {
        lock()
        defer { unlock() }
        return operation()
    }
}
