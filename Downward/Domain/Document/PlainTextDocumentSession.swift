import CryptoKit
import Foundation

/// Coordinates live reads and writes for the active editor document against the real workspace file.
/// The current editor buffer is authoritative for autosave; coordinated reload/revalidation only
/// interrupts when the path disappears or a coordinated read/write fails unrecoverably.
actor PlainTextDocumentSession {
    private let workspaceRootURL: URL
    private let relativePath: String
    private let securityScopedAccess: any SecurityScopedAccessHandling

    init(
        relativePath: String,
        workspaceRootURL: URL,
        securityScopedAccess: any SecurityScopedAccessHandling
    ) {
        self.relativePath = relativePath
        self.workspaceRootURL = workspaceRootURL
        self.securityScopedAccess = securityScopedAccess
    }

    func openDocument(fallbackName: String) async throws -> OpenDocument {
        let relativePath = self.relativePath
        let workspaceRootURL = self.workspaceRootURL
        let securityScopedAccess = self.securityScopedAccess

        return try await Task.detached(priority: .userInitiated) {
            try securityScopedAccess.withAccess(
                toDescendantAt: relativePath,
                within: workspaceRootURL
            ) { securedURL in
                switch Self.readDocumentState(at: securedURL) {
                case let .success(documentState):
                    return OpenDocument(
                        url: securedURL,
                        workspaceRootURL: workspaceRootURL,
                        relativePath: relativePath,
                        displayName: documentState.displayName,
                        text: documentState.text,
                        loadedVersion: documentState.version,
                        isDirty: false,
                        saveState: .idle,
                        conflictState: .none
                    )
                case .failure(.missing):
                    throw AppError.documentUnavailable(name: fallbackName)
                case let .failure(.appError(error)):
                    throw error
                }
            }
        }.value
    }

    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument {
        try await openDocument(fallbackName: document.displayName)
    }

    /// Revalidates the active document without treating the editor's own coordinated saves as conflicts.
    /// If the file changed elsewhere while the buffer is clean, the latest disk contents replace the view.
    /// If the user still has local edits, the current buffer remains authoritative and autosave can persist it.
    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument {
        let relativePath = self.relativePath
        let workspaceRootURL = self.workspaceRootURL
        let securityScopedAccess = self.securityScopedAccess

        return try await Task.detached(priority: .utility) {
            try securityScopedAccess.withAccess(
                toDescendantAt: relativePath,
                within: workspaceRootURL
            ) { securedURL in
                switch Self.readDocumentState(at: securedURL) {
                case let .success(diskDocument):
                    if document.loadedVersion.matchesCurrentDisk(diskDocument.version) {
                        var validatedDocument = document
                        validatedDocument.url = securedURL
                        validatedDocument.displayName = diskDocument.displayName
                        return validatedDocument
                    }

                    if diskDocument.text == document.text {
                        var updatedDocument = document
                        updatedDocument.url = securedURL
                        updatedDocument.displayName = diskDocument.displayName
                        updatedDocument.loadedVersion = diskDocument.version
                        updatedDocument.conflictState = .none
                        return updatedDocument
                    }

                    guard document.isDirty == false else {
                        var preservedDocument = document
                        preservedDocument.url = securedURL
                        preservedDocument.displayName = diskDocument.displayName
                        preservedDocument.conflictState = .none
                        return preservedDocument
                    }

                    return OpenDocument(
                        url: securedURL,
                        workspaceRootURL: workspaceRootURL,
                        relativePath: relativePath,
                        displayName: diskDocument.displayName,
                        text: diskDocument.text,
                        loadedVersion: diskDocument.version,
                        isDirty: false,
                        saveState: .idle,
                        conflictState: .none
                    )
                case .failure(.missing):
                    return Self.makeConflictDocument(
                        from: document,
                        kind: .missingOnDisk
                    )
                case let .failure(.appError(error)):
                    throw error
                }
            }
        }.value
    }

    /// Performs a coordinated last-writer-wins save for the active editor buffer. The active buffer remains
    /// authoritative during ordinary typing; only missing paths or unrecoverable write failures interrupt it.
    func saveDocument(
        _ document: OpenDocument,
        overwriteConflict: Bool
    ) async throws -> OpenDocument {
        let relativePath = self.relativePath
        let workspaceRootURL = self.workspaceRootURL
        let securityScopedAccess = self.securityScopedAccess

        return try await Task.detached(priority: .utility) {
            try securityScopedAccess.withAccess(
                toDescendantAt: relativePath,
                within: workspaceRootURL
            ) { securedURL in
                if overwriteConflict == false {
                    switch Self.readPresenceState(at: securedURL, fallbackName: document.displayName) {
                    case .success:
                        break
                    case .failure(.missing):
                        return Self.makeConflictDocument(
                            from: document,
                            kind: .missingOnDisk
                        )
                    case let .failure(.appError(error)):
                        throw error
                    }
                }

                switch Self.writeDocumentState(
                    text: document.text,
                    to: securedURL,
                    fallbackName: document.displayName
                ) {
                case let .success(savedState):
                    var savedDocument = document
                    savedDocument.url = securedURL
                    savedDocument.displayName = savedState.displayName
                    savedDocument.loadedVersion = savedState.version
                    savedDocument.isDirty = false
                    savedDocument.saveState = .saved(Date())
                    savedDocument.conflictState = .none
                    return savedDocument
                case .failure(.missing):
                    return Self.makeConflictDocument(
                        from: document,
                        kind: .missingOnDisk
                    )
                case let .failure(.appError(error)):
                    throw error
                }
            }
        }.value
    }

    nonisolated static func makeConflictDocument(
        from document: OpenDocument,
        kind: DocumentConflict.Kind
    ) -> OpenDocument {
        let userFacingError = switch kind {
        case .modifiedOnDisk:
            UserFacingError(
                title: "File Changed Elsewhere",
                message: "\(document.displayName) changed on disk after it was opened.",
                recoverySuggestion: "Reload from disk, overwrite the newer version, or keep your edits in memory for now."
            )
        case .missingOnDisk:
            UserFacingError(
                title: "File No Longer Exists",
                message: "\(document.displayName) was moved or deleted outside the app.",
                recoverySuggestion: "Reload if it returns, overwrite to recreate it at this path, or keep your edits in memory for now."
            )
        }

        var conflictedDocument = document
        conflictedDocument.isDirty = document.isDirty
        conflictedDocument.saveState = document.isDirty ? .unsaved : .idle
        conflictedDocument.conflictState = .needsResolution(
            DocumentConflict(kind: kind, error: userFacingError)
        )
        return conflictedDocument
    }

    nonisolated private static func readDocumentState(
        at url: URL
    ) -> Result<CoordinatedDocumentState, AppErrorOrMissing> {
        var coordinationError: NSError?
        var result: Result<CoordinatedDocumentState, AppErrorOrMissing>?
        let coordinator = NSFileCoordinator(filePresenter: nil)

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = loadDocumentState(at: coordinatedURL)
        }

        if let coordinationError {
            return wrapFilesystemError(
                coordinationError,
                name: url.lastPathComponent,
                makeAppError: { name in
                    AppError.documentOpenFailed(
                        name: name,
                        details: "The file could not be read from disk."
                    )
                }
            )
        }

        return result ?? .failure(
            .appError(
                AppError.documentOpenFailed(
                    name: url.lastPathComponent,
                    details: "The coordinated read did not return any data."
                )
            )
        )
    }

    nonisolated private static func readPresenceState(
        at url: URL,
        fallbackName: String
    ) -> Result<CoordinatedPresenceState, AppErrorOrMissing> {
        var coordinationError: NSError?
        var result: Result<CoordinatedPresenceState, AppErrorOrMissing>?
        let coordinator = NSFileCoordinator(filePresenter: nil)

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = loadPresenceState(at: coordinatedURL, fallbackName: fallbackName)
        }

        if let coordinationError {
            return wrapFilesystemError(
                coordinationError,
                name: fallbackName,
                makeAppError: { name in
                    AppError.documentSaveFailed(
                        name: name,
                        details: "The current file metadata could not be read before saving."
                    )
                }
            )
        }

        return result ?? .failure(
            .appError(
                AppError.documentSaveFailed(
                    name: fallbackName,
                    details: "The file could not be checked before saving."
                )
            )
        )
    }

    nonisolated private static func writeDocumentState(
        text: String,
        to url: URL,
        fallbackName: String
    ) -> Result<CoordinatedDocumentState, AppErrorOrMissing> {
        var coordinationError: NSError?
        var result: Result<CoordinatedDocumentState, AppErrorOrMissing>?
        let coordinator = NSFileCoordinator(filePresenter: nil)

        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                let parentURL = coordinatedURL.deletingLastPathComponent()
                let parentValues = try parentURL.resourceValues(forKeys: [.isDirectoryKey])
                guard parentValues.isDirectory == true else {
                    result = .failure(.missing)
                    return
                }

                // Write directly to the coordinated URL. An additional atomic replace here would create
                // another filesystem-level replacement step on provider-backed files, which is exactly the
                // noisy path this live document session is replacing.
                try text.write(to: coordinatedURL, atomically: false, encoding: .utf8)

                let resourceValues = try coordinatedURL.resourceValues(forKeys: documentResourceKeys)
                guard resourceValues.isDirectory != true else {
                    throw AppError.documentSaveFailed(
                        name: fallbackName,
                        details: "The path now points to a folder instead of a file."
                    )
                }

                result = .success(
                    CoordinatedDocumentState(
                        displayName: resourceValues.localizedName ?? resourceValues.name ?? coordinatedURL.lastPathComponent,
                        text: text,
                        version: makeLoadedVersion(from: resourceValues, text: text)
                    )
                )
            } catch let error as AppError {
                result = .failure(.appError(error))
            } catch {
                result = wrapFilesystemError(
                    error,
                    name: fallbackName,
                    makeAppError: { name in
                        AppError.documentSaveFailed(
                            name: name,
                            details: "The latest text could not be written to disk."
                        )
                    }
                )
            }
        }

        if let coordinationError {
            return wrapFilesystemError(
                coordinationError,
                name: fallbackName,
                makeAppError: { name in
                    AppError.documentSaveFailed(
                        name: name,
                        details: "The coordinated write could not be completed."
                    )
                }
            )
        }

        return result ?? .failure(
            .appError(
                AppError.documentSaveFailed(
                    name: fallbackName,
                    details: "The coordinated write did not return a saved state."
                )
            )
        )
    }

    nonisolated private static func loadDocumentState(
        at url: URL
    ) -> Result<CoordinatedDocumentState, AppErrorOrMissing> {
        do {
            let resourceValues = try url.resourceValues(forKeys: documentResourceKeys)
            guard resourceValues.isDirectory != true else {
                throw AppError.documentOpenFailed(
                    name: url.lastPathComponent,
                    details: "The selected path is not a plain text file."
                )
            }

            let text = try String(contentsOf: url, encoding: .utf8)

            return .success(
                CoordinatedDocumentState(
                    displayName: resourceValues.localizedName ?? resourceValues.name ?? url.lastPathComponent,
                    text: text,
                    version: makeLoadedVersion(from: resourceValues, text: text)
                )
            )
        } catch let error as AppError {
            return .failure(.appError(error))
        } catch {
            return wrapFilesystemError(
                error,
                name: url.lastPathComponent,
                makeAppError: { name in
                    AppError.documentOpenFailed(
                        name: name,
                        details: "The file could not be read from disk."
                    )
                }
            )
        }
    }

    nonisolated private static func loadPresenceState(
        at url: URL,
        fallbackName: String
    ) -> Result<CoordinatedPresenceState, AppErrorOrMissing> {
        do {
            let resourceValues = try url.resourceValues(forKeys: documentResourceKeys)
            guard resourceValues.isDirectory != true else {
                throw AppError.documentSaveFailed(
                    name: fallbackName,
                    details: "The path now points to a folder instead of a file."
                )
            }

            return .success(
                CoordinatedPresenceState(
                    displayName: resourceValues.localizedName ?? resourceValues.name ?? fallbackName
                )
            )
        } catch let error as AppError {
            return .failure(.appError(error))
        } catch {
            return wrapFilesystemError(
                error,
                name: fallbackName,
                makeAppError: { name in
                    AppError.documentSaveFailed(
                        name: name,
                        details: "The current file metadata could not be read before saving."
                    )
                }
            )
        }
    }

    nonisolated private static func makeLoadedVersion(
        from resourceValues: URLResourceValues,
        text: String
    ) -> DocumentVersion {
        let data = Data(text.utf8)
        return DocumentVersion(
            contentModificationDate: resourceValues.contentModificationDate,
            fileSize: resourceValues.fileSize ?? data.count,
            contentDigest: SHA256.hash(data: data).compactMap { byte in
                String(format: "%02x", byte)
            }.joined()
        )
    }

    nonisolated private static func wrapFilesystemError<Success>(
        _ error: Error,
        name: String,
        makeAppError: (String) -> AppError
    ) -> Result<Success, AppErrorOrMissing> {
        if isMissingFileError(error) {
            return .failure(.missing)
        }

        return .failure(.appError(makeAppError(name)))
    }

    nonisolated private static func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoSuchFileError {
            return true
        }

        if nsError.domain == NSPOSIXErrorDomain, nsError.code == ENOENT {
            return true
        }

        return false
    }

    nonisolated private static var documentResourceKeys: Set<URLResourceKey> {
        [
            .contentModificationDateKey,
            .fileSizeKey,
            .localizedNameKey,
            .nameKey,
            .isDirectoryKey,
        ]
    }
}

private struct CoordinatedDocumentState: Sendable {
    let displayName: String
    let text: String
    let version: DocumentVersion
}

private struct CoordinatedPresenceState: Sendable {
    let displayName: String
}

private enum AppErrorOrMissing: Error, Sendable {
    case appError(AppError)
    case missing
}
