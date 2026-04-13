import Foundation

enum WorkspaceRestoreResult: Equatable, Sendable {
    case noWorkspaceSelected
    case ready(WorkspaceSnapshot)
    case accessInvalid(WorkspaceAccessState)
    case failed(UserFacingError)
}

struct WorkspaceMutationResult: Equatable, Sendable {
    let snapshot: WorkspaceSnapshot
    let outcome: WorkspaceMutationOutcome
}

enum WorkspaceMutationOutcome: Equatable, Sendable {
    case createdFile(url: URL, displayName: String)
    case renamedFile(
        oldURL: URL,
        newURL: URL,
        displayName: String,
        relativePath: String
    )
    case deletedFile(url: URL, displayName: String)
}

/// Owns workspace selection and restore boundaries while keeping raw bookmark work out of views.
protocol WorkspaceManager: Sendable {
    func restoreWorkspace() async -> WorkspaceRestoreResult
    func selectWorkspace(at url: URL) async -> WorkspaceRestoreResult
    func refreshCurrentWorkspace() async throws -> WorkspaceSnapshot
    func createFile(named proposedName: String, in folderURL: URL?) async throws -> WorkspaceMutationResult
    func renameFile(at url: URL, to proposedName: String) async throws -> WorkspaceMutationResult
    func deleteFile(at url: URL) async throws -> WorkspaceMutationResult
    func clearWorkspaceSelection() async throws
}

