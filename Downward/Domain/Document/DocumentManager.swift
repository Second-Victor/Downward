import Foundation

/// Loads text documents and maps them into the in-memory editor model.
protocol DocumentManager: Sendable {
    /// Opens a document by resolving its path relative to the active workspace root.
    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument
    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument
    /// Revalidates the active document using the same policy as live observation:
    /// clean buffers can silently refresh from disk, dirty buffers keep the local text authoritative,
    /// and only missing paths or unrecoverable failures escalate into explicit recovery UI.
    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument
    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument
    /// Emits change signals for the currently open file so the caller can rerun `revalidateDocument(_:)`
    /// instead of duplicating separate live-refresh conflict rules.
    func observeDocumentChanges(for document: OpenDocument) async throws -> AsyncStream<Void>
}

actor LiveDocumentManager: DocumentManager {
    private let securityScopedAccess: any SecurityScopedAccessHandling
    private var activeSessionKey: DocumentSessionKey?
    private var activeSession: PlainTextDocumentSession?

    init(securityScopedAccess: any SecurityScopedAccessHandling) {
        self.securityScopedAccess = securityScopedAccess
    }

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument {
        let relativePath = try Self.relativePath(for: url, within: workspaceRootURL)
        let session = makeActiveSession(
            for: DocumentSessionKey(
                workspaceRootURL: workspaceRootURL,
                relativePath: relativePath
            )
        )
        return try await session.openDocument(fallbackName: url.lastPathComponent)
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
            securityScopedAccess: securityScopedAccess
        )
        activeSessionKey = key
        activeSession = session
        return session
    }

    nonisolated private static func relativePath(
        for documentURL: URL,
        within workspaceRootURL: URL
    ) throws -> String {
        let documentComponents = documentURL.standardizedFileURL.pathComponents
        let workspaceComponents = workspaceRootURL.standardizedFileURL.pathComponents

        guard
            documentComponents.count > workspaceComponents.count,
            documentComponents.starts(with: workspaceComponents)
        else {
            throw AppError.documentUnavailable(name: documentURL.lastPathComponent)
        }

        return documentComponents
            .dropFirst(workspaceComponents.count)
            .joined(separator: "/")
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
}
