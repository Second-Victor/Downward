import Foundation

struct ResolvedSecurityScopedURL: Equatable, Sendable {
    let url: URL
    let displayName: String
    let isStale: Bool
}

final class SecurityScopedAccessLease: @unchecked Sendable {
    nonisolated let url: URL

    private let stopHandler: (@Sendable () -> Void)?
    private let lock = NSLock()
    nonisolated(unsafe) private var isActive = true

    nonisolated init(
        url: URL,
        stopHandler: (@Sendable () -> Void)?
    ) {
        self.url = url
        self.stopHandler = stopHandler
    }

    nonisolated func endAccess() {
        let handler: (@Sendable () -> Void)? = lock.withLock {
            guard isActive else {
                return nil
            }

            isActive = false
            return stopHandler
        }

        handler?()
    }

    nonisolated
    deinit {
        endAccess()
    }
}

/// Wraps security-scoped URL access so folder selection and bookmark restore stay out of views.
protocol SecurityScopedAccessHandling: Sendable {
    nonisolated func makeBookmark(for url: URL) throws -> Data
    nonisolated func resolveBookmark(_ data: Data) throws -> ResolvedSecurityScopedURL
    nonisolated func validateAccess(to url: URL) throws
    nonisolated func beginAccess(to url: URL) throws -> SecurityScopedAccessLease
    nonisolated func withAccess<Value>(
        to url: URL,
        operation: (URL) throws -> Value
    ) throws -> Value
    /// Resolves a descendant path under an active workspace root so document access does not
    /// incorrectly rely on starting security scope on child file URLs.
    nonisolated func withAccess<Value>(
        toDescendantAt relativePath: String,
        within workspaceRootURL: URL,
        operation: (URL) throws -> Value
    ) throws -> Value
}

protocol SecurityScopedBookmarking: Sendable {
    nonisolated func makeBookmark(
        for url: URL,
        options: URL.BookmarkCreationOptions
    ) throws -> Data
    nonisolated func resolveBookmark(
        _ data: Data,
        options: URL.BookmarkResolutionOptions
    ) throws -> ResolvedSecurityScopedURL
}

protocol SecurityScopedResourceAccessing: Sendable {
    nonisolated func startAccessing(_ url: URL) -> Bool
    nonisolated func stopAccessing(_ url: URL)
}

struct LiveSecurityScopedAccessHandler: SecurityScopedAccessHandling {
    private let bookmarking: any SecurityScopedBookmarking
    private let resourceAccess: any SecurityScopedResourceAccessing

    nonisolated init(
        bookmarking: any SecurityScopedBookmarking = URLSecurityScopedBookmarking(),
        resourceAccess: any SecurityScopedResourceAccessing = URLSecurityScopedResourceAccess()
    ) {
        self.bookmarking = bookmarking
        self.resourceAccess = resourceAccess
    }

    nonisolated func makeBookmark(for url: URL) throws -> Data {
        try withSecurityScopedAccess(to: url) { securedURL in
            try bookmarking.makeBookmark(
                for: securedURL,
                options: Self.bookmarkCreationOptions()
            )
        }
    }

    nonisolated func resolveBookmark(_ data: Data) throws -> ResolvedSecurityScopedURL {
        try bookmarking.resolveBookmark(
            data,
            options: Self.bookmarkResolutionOptions()
        )
    }

    nonisolated func validateAccess(to url: URL) throws {
        _ = try withSecurityScopedAccess(to: url) { _ in () }
    }

    nonisolated func beginAccess(to url: URL) throws -> SecurityScopedAccessLease {
        let didStartAccess = resourceAccess.startAccessing(url)
        guard didStartAccess else {
            throw AppError.workspaceAccessInvalid(displayName: url.lastPathComponent)
        }

        let resourceAccess = self.resourceAccess
        return SecurityScopedAccessLease(
            url: url,
            stopHandler: {
                resourceAccess.stopAccessing(url)
            }
        )
    }

    nonisolated func withAccess<Value>(
        to url: URL,
        operation: (URL) throws -> Value
    ) throws -> Value {
        try withSecurityScopedAccess(to: url, operation)
    }

    nonisolated func withAccess<Value>(
        toDescendantAt relativePath: String,
        within workspaceRootURL: URL,
        operation: (URL) throws -> Value
    ) throws -> Value {
        try withSecurityScopedAccess(to: workspaceRootURL) { securedRootURL in
            guard let securedDescendantURL = WorkspaceRelativePath.resolveCandidate(
                relativePath,
                within: securedRootURL
            ) else {
                throw AppError.documentUnavailable(
                    name: Self.descendantDisplayName(for: relativePath)
                )
            }

            return try operation(securedDescendantURL)
        }
    }

    nonisolated private func withSecurityScopedAccess<Value>(
        to url: URL,
        _ operation: (URL) throws -> Value
    ) throws -> Value {
        let didStartAccess = resourceAccess.startAccessing(url)
        guard didStartAccess else {
            throw AppError.workspaceAccessInvalid(displayName: url.lastPathComponent)
        }

        defer {
            resourceAccess.stopAccessing(url)
        }

        return try operation(url)
    }

    nonisolated private static func descendantDisplayName(for relativePath: String) -> String {
        relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .last
            .map(String.init) ?? "Document"
    }

    nonisolated private static func bookmarkCreationOptions() -> URL.BookmarkCreationOptions {
        #if os(macOS)
        [.withSecurityScope]
        #else
        []
        #endif
    }

    nonisolated private static func bookmarkResolutionOptions() -> URL.BookmarkResolutionOptions {
        #if os(macOS)
        [.withSecurityScope]
        #else
        [.withoutImplicitStartAccessing]
        #endif
    }
}

private struct URLSecurityScopedBookmarking: SecurityScopedBookmarking {
    nonisolated func makeBookmark(
        for url: URL,
        options: URL.BookmarkCreationOptions
    ) throws -> Data {
        try url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    nonisolated func resolveBookmark(
        _ data: Data,
        options: URL.BookmarkResolutionOptions
    ) throws -> ResolvedSecurityScopedURL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        return ResolvedSecurityScopedURL(
            url: url,
            displayName: url.lastPathComponent,
            isStale: isStale
        )
    }
}

private struct URLSecurityScopedResourceAccess: SecurityScopedResourceAccessing {
    nonisolated func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    nonisolated func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

private extension NSLock {
    nonisolated func withLock<Value>(_ operation: () -> Value) -> Value {
        lock()
        defer { unlock() }
        return operation()
    }
}
