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

protocol WorkspaceFileCoordinating: Sendable {
    nonisolated func coordinateCreation(
        at url: URL,
        accessor: (URL) throws -> Void
    ) throws
    nonisolated func coordinateMove(
        from sourceURL: URL,
        to destinationURL: URL,
        accessor: (URL, URL) throws -> Void
    ) throws
    nonisolated func coordinateDeletion(
        at url: URL,
        accessor: (URL) throws -> Void
    ) throws
}

actor LiveWorkspaceManager: WorkspaceManager {
    private let bookmarkStore: any BookmarkStore
    private let securityScopedAccess: any SecurityScopedAccessHandling
    private let workspaceEnumerator: any WorkspaceEnumerating
    private let fileCoordinator: any WorkspaceFileCoordinating
    private var currentSnapshot: WorkspaceSnapshot?
    private var refreshGeneration = 0

    init(
        bookmarkStore: any BookmarkStore,
        securityScopedAccess: any SecurityScopedAccessHandling,
        workspaceEnumerator: any WorkspaceEnumerating,
        fileCoordinator: any WorkspaceFileCoordinating = LiveWorkspaceFileCoordinator()
    ) {
        self.bookmarkStore = bookmarkStore
        self.securityScopedAccess = securityScopedAccess
        self.workspaceEnumerator = workspaceEnumerator
        self.fileCoordinator = fileCoordinator
    }

    func restoreWorkspace() async -> WorkspaceRestoreResult {
        do {
            guard let bookmark = try await bookmarkStore.loadBookmark() else {
                currentSnapshot = nil
                return .noWorkspaceSelected
            }

            let resolvedWorkspace = try await resolvedWorkspaceReference(from: bookmark)
            guard resolvedWorkspace.isAccessible else {
                currentSnapshot = nil
                return invalidRestoreResult(
                    displayName: resolvedWorkspace.displayName,
                    message: "The previous folder can no longer be opened."
                )
            }

            let snapshot = try await loadSnapshot(
                rootURL: resolvedWorkspace.url,
                displayName: resolvedWorkspace.displayName,
                workspaceID: resolvedWorkspace.workspaceID,
                recentFileLookupPaths: resolvedWorkspace.recentFileLookupPaths
            )
            return .ready(snapshot)
        } catch let error as AppError {
            currentSnapshot = nil
            if case let .workspaceAccessInvalid(displayName) = error {
                return invalidRestoreResult(
                    displayName: displayName,
                    message: "The previous folder can no longer be opened."
                )
            }

            return failedRestoreResult(
                message: "The saved workspace could not be restored."
            )
        } catch {
            currentSnapshot = nil
            return failedRestoreResult(
                message: "The saved workspace could not be restored."
            )
        }
    }

    func selectWorkspace(at url: URL) async -> WorkspaceRestoreResult {
        let previousSnapshot = currentSnapshot

        do {
            try securityScopedAccess.validateAccess(to: url)
            let bookmarkData = try securityScopedAccess.makeBookmark(for: url)
            let pendingBookmark = StoredWorkspaceBookmark(
                workspaceName: url.lastPathComponent,
                lastKnownPath: url.path,
                bookmarkData: bookmarkData
            )

            // Workspace selection is transactional: a newly chosen folder only becomes persisted
            // restore state after its first usable snapshot succeeds.
            let snapshot = try await makeSnapshot(
                rootURL: url,
                displayName: pendingBookmark.workspaceName,
                workspaceID: pendingBookmark.workspaceID,
                recentFileLookupPaths: [url.path]
            )
            try await bookmarkStore.saveBookmark(pendingBookmark)
            currentSnapshot = snapshot
            return .ready(snapshot)
        } catch let error as AppError {
            currentSnapshot = previousSnapshot
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
            currentSnapshot = previousSnapshot
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
                displayName: currentSnapshot.displayName,
                workspaceID: currentSnapshot.workspaceID,
                recentFileLookupPaths: currentSnapshot.recentFileLookupPaths
            )
        }

        if let bookmark = try await bookmarkStore.loadBookmark() {
            let resolvedWorkspace = try await resolvedWorkspaceReference(from: bookmark)
            guard resolvedWorkspace.isAccessible else {
                throw AppError.workspaceAccessInvalid(displayName: resolvedWorkspace.displayName)
            }

            return try await loadSnapshot(
                rootURL: resolvedWorkspace.url,
                displayName: resolvedWorkspace.displayName,
                workspaceID: resolvedWorkspace.workspaceID,
                recentFileLookupPaths: resolvedWorkspace.recentFileLookupPaths
            )
        }

        throw AppError.missingWorkspaceSelection
    }

    func createFile(named proposedName: String, in folderURL: URL?) async throws -> WorkspaceMutationResult {
        let workspaceContext = try await currentWorkspaceContext()
        let fileCoordinator = self.fileCoordinator

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
            let requestedDestinationURL = Self.uniqueAvailableFileURL(
                for: normalizedName,
                in: parentURL
            )
            let destinationRelativePath = try Self.createOrRenameTargetRelativePath(
                for: requestedDestinationURL,
                within: securedRootURL
            )

            // Creation targets use the same workspace-boundary policy as existing descendants:
            // the validated parent container must remain real and in-root, and the candidate file
            // path must still reconstruct under that container without crossing a redirecting ancestor.
            guard let destinationURL = WorkspaceRelativePath.resolveCandidate(
                destinationRelativePath,
                within: securedRootURL
            ) else {
                throw AppError.fileOperationFailed(
                    action: "Create File",
                    name: normalizedName,
                    details: "The selected folder is no longer available."
                )
            }

            do {
                try fileCoordinator.coordinateCreation(at: destinationURL) { coordinatedURL in
                    try Data().write(to: coordinatedURL, options: .withoutOverwriting)
                }
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
            displayName: workspaceContext.displayName,
            workspaceID: workspaceContext.workspaceID,
            recentFileLookupPaths: workspaceContext.recentFileLookupPaths
        )
        return WorkspaceMutationResult(snapshot: snapshot, outcome: outcome)
    }

    func renameFile(at url: URL, to proposedName: String) async throws -> WorkspaceMutationResult {
        let workspaceContext = try await currentWorkspaceContext()
        let fileCoordinator = self.fileCoordinator

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
            let sourceRelativePath = try Self.relativePath(for: sourceURL, within: securedRootURL)
            let destinationRelativePath = Self.renamedRelativePath(
                from: sourceRelativePath,
                toLeafName: normalizedName
            )
            guard let destinationURL = WorkspaceRelativePath.resolveCandidate(
                destinationRelativePath,
                within: securedRootURL
            ) else {
                throw AppError.fileOperationFailed(
                    action: "Rename File",
                    name: sourceURL.lastPathComponent,
                    details: "The file is outside the current workspace."
                )
            }

            guard destinationURL != sourceURL else {
                return .renamedFile(
                    oldURL: sourceURL,
                    newURL: destinationURL,
                    displayName: destinationURL.lastPathComponent,
                    relativePath: destinationRelativePath
                )
            }

            do {
                try fileCoordinator.coordinateMove(from: sourceURL, to: destinationURL) {
                    coordinatedSourceURL,
                    coordinatedDestinationURL in
                    guard FileManager.default.fileExists(atPath: coordinatedDestinationURL.path) == false else {
                        throw AppError.fileOperationFailed(
                            action: "Rename File",
                            name: coordinatedSourceURL.lastPathComponent,
                            details: "\(coordinatedDestinationURL.lastPathComponent) already exists in this folder."
                        )
                    }

                    try FileManager.default.moveItem(
                        at: coordinatedSourceURL,
                        to: coordinatedDestinationURL
                    )
                }
            } catch let error as AppError {
                throw error
            } catch {
                throw AppError.fileOperationFailed(
                    action: "Rename File",
                    name: sourceURL.lastPathComponent,
                    details: "The file could not be renamed."
                )
            }

            return .renamedFile(
                oldURL: sourceURL,
                newURL: destinationURL,
                displayName: destinationURL.lastPathComponent,
                relativePath: destinationRelativePath
            )
        }

        let snapshot = try await loadSnapshot(
            rootURL: workspaceContext.rootURL,
            displayName: workspaceContext.displayName,
            workspaceID: workspaceContext.workspaceID,
            recentFileLookupPaths: workspaceContext.recentFileLookupPaths
        )
        return WorkspaceMutationResult(snapshot: snapshot, outcome: outcome)
    }

    func deleteFile(at url: URL) async throws -> WorkspaceMutationResult {
        let workspaceContext = try await currentWorkspaceContext()
        let fileCoordinator = self.fileCoordinator

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
                try fileCoordinator.coordinateDeletion(at: sourceURL) { coordinatedURL in
                    try FileManager.default.removeItem(at: coordinatedURL)
                }
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
            displayName: workspaceContext.displayName,
            workspaceID: workspaceContext.workspaceID,
            recentFileLookupPaths: workspaceContext.recentFileLookupPaths
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

    private func loadSnapshot(
        rootURL: URL,
        displayName: String,
        workspaceID: String,
        recentFileLookupPaths: [String]
    ) async throws -> WorkspaceSnapshot {
        refreshGeneration += 1
        let generation = refreshGeneration
        let snapshot = try await makeSnapshot(
            rootURL: rootURL,
            displayName: displayName,
            workspaceID: workspaceID,
            recentFileLookupPaths: recentFileLookupPaths
        )

        if generation == refreshGeneration {
            currentSnapshot = snapshot
        }

        return snapshot
    }

    private func makeSnapshot(
        rootURL: URL,
        displayName: String,
        workspaceID: String,
        recentFileLookupPaths: [String]
    ) async throws -> WorkspaceSnapshot {
        let securityScopedAccess = self.securityScopedAccess
        let workspaceEnumerator = self.workspaceEnumerator

        let enumeratedSnapshot = try await Self.runStructuredBackgroundOperation(priority: .userInitiated) {
            try Task.checkCancellation()
            return try securityScopedAccess.withAccess(to: rootURL) { securedRootURL in
                try Task.checkCancellation()
                return try workspaceEnumerator.makeSnapshot(
                    rootURL: securedRootURL,
                    displayName: displayName
                )
            }
        }

        return WorkspaceSnapshot(
            workspaceID: workspaceID,
            recentFileLookupPaths: recentFileLookupPaths,
            rootURL: enumeratedSnapshot.rootURL,
            displayName: enumeratedSnapshot.displayName,
            rootNodes: enumeratedSnapshot.rootNodes,
            lastUpdated: enumeratedSnapshot.lastUpdated
        )
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

    private func currentWorkspaceContext() async throws -> (
        rootURL: URL,
        displayName: String,
        workspaceID: String,
        recentFileLookupPaths: [String]
    ) {
        if let currentSnapshot {
            return (
                currentSnapshot.rootURL,
                currentSnapshot.displayName,
                currentSnapshot.workspaceID,
                currentSnapshot.recentFileLookupPaths
            )
        }

        guard let bookmark = try await bookmarkStore.loadBookmark() else {
            throw AppError.missingWorkspaceSelection
        }

        let resolvedWorkspace = try await resolvedWorkspaceReference(from: bookmark)
        guard resolvedWorkspace.isAccessible else {
            throw AppError.workspaceAccessInvalid(displayName: resolvedWorkspace.displayName)
        }

        return (
            resolvedWorkspace.url,
            resolvedWorkspace.displayName,
            resolvedWorkspace.workspaceID,
            resolvedWorkspace.recentFileLookupPaths
        )
    }

    private func performMutation(
        in rootURL: URL,
        mutation: @escaping @Sendable (URL) throws -> WorkspaceMutationOutcome
    ) async throws -> WorkspaceMutationOutcome {
        let securityScopedAccess = self.securityScopedAccess

        return try await Self.runDetachedMutationOperation(priority: .userInitiated) {
            try securityScopedAccess.withAccess(to: rootURL) { securedRootURL in
                try mutation(securedRootURL)
            }
        }
    }

    /// Resolves the persisted workspace bookmark and refreshes stale bookmark data before the caller
    /// uses the URL for restore, refresh, or mutation flows.
    private func resolvedWorkspaceReference(
        from bookmark: StoredWorkspaceBookmark
    ) async throws -> ResolvedWorkspaceReference {
        let resolvedBookmark = try securityScopedAccess.resolveBookmark(bookmark.bookmarkData)

        do {
            try securityScopedAccess.validateAccess(to: resolvedBookmark.url)
        } catch {
            return ResolvedWorkspaceReference(
                url: resolvedBookmark.url,
                displayName: bookmark.workspaceName,
                workspaceID: bookmark.workspaceID,
                recentFileLookupPaths: [bookmark.lastKnownPath, resolvedBookmark.url.path],
                isAccessible: false
            )
        }

        if resolvedBookmark.isStale {
            let refreshedBookmarkData = try securityScopedAccess.makeBookmark(for: resolvedBookmark.url)
            let refreshedBookmark = StoredWorkspaceBookmark(
                workspaceName: resolvedBookmark.displayName,
                lastKnownPath: resolvedBookmark.url.path,
                bookmarkData: refreshedBookmarkData,
                workspaceID: bookmark.workspaceID
            )
            try await bookmarkStore.saveBookmark(refreshedBookmark)

            return ResolvedWorkspaceReference(
                url: resolvedBookmark.url,
                displayName: refreshedBookmark.workspaceName,
                workspaceID: refreshedBookmark.workspaceID,
                recentFileLookupPaths: [bookmark.lastKnownPath, resolvedBookmark.url.path],
                isAccessible: true
            )
        }

        return ResolvedWorkspaceReference(
            url: resolvedBookmark.url,
            displayName: bookmark.workspaceName,
            workspaceID: bookmark.workspaceID,
            recentFileLookupPaths: [bookmark.lastKnownPath, resolvedBookmark.url.path],
            isAccessible: true
        )
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
        guard let securedItemURL = WorkspaceRelativePath.resolveExisting(
            relativePath,
            within: securedRootURL
        ) else {
            throw AppError.fileOperationFailed(
                action: "Workspace File Operation",
                name: url.lastPathComponent,
                details: "The file is outside the current workspace."
            )
        }

        return securedItemURL
    }

    nonisolated private static func relativePath(for url: URL, within rootURL: URL) throws -> String {
        guard let relativePath = WorkspaceRelativePath.make(for: url, within: rootURL) else {
            throw AppError.fileOperationFailed(
                action: "Workspace File Operation",
                name: url.lastPathComponent,
                details: "The file is outside the current workspace."
            )
        }

        return relativePath
    }

    nonisolated private static func createOrRenameTargetRelativePath(
        for url: URL,
        within rootURL: URL
    ) throws -> String {
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

    nonisolated private static func renamedRelativePath(
        from sourceRelativePath: String,
        toLeafName leafName: String
    ) -> String {
        let sourceComponents = sourceRelativePath.split(separator: "/", omittingEmptySubsequences: true)
        let parentPath = sourceComponents.dropLast().joined(separator: "/")

        if parentPath.isEmpty {
            return leafName
        }

        return "\(parentPath)/\(leafName)"
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

    /// Runs snapshot enumeration as a structured child task so caller cancellation reaches the
    /// underlying file/provider read work instead of leaving it detached in the background.
    nonisolated private static func runStructuredBackgroundOperation<Value: Sendable>(
        priority: TaskPriority,
        operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask(priority: priority) {
                try Task.checkCancellation()
                let value = try operation()
                try Task.checkCancellation()
                return value
            }

            defer {
                group.cancelAll()
            }

            guard let value = try await group.next() else {
                throw CancellationError()
            }

            return value
        }
    }

    /// Workspace mutations are intentionally detached from caller cancellation once they start.
    /// Create/rename/delete are user-initiated write operations against the real workspace, and a
    /// transient view-task cancellation should not interrupt them after coordination begins.
    nonisolated private static func runDetachedMutationOperation<Value: Sendable>(
        priority: TaskPriority,
        operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await Task.detached(priority: priority) {
            try operation()
        }.value
    }
}

private struct LiveWorkspaceFileCoordinator: WorkspaceFileCoordinating {
    nonisolated func coordinateCreation(
        at url: URL,
        accessor: (URL) throws -> Void
    ) throws {
        var coordinationError: NSError?
        var accessorError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)

        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                try accessor(coordinatedURL)
            } catch {
                accessorError = error
            }
        }

        if let accessorError {
            throw accessorError
        }

        if let coordinationError {
            throw coordinationError
        }
    }

    nonisolated func coordinateMove(
        from sourceURL: URL,
        to destinationURL: URL,
        accessor: (URL, URL) throws -> Void
    ) throws {
        var coordinationError: NSError?
        var accessorError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)

        coordinator.coordinate(
            writingItemAt: sourceURL,
            options: .forMoving,
            writingItemAt: destinationURL,
            options: [],
            error: &coordinationError
        ) { coordinatedSourceURL, coordinatedDestinationURL in
            do {
                try accessor(coordinatedSourceURL, coordinatedDestinationURL)
            } catch {
                accessorError = error
            }
        }

        if let accessorError {
            throw accessorError
        }

        if let coordinationError {
            throw coordinationError
        }
    }

    nonisolated func coordinateDeletion(
        at url: URL,
        accessor: (URL) throws -> Void
    ) throws {
        var coordinationError: NSError?
        var accessorError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)

        coordinator.coordinate(
            writingItemAt: url,
            options: .forDeleting,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try accessor(coordinatedURL)
            } catch {
                accessorError = error
            }
        }

        if let accessorError {
            throw accessorError
        }

        if let coordinationError {
            throw coordinationError
        }
    }
}

private struct ResolvedWorkspaceReference: Sendable {
    let url: URL
    let displayName: String
    let workspaceID: String
    let recentFileLookupPaths: [String]
    let isAccessible: Bool
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