actor LiveWorkspaceManager: WorkspaceManager {
    private let bookmarkStore: any BookmarkStore
    private let securityScopedAccess: any SecurityScopedAccessHandling
    private let workspaceEnumerator: any WorkspaceEnumerating
    private var currentSnapshot: WorkspaceSnapshot?
    private var refreshGeneration = 0

    init(
        bookmarkStore: any BookmarkStore,
        securityScopedAccess: any SecurityScopedAccessHandling,
        workspaceEnumerator: any WorkspaceEnumerating
    ) {
        self.bookmarkStore = bookmarkStore
        self.securityScopedAccess = securityScopedAccess
        self.workspaceEnumerator = workspaceEnumerator
    }

    func restoreWorkspace() async -> WorkspaceRestoreResult {
        do {
            guard let bookmark = try await bookmarkStore.loadBookmark() else {
                currentSnapshot = nil
                return .noWorkspaceSelected
            }

            let resolvedBookmark = try securityScopedAccess.resolveBookmark(bookmark.bookmarkData)

            guard resolvedBookmark.isStale == false else {
                currentSnapshot = nil
                return invalidRestoreResult(
                    displayName: bookmark.workspaceName,
                    message: "The previous folder reference is stale."
                )
            }

            do {
                try securityScopedAccess.validateAccess(to: resolvedBookmark.url)
            } catch {
                currentSnapshot = nil
                return invalidRestoreResult(
                    displayName: bookmark.workspaceName,
                    message: "The previous folder can no longer be opened."
                )
            }

            let snapshot = try await loadSnapshot(
                rootURL: resolvedBookmark.url,
                displayName: bookmark.workspaceName
            )
            return .ready(snapshot)
        } catch {
            currentSnapshot = nil
            return failedRestoreResult(
                message: "The saved workspace could not be restored."
            )
        }
    }

    func selectWorkspace(at url: URL) async -> WorkspaceRestoreResult {
        do {
            try securityScopedAccess.validateAccess(to: url)
            let bookmarkData = try securityScopedAccess.makeBookmark(for: url)
            let bookmark = StoredWorkspaceBookmark(
                workspaceName: url.lastPathComponent,
                lastKnownPath: url.path,
                bookmarkData: bookmarkData
            )
            try await bookmarkStore.saveBookmark(bookmark)

            let snapshot = try await loadSnapshot(
                rootURL: url,
                displayName: bookmark.workspaceName
            )
            return .ready(snapshot)
        } catch let error as AppError {
            currentSnapshot = nil
            switch error {
            case .workspaceAccessInvalid:
                return .failed(
                    UserFacingError(
                        title: "Can’t Open Folder",
                        message: "The selected folder could not be accessed.",
                        recoverySuggestion: "Choose the folder again from Files."
                    )
                )
            default:
                return failedRestoreResult(message: error.localizedDescription)
            }
        } catch {
            currentSnapshot = nil
            return .failed(
                UserFacingError(
                    title: "Can’t Open Folder",
                    message: "The selected folder could not be loaded.",
                    recoverySuggestion: "Try choosing the folder again."
                )
            )
        }
    }

    func refreshCurrentWorkspace() async throws -> WorkspaceSnapshot {
        if let currentSnapshot {
            return try await loadSnapshot(
                rootURL: currentSnapshot.rootURL,
                displayName: currentSnapshot.displayName
            )
        }

        if let bookmark = try await bookmarkStore.loadBookmark() {
            let resolvedBookmark = try securityScopedAccess.resolveBookmark(bookmark.bookmarkData)

            guard resolvedBookmark.isStale == false else {
                throw AppError.workspaceAccessInvalid(displayName: bookmark.workspaceName)
            }

            try securityScopedAccess.validateAccess(to: resolvedBookmark.url)
            return try await loadSnapshot(
                rootURL: resolvedBookmark.url,
                displayName: bookmark.workspaceName
            )
        }

        throw AppError.missingWorkspaceSelection
    }

    func createFile(named proposedName: String, in folderURL: URL?) async throws -> WorkspaceMutationResult {
        let workspaceContext = try await currentWorkspaceContext()

        let outcome = try await performMutation(in: workspaceContext.rootURL) { securedRootURL in
            let parentURL = try folderURL.map {
                try Self.resolveWorkspaceItemURL(
                    from: $0,
                    within: workspaceContext.rootURL,
                    securedRootURL: securedRootURL
                )
            } ?? securedRootURL
            let resourceValues = try parentURL.resourceValues(forKeys: [.isDirectoryKey])

            guard resourceValues.isDirectory == true else {
                throw AppError.fileOperationFailed(
                    action: "Create File",
                    name: proposedName.isEmpty ? "Untitled.md" : proposedName,
                    details: "The selected folder is no longer available."
                )
            }

            let normalizedName = try Self.normalizedCreatedFileName(from: proposedName)
            let destinationURL = Self.uniqueAvailableFileURL(
                for: normalizedName,
                in: parentURL
            )

            do {
                try Data().write(to: destinationURL, options: .withoutOverwriting)
            } catch {
                throw AppError.fileOperationFailed(
                    action: "Create File",
                    name: normalizedName,
                    details: "The file could not be created."
                )
            }

            return .createdFile(
                url: destinationURL,
                displayName: destinationURL.lastPathComponent
            )
        }

        let snapshot = try await loadSnapshot(
            rootURL: workspaceContext.rootURL,
            displayName: workspaceContext.displayName
        )
        return WorkspaceMutationResult(snapshot: snapshot, outcome: outcome)
    }

    func renameFile(at url: URL, to proposedName: String) async throws -> WorkspaceMutationResult {
        let workspaceContext = try await currentWorkspaceContext()

        let outcome = try await performMutation(in: workspaceContext.rootURL) { securedRootURL in
            let sourceURL = try Self.resolveWorkspaceItemURL(
                from: url,
                within: workspaceContext.rootURL,
                securedRootURL: securedRootURL
            )
            let sourceResourceValues = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])

            guard sourceResourceValues.isRegularFile == true, sourceResourceValues.isDirectory != true else {
                throw AppError.fileOperationFailed(
                    action: "Rename File",
                    name: url.lastPathComponent,
                    details: "Only files can be renamed from the browser."
                )
            }

            let normalizedName = try Self.normalizedRenamedFileName(
                from: proposedName,
                originalURL: sourceURL
            )
            let destinationURL = sourceURL.deletingLastPathComponent().appending(path: normalizedName)

            guard destinationURL != sourceURL else {
                let relativePath = try Self.relativePath(
                    for: destinationURL,
                    within: securedRootURL
                )
                return .renamedFile(
                    oldURL: sourceURL,
                    newURL: destinationURL,
                    displayName: destinationURL.lastPathComponent,
                    relativePath: relativePath
                )
            }

            guard FileManager.default.fileExists(atPath: destinationURL.path) == false else {
                throw AppError.fileOperationFailed(
                    action: "Rename File",
                    name: sourceURL.lastPathComponent,
                    details: "\(destinationURL.lastPathComponent) already exists in this folder."
                )
            }

            do {
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            } catch {
                throw AppError.fileOperationFailed(
                    action: "Rename File",
                    name: sourceURL.lastPathComponent,
                    details: "The file could not be renamed."
                )
            }

            let relativePath = try Self.relativePath(
                for: destinationURL,
                within: securedRootURL
            )
            return .renamedFile(
                oldURL: sourceURL,
                newURL: destinationURL,
                displayName: destinationURL.lastPathComponent,
                relativePath: relativePath
            )
        }

        let snapshot = try await loadSnapshot(
            rootURL: workspaceContext.rootURL,
            displayName: workspaceContext.displayName
        )
        return WorkspaceMutationResult(snapshot: snapshot, outcome: outcome)
    }

    func deleteFile(at url: URL) async throws -> WorkspaceMutationResult {
        let workspaceContext = try await currentWorkspaceContext()

        let outcome = try await performMutation(in: workspaceContext.rootURL) { securedRootURL in
            let sourceURL = try Self.resolveWorkspaceItemURL(
                from: url,
                within: workspaceContext.rootURL,
                securedRootURL: securedRootURL
            )
            let resourceValues = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])

            guard resourceValues.isRegularFile == true, resourceValues.isDirectory != true else {
                throw AppError.fileOperationFailed(
                    action: "Delete File",
                    name: url.lastPathComponent,
                    details: "Only files can be deleted from the browser."
                )
            }

            do {
                try FileManager.default.removeItem(at: sourceURL)
            } catch {
                throw AppError.fileOperationFailed(
                    action: "Delete File",
                    name: sourceURL.lastPathComponent,
                    details: "The file could not be deleted."
                )
            }

            return .deletedFile(
                url: sourceURL,
                displayName: sourceURL.lastPathComponent
            )
        }

        let snapshot = try await loadSnapshot(
            rootURL: workspaceContext.rootURL,
            displayName: workspaceContext.displayName
        )
        return WorkspaceMutationResult(snapshot: snapshot, outcome: outcome)
    }

    /// Clears the stored bookmark without mutating UI state. The caller decides whether in-memory app
    /// state should also be reset so a failed clear does not leave the app partially torn down.
    func clearWorkspaceSelection() async throws {
        do {
            try await bookmarkStore.clearBookmark()
        } catch let error as AppError {
            throw AppError.workspaceClearFailed(details: error.localizedDescription)
        } catch {
            throw AppError.workspaceClearFailed(details: "The stored workspace reference could not be removed.")
        }

        currentSnapshot = nil
    }

    private func loadSnapshot(rootURL: URL, displayName: String) async throws -> WorkspaceSnapshot {
        refreshGeneration += 1
        let generation = refreshGeneration
        let securityScopedAccess = self.securityScopedAccess
        let workspaceEnumerator = self.workspaceEnumerator

        let snapshot = try await Task.detached(priority: .userInitiated) {
            try securityScopedAccess.withAccess(to: rootURL) { securedRootURL in
                try workspaceEnumerator.makeSnapshot(
                    rootURL: securedRootURL,
                    displayName: displayName
                )
            }
        }.value

        if generation == refreshGeneration {
            currentSnapshot = snapshot
        }

        return snapshot
    }

    private func invalidRestoreResult(
        displayName: String,
        message: String
    ) -> WorkspaceRestoreResult {
        .accessInvalid(
            .invalid(
                displayName: displayName,
                error: UserFacingError(
                    title: "Workspace Needs Reconnect",
                    message: message,
                    recoverySuggestion: "Choose the folder again or clear the stored workspace."
                )
            )
        )
    }

    private func failedRestoreResult(message: String) -> WorkspaceRestoreResult {
        .failed(
            UserFacingError(
                title: "Unable to Restore Workspace",
                message: message,
                recoverySuggestion: "Choose the folder again or clear the stored workspace."
            )
        )
    }

    private func currentWorkspaceContext() async throws -> (rootURL: URL, displayName: String) {
        if let currentSnapshot {
            return (currentSnapshot.rootURL, currentSnapshot.displayName)
        }

        guard let bookmark = try await bookmarkStore.loadBookmark() else {
            throw AppError.missingWorkspaceSelection
        }

        let resolvedBookmark = try securityScopedAccess.resolveBookmark(bookmark.bookmarkData)
        guard resolvedBookmark.isStale == false else {
            throw AppError.workspaceAccessInvalid(displayName: bookmark.workspaceName)
        }

        try securityScopedAccess.validateAccess(to: resolvedBookmark.url)
        return (resolvedBookmark.url, bookmark.workspaceName)
    }

    private func performMutation(
        in rootURL: URL,
        mutation: @escaping @Sendable (URL) throws -> WorkspaceMutationOutcome
    ) async throws -> WorkspaceMutationOutcome {
        let securityScopedAccess = self.securityScopedAccess

        return try await Task.detached(priority: .userInitiated) {
            try securityScopedAccess.withAccess(to: rootURL) { securedRootURL in
                try mutation(securedRootURL)
            }
        }.value
    }

    nonisolated private static func resolveWorkspaceItemURL(
        from url: URL,
        within rootURL: URL,
        securedRootURL: URL
    ) throws -> URL {
        if url == rootURL {
            return securedRootURL
        }

        let relativePath = try relativePath(for: url, within: rootURL)
        return relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .reduce(securedRootURL) { partialURL, component in
                partialURL.appending(path: String(component))
            }
    }

    nonisolated private static func relativePath(for url: URL, within rootURL: URL) throws -> String {
        let urlComponents = url.standardizedFileURL.pathComponents
        let rootComponents = rootURL.standardizedFileURL.pathComponents

        guard
            urlComponents.count > rootComponents.count,
            urlComponents.starts(with: rootComponents)
        else {
            throw AppError.fileOperationFailed(
                action: "Workspace File Operation",
                name: url.lastPathComponent,
                details: "The file is outside the current workspace."
            )
        }

        return urlComponents
            .dropFirst(rootComponents.count)
            .joined(separator: "/")
    }

    nonisolated private static func normalizedCreatedFileName(from proposedName: String) throws -> String {
        try normalizedFileName(
            from: proposedName,
            defaultName: "Untitled.md",
            preservedExtension: nil,
            emptyNameDetails: "Enter a file name to create."
        )
    }

    nonisolated private static func normalizedRenamedFileName(
        from proposedName: String,
        originalURL: URL
    ) throws -> String {
        try normalizedFileName(
            from: proposedName,
            defaultName: originalURL.lastPathComponent,
            preservedExtension: originalURL.pathExtension,
            emptyNameDetails: "Enter a new file name."
        )
    }

    nonisolated private static func normalizedFileName(
        from proposedName: String,
        defaultName: String,
        preservedExtension: String?,
        emptyNameDetails: String
    ) throws -> String {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawName = trimmedName.isEmpty ? defaultName : trimmedName

        guard
            rawName.isEmpty == false,
            rawName != ".",
            rawName != "..",
            rawName.contains("/") == false
        else {
            throw AppError.fileOperationFailed(
                action: preservedExtension == nil ? "Create File" : "Rename File",
                name: defaultName,
                details: emptyNameDetails
            )
        }

        if rawName.hasSuffix(".") {
            throw AppError.fileOperationFailed(
                action: preservedExtension == nil ? "Create File" : "Rename File",
                name: rawName,
                details: "Choose a valid file name."
            )
        }

        let pathExtension = (rawName as NSString).pathExtension

        if pathExtension.isEmpty {
            let fileExtension = if let preservedExtension, preservedExtension.isEmpty == false {
                preservedExtension
            } else {
                "md"
            }
            return "\(rawName).\(fileExtension)"
        }

        guard SupportedFileType.isSupportedExtension(pathExtension) else {
            throw AppError.fileOperationFailed(
                action: preservedExtension == nil ? "Create File" : "Rename File",
                name: rawName,
                details: "Use .md, .markdown, or .txt."
            )
        }

        return rawName
    }

    nonisolated private static func uniqueAvailableFileURL(for requestedName: String, in directoryURL: URL) -> URL {
        let fileManager = FileManager.default
        let baseName = (requestedName as NSString).deletingPathExtension
        let fileExtension = (requestedName as NSString).pathExtension
        var candidateURL = directoryURL.appending(path: requestedName)
        var duplicateIndex = 2

        while fileManager.fileExists(atPath: candidateURL.path) {
            let suffix = " \(duplicateIndex)"
            let candidateName = fileExtension.isEmpty
                ? "\(baseName)\(suffix)"
                : "\(baseName)\(suffix).\(fileExtension)"
            candidateURL = directoryURL.appending(path: candidateName)
            duplicateIndex += 1
        }

        return candidateURL
    }
}

