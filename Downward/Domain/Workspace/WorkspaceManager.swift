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
    case createdFolder(url: URL, displayName: String)
    case renamedFile(
        oldURL: URL,
        newURL: URL,
        displayName: String,
        relativePath: String
    )
    case renamedFolder(
        oldURL: URL,
        newURL: URL,
        displayName: String,
        relativePath: String
    )
    case deletedFile(url: URL, displayName: String)
    case deletedFolder(url: URL, displayName: String)
}

/// Owns workspace access, refresh, and filesystem mutation boundaries for the selected folder.
/// Keep UI routing in coordinator/view-model policies, and add focused validation or coordination
/// helpers here before pushing file I/O into views.
protocol WorkspaceManager: Sendable {
    func restoreWorkspace() async -> WorkspaceRestoreResult
    func selectWorkspace(at url: URL) async -> WorkspaceRestoreResult
    func refreshCurrentWorkspace() async throws -> WorkspaceSnapshot
    func createFile(named proposedName: String, in folderURL: URL?) async throws -> WorkspaceMutationResult
    func createFolder(named proposedName: String, in folderURL: URL?) async throws -> WorkspaceMutationResult
    func renameFile(at url: URL, to proposedName: String) async throws -> WorkspaceMutationResult
    func moveItem(at url: URL, toFolder destinationFolderURL: URL?) async throws -> WorkspaceMutationResult
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
            let normalizedName = try Self.normalizedCreatedFileName(from: proposedName)
            let destinationURL = try Self.validatedCreationDestinationURL(
                named: normalizedName,
                action: "Create File",
                parentURL: folderURL,
                within: workspaceContext.rootURL,
                securedRootURL: securedRootURL
            ) { parentURL in
                Self.uniqueAvailableFileURL(for: normalizedName, in: parentURL)
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

    func createFolder(named proposedName: String, in folderURL: URL?) async throws -> WorkspaceMutationResult {
        let workspaceContext = try await currentWorkspaceContext()
        let fileCoordinator = self.fileCoordinator

        let outcome = try await performMutation(in: workspaceContext.rootURL) { securedRootURL in
            let normalizedName = try Self.normalizedCreatedFolderName(from: proposedName)
            let destinationURL = try Self.validatedCreationDestinationURL(
                named: normalizedName,
                action: "Create Folder",
                parentURL: folderURL,
                within: workspaceContext.rootURL,
                securedRootURL: securedRootURL
            ) { parentURL in
                Self.uniqueAvailableDirectoryURL(for: normalizedName, in: parentURL)
            }

            do {
                try fileCoordinator.coordinateCreation(at: destinationURL) { coordinatedURL in
                    try FileManager.default.createDirectory(
                        at: coordinatedURL,
                        withIntermediateDirectories: false
                    )
                }
            } catch {
                throw AppError.fileOperationFailed(
                    action: "Create Folder",
                    name: normalizedName,
                    details: "The folder could not be created."
                )
            }

            return .createdFolder(
                url: destinationURL.standardizedFileURL,
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

            if sourceResourceValues.isDirectory == true {
                let normalizedSourceURL = sourceURL.standardizedFileURL
                let normalizedName = try Self.normalizedRenamedFolderName(
                    from: proposedName,
                    originalURL: normalizedSourceURL
                )
                let sourceRelativePath = try Self.relativePath(for: normalizedSourceURL, within: securedRootURL)
                let destinationRelativePath = Self.renamedRelativePath(
                    from: sourceRelativePath,
                    toLeafName: normalizedName
                )
                guard let destinationURL = WorkspaceRelativePath.resolveCandidate(
                    destinationRelativePath,
                    within: securedRootURL
                ) else {
                    throw AppError.fileOperationFailed(
                        action: "Rename Folder",
                        name: sourceURL.lastPathComponent,
                        details: "The folder is outside the current workspace."
                    )
                }
                let normalizedDestinationURL = destinationURL.standardizedFileURL

                guard normalizedDestinationURL != normalizedSourceURL else {
                    return .renamedFolder(
                        oldURL: normalizedSourceURL,
                        newURL: normalizedDestinationURL,
                        displayName: normalizedDestinationURL.lastPathComponent,
                        relativePath: destinationRelativePath
                    )
                }

                do {
                    try fileCoordinator.coordinateMove(from: normalizedSourceURL, to: normalizedDestinationURL) {
                        coordinatedSourceURL,
                        coordinatedDestinationURL in
                        try Self.moveItemAllowingCaseOnlyRename(
                            at: coordinatedSourceURL,
                            to: coordinatedDestinationURL,
                            action: "Rename Folder"
                        )
                    }
                } catch let error as AppError {
                    throw error
                } catch {
                    throw AppError.fileOperationFailed(
                        action: "Rename Folder",
                        name: sourceURL.lastPathComponent,
                        details: "The folder could not be renamed."
                    )
                }

                return .renamedFolder(
                    oldURL: normalizedSourceURL,
                    newURL: normalizedDestinationURL,
                    displayName: normalizedDestinationURL.lastPathComponent,
                    relativePath: destinationRelativePath
                )
            }

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
                    try Self.moveItemAllowingCaseOnlyRename(
                        at: coordinatedSourceURL,
                        to: coordinatedDestinationURL,
                        action: "Rename File"
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

    func moveItem(at url: URL, toFolder destinationFolderURL: URL?) async throws -> WorkspaceMutationResult {
        let workspaceContext = try await currentWorkspaceContext()
        let fileCoordinator = self.fileCoordinator

        let outcome = try await performMutation(in: workspaceContext.rootURL) { securedRootURL in
            let sourceURL = try Self.resolveWorkspaceItemURL(
                from: url,
                within: workspaceContext.rootURL,
                securedRootURL: securedRootURL
            )
            let resourceValues = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            let destinationFolderURL = try Self.resolveWorkspaceDestinationFolderURL(
                from: destinationFolderURL,
                within: workspaceContext.rootURL,
                securedRootURL: securedRootURL
            )

            if resourceValues.isDirectory == true {
                let normalizedSourceURL = sourceURL.standardizedFileURL
                let normalizedDestinationFolderURL = destinationFolderURL.standardizedFileURL

                guard Self.isSameOrDescendantURL(normalizedDestinationFolderURL, of: normalizedSourceURL) == false else {
                    throw AppError.fileOperationFailed(
                        action: "Move Folder",
                        name: normalizedSourceURL.lastPathComponent,
                        details: "Choose a different destination folder."
                    )
                }

                let destinationFolderRelativePath = Self.relativePathIfNotRoot(
                    for: normalizedDestinationFolderURL,
                    within: securedRootURL
                )
                let destinationRelativePath = Self.childRelativePath(
                    named: normalizedSourceURL.lastPathComponent,
                    in: destinationFolderRelativePath
                )
                guard let destinationURL = WorkspaceRelativePath.resolveCandidate(
                    destinationRelativePath,
                    within: securedRootURL
                ) else {
                    throw AppError.fileOperationFailed(
                        action: "Move Folder",
                        name: normalizedSourceURL.lastPathComponent,
                        details: "The folder is outside the current workspace."
                    )
                }
                let normalizedDestinationURL = destinationURL.standardizedFileURL

                if normalizedDestinationURL != normalizedSourceURL {
                    do {
                        try fileCoordinator.coordinateMove(
                            from: normalizedSourceURL,
                            to: normalizedDestinationURL
                        ) { coordinatedSourceURL, coordinatedDestinationURL in
                            try Self.moveItemAllowingCaseOnlyRename(
                                at: coordinatedSourceURL,
                                to: coordinatedDestinationURL,
                                action: "Move Folder"
                            )
                        }
                    } catch let error as AppError {
                        throw error
                    } catch {
                        throw AppError.fileOperationFailed(
                            action: "Move Folder",
                            name: normalizedSourceURL.lastPathComponent,
                            details: "The folder could not be moved."
                        )
                    }
                }

                return .renamedFolder(
                    oldURL: normalizedSourceURL,
                    newURL: normalizedDestinationURL,
                    displayName: normalizedDestinationURL.lastPathComponent,
                    relativePath: destinationRelativePath
                )
            }

            guard resourceValues.isRegularFile == true, resourceValues.isDirectory != true else {
                throw AppError.fileOperationFailed(
                    action: "Move File",
                    name: url.lastPathComponent,
                    details: "Only files can be moved from the browser."
                )
            }

            let normalizedSourceURL = sourceURL.standardizedFileURL
            let normalizedDestinationFolderURL = destinationFolderURL.standardizedFileURL
            let destinationFolderRelativePath = Self.relativePathIfNotRoot(
                for: normalizedDestinationFolderURL,
                within: securedRootURL
            )
            let destinationRelativePath = Self.childRelativePath(
                named: normalizedSourceURL.lastPathComponent,
                in: destinationFolderRelativePath
            )
            guard let destinationURL = WorkspaceRelativePath.resolveCandidate(
                destinationRelativePath,
                within: securedRootURL
            ) else {
                throw AppError.fileOperationFailed(
                    action: "Move File",
                    name: normalizedSourceURL.lastPathComponent,
                    details: "The file is outside the current workspace."
                )
            }
            let normalizedDestinationURL = destinationURL.standardizedFileURL

            if normalizedDestinationURL != normalizedSourceURL {
                do {
                    try fileCoordinator.coordinateMove(
                        from: normalizedSourceURL,
                        to: normalizedDestinationURL
                    ) { coordinatedSourceURL, coordinatedDestinationURL in
                        try Self.moveItemAllowingCaseOnlyRename(
                            at: coordinatedSourceURL,
                            to: coordinatedDestinationURL,
                            action: "Move File"
                        )
                    }
                } catch let error as AppError {
                    throw error
                } catch {
                    throw AppError.fileOperationFailed(
                        action: "Move File",
                        name: normalizedSourceURL.lastPathComponent,
                        details: "The file could not be moved."
                    )
                }
            }

            return .renamedFile(
                oldURL: normalizedSourceURL,
                newURL: normalizedDestinationURL,
                displayName: normalizedDestinationURL.lastPathComponent,
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

            if resourceValues.isDirectory == true {
                let normalizedSourceURL = sourceURL.standardizedFileURL
                do {
                    try fileCoordinator.coordinateDeletion(at: normalizedSourceURL) { coordinatedURL in
                        try FileManager.default.removeItem(at: coordinatedURL)
                    }
                } catch {
                    throw AppError.fileOperationFailed(
                        action: "Delete Folder",
                        name: sourceURL.lastPathComponent,
                        details: "The folder could not be deleted."
                    )
                }

                return .deletedFolder(
                    url: normalizedSourceURL,
                    displayName: normalizedSourceURL.lastPathComponent
                )
            }

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
        if WorkspaceIdentity.normalizedPath(for: url) == WorkspaceIdentity.normalizedPath(for: rootURL) {
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

    nonisolated private static func resolveWorkspaceDestinationFolderURL(
        from destinationFolderURL: URL?,
        within rootURL: URL,
        securedRootURL: URL
    ) throws -> URL {
        guard let destinationFolderURL else {
            return securedRootURL
        }

        let resolvedURL = try resolveWorkspaceItemURL(
            from: destinationFolderURL,
            within: rootURL,
            securedRootURL: securedRootURL
        )
        let resourceValues = try resolvedURL.resourceValues(forKeys: [.isDirectoryKey])
        guard resourceValues.isDirectory == true else {
            throw AppError.fileOperationFailed(
                action: "Move File",
                name: destinationFolderURL.lastPathComponent,
                details: "Choose a destination folder in the workspace."
            )
        }

        return resolvedURL
    }

    nonisolated private static func relativePathIfNotRoot(for url: URL, within rootURL: URL) -> String? {
        guard WorkspaceIdentity.normalizedPath(for: url) != WorkspaceIdentity.normalizedPath(for: rootURL) else {
            return nil
        }

        return WorkspaceRelativePath.make(for: url, within: rootURL)
    }

    nonisolated private static func childRelativePath(named leafName: String, in parentRelativePath: String?) -> String {
        guard let parentRelativePath, parentRelativePath.isEmpty == false else {
            return leafName
        }

        return "\(parentRelativePath)/\(leafName)"
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

    nonisolated private static func normalizedCreatedFolderName(from proposedName: String) throws -> String {
        try normalizedCreatedItemName(
            from: proposedName,
            defaultName: "Untitled Folder",
            action: "Create Folder",
            emptyNameDetails: "Enter a folder name to create."
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

    nonisolated private static func normalizedRenamedFolderName(
        from proposedName: String,
        originalURL: URL
    ) throws -> String {
        try normalizedCreatedItemName(
            from: proposedName,
            defaultName: originalURL.lastPathComponent,
            action: "Rename Folder",
            emptyNameDetails: "Enter a new folder name."
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
                details: "Use a supported text or source-file extension."
            )
        }

        return rawName
    }

    nonisolated private static func moveItemAllowingCaseOnlyRename(
        at sourceURL: URL,
        to destinationURL: URL,
        action: String
    ) throws {
        let fileManager = FileManager.default
        let destinationExists = fileManager.fileExists(atPath: destinationURL.path)

        guard destinationExists else {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            return
        }

        guard try isSameFilesystemItem(sourceURL, destinationURL) else {
            throw AppError.fileOperationFailed(
                action: action,
                name: sourceURL.lastPathComponent,
                details: "\(destinationURL.lastPathComponent) already exists in this folder."
            )
        }

        guard WorkspaceIdentity.normalizedPath(for: sourceURL) != WorkspaceIdentity.normalizedPath(for: destinationURL) else {
            return
        }

        // Case-only renames on case-insensitive volumes need a temporary sibling hop to force
        // the filesystem to materialize the new leaf name.
        let temporaryURL = uniqueTemporaryRenameHopURL(
            near: sourceURL,
            basedOn: destinationURL.lastPathComponent
        )

        do {
            try fileManager.moveItem(at: sourceURL, to: temporaryURL)
            do {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            } catch {
                try? fileManager.moveItem(at: temporaryURL, to: sourceURL)
                throw error
            }
        } catch let error as AppError {
            throw error
        } catch {
            let itemDescription = action == "Rename Folder" ? "folder" : "file"
            throw AppError.fileOperationFailed(
                action: action,
                name: sourceURL.lastPathComponent,
                details: "The \(itemDescription) could not be renamed."
            )
        }
    }

    nonisolated private static func isSameFilesystemItem(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let lhsValues = try lhs.resourceValues(forKeys: [.fileResourceIdentifierKey])
        let rhsValues = try rhs.resourceValues(forKeys: [.fileResourceIdentifierKey])

        if let lhsIdentifier = lhsValues.fileResourceIdentifier as? NSObject,
           let rhsIdentifier = rhsValues.fileResourceIdentifier as? NSObject {
            return lhsIdentifier.isEqual(rhsIdentifier)
        }

        return WorkspaceIdentity.normalizedPath(for: lhs) == WorkspaceIdentity.normalizedPath(for: rhs)
    }

    nonisolated private static func isSameOrDescendantURL(_ url: URL, of prefix: URL) -> Bool {
        let urlComponents = url.standardizedFileURL.pathComponents
        let prefixComponents = prefix.standardizedFileURL.pathComponents
        return urlComponents.starts(with: prefixComponents)
    }

    nonisolated private static func uniqueTemporaryRenameHopURL(
        near sourceURL: URL,
        basedOn destinationName: String
    ) -> URL {
        let fileManager = FileManager.default
        let parentURL = sourceURL.deletingLastPathComponent()
        let destinationStem = (destinationName as NSString).deletingPathExtension
        let destinationExtension = (destinationName as NSString).pathExtension
        let renameToken = UUID().uuidString
        var duplicateIndex = 1

        while true {
            let candidateBaseName = ".rename-hop-\(destinationStem)-\(renameToken)-\(duplicateIndex)"
            let candidateName = destinationExtension.isEmpty
                ? candidateBaseName
                : "\(candidateBaseName).\(destinationExtension)"
            let candidateURL = parentURL.appending(path: candidateName)
            if fileManager.fileExists(atPath: candidateURL.path) == false {
                return candidateURL
            }

            duplicateIndex += 1
        }
    }

    nonisolated private static func normalizedCreatedItemName(
        from proposedName: String,
        defaultName: String,
        action: String,
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
                action: action,
                name: defaultName,
                details: emptyNameDetails
            )
        }

        if rawName.hasSuffix(".") {
            throw AppError.fileOperationFailed(
                action: action,
                name: rawName,
                details: "Choose a valid folder name."
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

    nonisolated private static func uniqueAvailableDirectoryURL(
        for requestedName: String,
        in directoryURL: URL
    ) -> URL {
        let fileManager = FileManager.default
        var candidateURL = directoryURL.appending(path: requestedName)
        var duplicateIndex = 2

        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateURL = directoryURL.appending(path: "\(requestedName) \(duplicateIndex)")
            duplicateIndex += 1
        }

        return candidateURL
    }

    /// Creation targets use the same workspace-boundary policy as existing descendants: the
    /// validated parent container must remain real and in-root, and the candidate path must still
    /// reconstruct under that container without crossing a redirecting ancestor.
    nonisolated private static func validatedCreationDestinationURL(
        named itemName: String,
        action: String,
        parentURL: URL?,
        within rootURL: URL,
        securedRootURL: URL,
        candidateBuilder: (URL) -> URL
    ) throws -> URL {
        let parentURL = try parentURL.map {
            try resolveWorkspaceItemURL(
                from: $0,
                within: rootURL,
                securedRootURL: securedRootURL
            )
        } ?? securedRootURL
        let resourceValues = try parentURL.resourceValues(forKeys: [.isDirectoryKey])

        guard resourceValues.isDirectory == true else {
            throw AppError.fileOperationFailed(
                action: action,
                name: itemName,
                details: "The selected folder is no longer available."
            )
        }

        let requestedDestinationURL = candidateBuilder(parentURL)
        let parentRelativePath: String? = if WorkspaceIdentity.normalizedPath(for: parentURL)
            == WorkspaceIdentity.normalizedPath(for: securedRootURL) {
            nil
        } else {
            try relativePath(for: parentURL, within: securedRootURL)
        }
        let destinationRelativePath = if let parentRelativePath, parentRelativePath.isEmpty == false {
            "\(parentRelativePath)/\(requestedDestinationURL.lastPathComponent)"
        } else {
            requestedDestinationURL.lastPathComponent
        }

        guard let destinationURL = WorkspaceRelativePath.resolveCandidate(
            destinationRelativePath,
            within: securedRootURL
        ) else {
            throw AppError.fileOperationFailed(
                action: action,
                name: itemName,
                details: "The selected folder is no longer available."
            )
        }

        return destinationURL
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

    func createFolder(named proposedName: String, in folderURL: URL?) async throws -> WorkspaceMutationResult {
        let displayName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled Folder"
            : proposedName
        let folderURL = (folderURL ?? readySnapshot.rootURL).appending(path: displayName)

        return WorkspaceMutationResult(
            snapshot: readySnapshot,
            outcome: .createdFolder(url: folderURL, displayName: folderURL.lastPathComponent)
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

    func moveItem(at url: URL, toFolder destinationFolderURL: URL?) async throws -> WorkspaceMutationResult {
        let destinationURL = (destinationFolderURL ?? readySnapshot.rootURL).appending(path: url.lastPathComponent)
        let relativePath = WorkspaceRelativePath.make(for: destinationURL, within: readySnapshot.rootURL)
            ?? destinationURL.lastPathComponent

        return WorkspaceMutationResult(
            snapshot: readySnapshot,
            outcome: browserNode(at: url)?.isFolder == true
                ? .renamedFolder(
                    oldURL: url,
                    newURL: destinationURL,
                    displayName: destinationURL.lastPathComponent,
                    relativePath: relativePath
                )
                : .renamedFile(
                    oldURL: url,
                    newURL: destinationURL,
                    displayName: destinationURL.lastPathComponent,
                    relativePath: relativePath
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

    private func browserNode(at url: URL, in nodes: [WorkspaceNode]? = nil) -> WorkspaceNode? {
        let nodes = nodes ?? readySnapshot.rootNodes

        for node in nodes {
            if WorkspaceIdentity.normalizedPath(for: node.url) == WorkspaceIdentity.normalizedPath(for: url) {
                return node
            }

            if let children = node.children,
               let descendant = browserNode(at: url, in: children) {
                return descendant
            }
        }

        return nil
    }
}
