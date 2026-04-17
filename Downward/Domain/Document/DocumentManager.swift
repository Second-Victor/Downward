import Foundation

/// Loads text documents and maps them into the in-memory editor model.
protocol DocumentManager: Sendable {
    /// Compatibility/non-browser entry point when the caller only has a file URL.
    /// Browser/search/recent-file flows should prefer `openDocument(atRelativePath:in:)`.
    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument
    /// Primary browser/search/recent-file entry point once trusted workspace-relative identity is known.
    func openDocument(atRelativePath relativePath: String, in workspaceRootURL: URL) async throws -> OpenDocument
    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument
    /// Revalidates the active document using the same policy as live observation:
    /// clean buffers can silently refresh from disk, dirty buffers keep the local text authoritative,
    /// and only missing paths or unrecoverable failures escalate into explicit recovery UI.
    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument
    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument
    /// Emits change signals for the currently open file so the caller can rerun `revalidateDocument(_:)`
    /// instead of duplicating separate live-refresh conflict rules.
    func observeDocumentChanges(for document: OpenDocument) async throws -> AsyncStream<Void>
    /// Keeps the active live session attached to the renamed file path after a coordinated in-app move.
    func relocateDocumentSession(
        for document: OpenDocument,
        to url: URL,
        relativePath: String
    ) async
}

extension DocumentManager {
    /// Default compatibility path for simple test doubles. Production browser/search callers should
    /// still prefer the explicit relative-path API instead of relying on this lexical resolution.
    func openDocument(
        atRelativePath relativePath: String,
        in workspaceRootURL: URL
    ) async throws -> OpenDocument {
        let url = WorkspaceRelativePath.resolve(relativePath, within: workspaceRootURL)
        return try await openDocument(at: url, in: workspaceRootURL)
    }
}

actor LiveDocumentManager: DocumentManager {
    private let securityScopedAccess: any SecurityScopedAccessHandling
    private let logger: DebugLogger?
    // The live document layer is intentionally single-document today: one app-wide active key maps
    // to one active PlainTextDocumentSession. Multi-pane or multi-window editing would need this
    // ownership model redesigned before concurrent live sessions are safe.
    private var activeSessionKey: DocumentSessionKey?
    private var activeSession: PlainTextDocumentSession?

    init(
        securityScopedAccess: any SecurityScopedAccessHandling,
        logger: DebugLogger? = nil
    ) {
        self.securityScopedAccess = securityScopedAccess
        self.logger = logger
    }

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument {
        let relativePath = try Self.relativePath(for: url, within: workspaceRootURL)
        return try await openDocument(atRelativePath: relativePath, in: workspaceRootURL)
    }

    func openDocument(
        atRelativePath relativePath: String,
        in workspaceRootURL: URL
    ) async throws -> OpenDocument {
        let session = makeActiveSession(
            for: DocumentSessionKey(
                workspaceRootURL: workspaceRootURL,
                relativePath: relativePath
            )
        )
        let fallbackName = relativePath.split(separator: "/").last.map(String.init) ?? "Document"
        return try await session.openDocument(fallbackName: fallbackName)
    }

    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument {
        let session = session(for: document)
        return try await session.reloadDocument(from: document)
    }

    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument {
        let session = session(for: document)
        return try await session.revalidateDocument(document)
    }

    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument {
        let session = session(for: document)
        return try await session.saveDocument(document, overwriteConflict: overwriteConflict)
    }

    func observeDocumentChanges(for document: OpenDocument) async throws -> AsyncStream<Void> {
        let session = session(for: document)
        return try await session.observeChanges()
    }

    func relocateDocumentSession(
        for document: OpenDocument,
        to url: URL,
        relativePath: String
    ) async {
        let oldKey = DocumentSessionKey(
            workspaceRootURL: document.workspaceRootURL,
            relativePath: document.relativePath
        )

        guard activeSessionKey == oldKey, let activeSession else {
            return
        }

        await activeSession.relocate(to: url, relativePath: relativePath)
        activeSessionKey = DocumentSessionKey(
            workspaceRootURL: document.workspaceRootURL,
            relativePath: relativePath
        )
    }

    nonisolated static func makeConflictDocument(
        from document: OpenDocument,
        kind: DocumentConflict.Kind
    ) -> OpenDocument {
        PlainTextDocumentSession.makeConflictDocument(from: document, kind: kind)
    }

    private func session(for document: OpenDocument) -> PlainTextDocumentSession {
        makeActiveSession(
            for: DocumentSessionKey(
                workspaceRootURL: document.workspaceRootURL,
                relativePath: document.relativePath
            )
        )
    }

    private func makeActiveSession(for key: DocumentSessionKey) -> PlainTextDocumentSession {
        if activeSessionKey == key, let activeSession {
            return activeSession
        }

        let session = PlainTextDocumentSession(
            relativePath: key.relativePath,
            workspaceRootURL: key.workspaceRootURL,
            securityScopedAccess: securityScopedAccess,
            logger: logger
        )
        activeSessionKey = key
        activeSession = session
        return session
    }

    nonisolated private static func relativePath(
        for documentURL: URL,
        within workspaceRootURL: URL
    ) throws -> String {
        guard let relativePath = WorkspaceRelativePath.make(
            for: documentURL,
            within: workspaceRootURL
        ) else {
            throw AppError.documentUnavailable(name: documentURL.lastPathComponent)
        }

        return relativePath
    }
}

private struct DocumentSessionKey: Equatable, Sendable {
    let workspaceRootURL: URL
    let relativePath: String
}

actor StubDocumentManager: DocumentManager {
    private var sampleDocuments: [URL: OpenDocument]

    init(sampleDocuments: [URL: OpenDocument]) {
        self.sampleDocuments = sampleDocuments
    }

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument {
        guard let document = sampleDocuments[url] else {
            throw AppError.documentUnavailable(name: url.lastPathComponent)
        }

        return document
    }

    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument {
        try await openDocument(at: document.url, in: document.workspaceRootURL)
    }

    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument {
        guard let currentDocument = sampleDocuments[document.url] else {
            return LiveDocumentManager.makeConflictDocument(
                from: document,
                kind: .missingOnDisk
            )
        }

        return currentDocument
    }

    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument {
        var savedDocument = document
        savedDocument.isDirty = false
        savedDocument.saveState = .saved(Date())
        savedDocument.conflictState = .none
        sampleDocuments[document.url] = savedDocument
        return savedDocument
    }

    func observeDocumentChanges(for document: OpenDocument) async throws -> AsyncStream<Void> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func relocateDocumentSession(
        for document: OpenDocument,
        to url: URL,
        relativePath: String
    ) async {}
}
