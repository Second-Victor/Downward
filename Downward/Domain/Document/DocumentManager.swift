import Foundation
import CryptoKit

/// Loads text documents and maps them into the in-memory editor model.
protocol DocumentManager: Sendable {
    /// Opens a document by resolving its path relative to the active workspace root.
    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument
    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument
    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument
}

actor LiveDocumentManager: DocumentManager {
    private let securityScopedAccess: any SecurityScopedAccessHandling

    init(securityScopedAccess: any SecurityScopedAccessHandling) {
        self.securityScopedAccess = securityScopedAccess
    }

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument {
        let relativePath = try Self.relativePath(for: url, within: workspaceRootURL)
        return try await loadDocument(
            relativePath: relativePath,
            workspaceRootURL: workspaceRootURL,
            fallbackName: url.lastPathComponent
        )
    }

    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument {
        try await loadDocument(
            relativePath: document.relativePath,
            workspaceRootURL: document.workspaceRootURL,
            fallbackName: document.displayName
        )
    }

    /// Writes the latest text only after confirming the on-disk version still matches the loaded snapshot.
    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument {
        let securityScopedAccess = self.securityScopedAccess

        return try await Task.detached(priority: .utility) {
            try securityScopedAccess.withAccess(
                toDescendantAt: document.relativePath,
                within: document.workspaceRootURL
            ) { securedURL in
                if overwriteConflict == false {
                    let currentVersionResult = Self.loadVersionState(at: securedURL, fallbackName: document.displayName)
                    switch currentVersionResult {
                    case let .success(currentVersionState):
                        guard document.loadedVersion.matchesCurrentDisk(currentVersionState.version) else {
                            return Self.makeConflictDocument(
                                from: document,
                                kind: .modifiedOnDisk
                            )
                        }
                    case .failure(.missing):
                        return Self.makeConflictDocument(
                            from: document,
                            kind: .missingOnDisk
                        )
                    case let .failure(.appError(error)):
                        throw error
                    }
                }

                do {
                    try Data(document.text.utf8).write(to: securedURL, options: .atomic)
                } catch {
                    throw AppError.documentSaveFailed(
                        name: document.displayName,
                        details: "The latest text could not be written to disk."
                    )
                }

                switch Self.loadVersionState(at: securedURL, fallbackName: document.displayName) {
                case let .success(versionState):
                    var savedDocument = document
                    savedDocument.url = securedURL
                    savedDocument.displayName = versionState.displayName
                    savedDocument.loadedVersion = versionState.version
                    savedDocument.isDirty = false
                    savedDocument.saveState = .saved(Date())
                    savedDocument.conflictState = .none
                    return savedDocument
                case .failure(.missing):
                    throw AppError.documentSaveFailed(
                        name: document.displayName,
                        details: "The file disappeared before the saved version could be confirmed."
                    )
                case let .failure(.appError(error)):
                    throw error
                }
            }
        }.value
    }

    private func loadDocument(
        relativePath: String,
        workspaceRootURL: URL,
        fallbackName: String
    ) async throws -> OpenDocument {
        let securityScopedAccess = self.securityScopedAccess

        return try await Task.detached(priority: .userInitiated) {
            try securityScopedAccess.withAccess(
                toDescendantAt: relativePath,
                within: workspaceRootURL
            ) { securedURL in
                switch Self.loadDocumentState(at: securedURL) {
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

    nonisolated private static func makeConflictDocument(
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
        conflictedDocument.isDirty = true
        conflictedDocument.saveState = .unsaved
        conflictedDocument.conflictState = .needsResolution(
            DocumentConflict(kind: kind, error: userFacingError)
        )
        return conflictedDocument
    }

    nonisolated private static func loadDocumentState(at url: URL) -> Result<DocumentState, AppErrorOrMissing> {
        do {
            let resourceValues = try url.resourceValues(forKeys: Self.documentResourceKeys)
            guard resourceValues.isDirectory != true else {
                throw AppError.documentOpenFailed(
                    name: url.lastPathComponent,
                    details: "The selected path is not a plain text file."
                )
            }

            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                throw AppError.documentOpenFailed(
                    name: url.lastPathComponent,
                    details: "The file is unreadable as UTF-8 text."
                )
            }

            return .success(
                DocumentState(
                    displayName: resourceValues.localizedName ?? resourceValues.name ?? url.lastPathComponent,
                    text: text,
                    version: makeLoadedVersion(from: resourceValues, data: data)
                )
            )
        } catch let error as AppError {
            return .failure(AppErrorOrMissing.appError(error))
        } catch {
            return Self.wrapFilesystemError(
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

    nonisolated private static func loadVersionState(
        at url: URL,
        fallbackName: String
    ) -> Result<VersionState, AppErrorOrMissing> {
        do {
            let resourceValues = try url.resourceValues(forKeys: Self.documentResourceKeys)
            guard resourceValues.isDirectory != true else {
                throw AppError.documentSaveFailed(
                    name: fallbackName,
                    details: "The path now points to a folder instead of a file."
                )
            }

            let data = try Data(contentsOf: url)
            return .success(
                VersionState(
                    displayName: resourceValues.localizedName ?? resourceValues.name ?? fallbackName,
                    version: makeLoadedVersion(from: resourceValues, data: data)
                )
            )
        } catch let error as AppError {
            return .failure(AppErrorOrMissing.appError(error))
        } catch {
            return Self.wrapFilesystemError(
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
        data: Data
    ) -> DocumentVersion {
        DocumentVersion(
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
            return .failure(AppErrorOrMissing.missing)
        }

        return .failure(
            AppErrorOrMissing.appError(
                makeAppError(name)
            )
        )
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

private struct DocumentState: Sendable {
    let displayName: String
    let text: String
    let version: DocumentVersion
}

private struct VersionState: Sendable {
    let displayName: String
    let version: DocumentVersion
}

private enum AppErrorOrMissing: Error, Sendable {
    case appError(AppError)
    case missing
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

    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument {
        var savedDocument = document
        savedDocument.isDirty = false
        savedDocument.saveState = .saved(Date())
        savedDocument.conflictState = .none
        sampleDocuments[document.url] = savedDocument
        return savedDocument
    }
}
