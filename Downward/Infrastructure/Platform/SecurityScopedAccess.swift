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

struct LiveSecurityScopedAccessHandler: SecurityScopedAccessHandling {
    nonisolated func makeBookmark(for url: URL) throws -> Data {
        try withSecurityScopedAccess(to: url) { securedURL in
            try securedURL.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }

    nonisolated func resolveBookmark(_ data: Data) throws -> ResolvedSecurityScopedURL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        return ResolvedSecurityScopedURL(
            url: url,
            displayName: url.lastPathComponent,
            isStale: isStale
        )
    }

    nonisolated func validateAccess(to url: URL) throws {
        _ = try withSecurityScopedAccess(to: url) { _ in () }
    }

    nonisolated func beginAccess(to url: URL) throws -> SecurityScopedAccessLease {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        guard didStartAccess else {
            throw AppError.workspaceAccessInvalid(displayName: url.lastPathComponent)
        }

        return SecurityScopedAccessLease(
            url: url,
            stopHandler: {
                url.stopAccessingSecurityScopedResource()
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
            try operation(resolveDescendantURL(relativePath, within: securedRootURL))
        }
    }

    nonisolated private func withSecurityScopedAccess<Value>(
        to url: URL,
        _ operation: (URL) throws -> Value
    ) throws -> Value {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        guard didStartAccess else {
            throw AppError.workspaceAccessInvalid(displayName: url.lastPathComponent)
        }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        return try operation(url)
    }

    nonisolated private func resolveDescendantURL(
        _ relativePath: String,
        within rootURL: URL
    ) -> URL {
        relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .reduce(rootURL) { partialURL, component in
                partialURL.appending(path: String(component))
            }
    }
}

private extension NSLock {
    nonisolated func withLock<Value>(_ operation: () -> Value) -> Value {
        lock()
        defer { unlock() }
        return operation()
    }
}