actor StubWorkspaceManager: WorkspaceManager {
    private let bookmarkStore: any BookmarkStore
    private var readySnapshot: WorkspaceSnapshot
    private let forcedRestoreResult: WorkspaceRestoreResult?

    init(
        bookmarkStore: any BookmarkStore,
        readySnapshot: WorkspaceSnapshot,
        forcedRestoreResult: WorkspaceRestoreResult? = nil
    ) {
        self.bookmarkStore = bookmarkStore
        self.readySnapshot = readySnapshot
        self.forcedRestoreResult = forcedRestoreResult
    }

    func restoreWorkspace() async -> WorkspaceRestoreResult {
        if let forcedRestoreResult {
            return forcedRestoreResult
        }

        guard (try? await bookmarkStore.loadBookmark()) != nil else {
            return .noWorkspaceSelected
        }

        return .ready(readySnapshot)
    }

    func selectWorkspace(at url: URL) async -> WorkspaceRestoreResult {
        let snapshot = WorkspaceSnapshot(
            rootURL: url,
            displayName: url.lastPathComponent,
            rootNodes: readySnapshot.rootNodes,
            lastUpdated: readySnapshot.lastUpdated
        )
        return .ready(snapshot)
    }

    func refreshCurrentWorkspace() async throws -> WorkspaceSnapshot {
        readySnapshot
    }

    func createFile(named proposedName: String, in folderURL: URL?) async throws -> WorkspaceMutationResult {
        let displayName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled.md"
            : proposedName
        let fileURL = (folderURL ?? readySnapshot.rootURL).appending(path: displayName)

        return WorkspaceMutationResult(
            snapshot: readySnapshot,
            outcome: .createdFile(url: fileURL, displayName: fileURL.lastPathComponent)
        )
    }

    func renameFile(at url: URL, to proposedName: String) async throws -> WorkspaceMutationResult {
        let displayName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? url.lastPathComponent
            : proposedName
        let newURL = url.deletingLastPathComponent().appending(path: displayName)

        return WorkspaceMutationResult(
            snapshot: readySnapshot,
            outcome: .renamedFile(
                oldURL: url,
                newURL: newURL,
                displayName: newURL.lastPathComponent,
                relativePath: newURL.lastPathComponent
            )
        )
    }

    func deleteFile(at url: URL) async throws -> WorkspaceMutationResult {
        WorkspaceMutationResult(
            snapshot: readySnapshot,
            outcome: .deletedFile(url: url, displayName: url.lastPathComponent)
        )
    }

    func clearWorkspaceSelection() async throws {
        try await bookmarkStore.clearBookmark()
    }
}
