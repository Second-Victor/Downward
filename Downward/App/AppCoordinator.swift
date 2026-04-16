import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppCoordinator {
    let session: AppSession

    private let workspaceManager: any WorkspaceManager
    private let documentManager: any DocumentManager
    private let sessionStore: any SessionStore
    private let recentFilesStore: RecentFilesStore
    private let errorReporter: any ErrorReporter
    private let folderPickerBridge: any FolderPickerBridge
    private let logger: DebugLogger
    private var workspaceTransitionGeneration = 0

    init(
        session: AppSession,
        workspaceManager: any WorkspaceManager,
        documentManager: any DocumentManager,
        sessionStore: any SessionStore = StubSessionStore(),
        recentFilesStore: RecentFilesStore = RecentFilesStore(initialItems: []),
        errorReporter: any ErrorReporter,
        folderPickerBridge: any FolderPickerBridge,
        logger: DebugLogger
    ) {
        self.session = session
        self.workspaceManager = workspaceManager
        self.documentManager = documentManager
        self.sessionStore = sessionStore
        self.recentFilesStore = recentFilesStore
        self.errorReporter = errorReporter
        self.folderPickerBridge = folderPickerBridge
        self.logger = logger
    }

    func bootstrapIfNeeded() async {
        guard session.hasBootstrapped == false else {
            return
        }

        session.hasBootstrapped = true
        session.launchState = .restoringWorkspace
        let generation = nextWorkspaceTransitionGeneration()

        let restoreResult = await workspaceManager.restoreWorkspace()
        applyRestoreResult(restoreResult, generation: generation)

        if case let .ready(snapshot) = restoreResult {
            await restoreLastOpenDocumentIfPossible(for: snapshot, generation: generation)
        }
    }

    func retryRestore() async {
        session.hasBootstrapped = false
        await bootstrapIfNeeded()
    }

    var folderPickerContentTypes: [UTType] {
        folderPickerBridge.allowedContentTypes
    }

    func refreshWorkspace() async -> Result<WorkspaceSnapshot, UserFacingError>? {
        guard session.launchState == .workspaceReady else {
            return .failure(
                UserFacingError(
                    title: "Workspace Unavailable",
                    message: "The workspace is not ready to refresh.",
                    recoverySuggestion: "Choose a workspace again if needed."
                )
            )
        }

        do {
            let snapshot = try await workspaceManager.refreshCurrentWorkspace()
            await applyRefreshedWorkspaceSnapshot(snapshot)
            return .success(snapshot)
        } catch is CancellationError {
            return nil
        } catch let error as AppError {
            if case let .workspaceAccessInvalid(displayName) = error {
                let reconnectError = transitionToWorkspaceReconnectState(
                    displayName: session.currentWorkspaceName ?? displayName,
                    message: "The workspace can no longer be accessed."
                )
                return .failure(reconnectError)
            }

            errorReporter.report(error, context: "Refreshing workspace")
            return .failure(errorReporter.makeUserFacingError(from: error))
        } catch {
            let appError = AppError.workspaceRestoreFailed(details: "The workspace could not be reloaded.")
            errorReporter.report(appError, context: "Refreshing workspace")
            return .failure(errorReporter.makeUserFacingError(from: appError))
        }
    }

    func createFile(
        named proposedName: String,
        in folderURL: URL?
    ) async -> Result<WorkspaceMutationOutcome, UserFacingError> {
        do {
            let mutationResult = try await workspaceManager.createFile(
                named: proposedName,
                in: folderURL
            )
            await applyWorkspaceMutationResult(mutationResult)
            return .success(mutationResult.outcome)
        } catch let error as AppError {
            if case let .workspaceAccessInvalid(displayName) = error {
                let reconnectError = transitionToWorkspaceReconnectState(
                    displayName: session.currentWorkspaceName ?? displayName,
                    message: "The workspace can no longer be accessed."
                )
                return .failure(reconnectError)
            }

            errorReporter.report(error, context: "Creating file")
            let userFacingError = errorReporter.makeUserFacingError(from: error)
            session.lastError = userFacingError
            return .failure(userFacingError)
        } catch {
            let appError = AppError.fileOperationFailed(
                action: "Create File",
                name: proposedName.isEmpty ? "Untitled.md" : proposedName,
                details: "The file could not be created."
            )
            errorReporter.report(appError, context: "Creating file")
            let userFacingError = errorReporter.makeUserFacingError(from: appError)
            session.lastError = userFacingError
            return .failure(userFacingError)
        }
    }

    func renameFile(
        at url: URL,
        to proposedName: String
    ) async -> Result<WorkspaceMutationOutcome, UserFacingError> {
        do {
            if let openDocument = session.openDocument, openDocument.url == url {
                guard openDocument.saveState != .saving else {
                    let error = UserFacingError(
                        title: "Rename File",
                        message: "\(openDocument.displayName) is still saving.",
                        recoverySuggestion: "Wait for the current save to finish, then try renaming it again."
                    )
                    session.lastError = error
                    return .failure(error)
                }

                guard openDocument.conflictState.isConflicted == false else {
                    let error = UserFacingError(
                        title: "Rename File",
                        message: "Resolve the current conflict before renaming \(openDocument.displayName).",
                        recoverySuggestion: "Finish resolving the document, then try again."
                    )
                    session.lastError = error
                    return .failure(error)
                }
            }

            let mutationResult = try await workspaceManager.renameFile(
                at: url,
                to: proposedName
            )
            await applyWorkspaceMutationResult(mutationResult)
            return .success(mutationResult.outcome)
        } catch let error as AppError {
            if case let .workspaceAccessInvalid(displayName) = error {
                let reconnectError = transitionToWorkspaceReconnectState(
                    displayName: session.currentWorkspaceName ?? displayName,
                    message: "The workspace can no longer be accessed."
                )
                return .failure(reconnectError)
            }

            errorReporter.report(error, context: "Renaming file")
            let userFacingError = errorReporter.makeUserFacingError(from: error)
            session.lastError = userFacingError
            return .failure(userFacingError)
        } catch {
            let appError = AppError.fileOperationFailed(
                action: "Rename File",
                name: url.lastPathComponent,
                details: "The file could not be renamed."
            )
            errorReporter.report(appError, context: "Renaming file")
            let userFacingError = errorReporter.makeUserFacingError(from: appError)
            session.lastError = userFacingError
            return .failure(userFacingError)
        }
    }

    func deleteFile(at url: URL) async -> Result<WorkspaceMutationOutcome, UserFacingError> {
        do {
            if let openDocument = session.openDocument, openDocument.url == url {
                if openDocument.saveState == .saving {
                    let error = UserFacingError(
                        title: "Delete File",
                        message: "\(openDocument.displayName) is still saving.",
                        recoverySuggestion: "Wait for the current save to finish, then try deleting it again."
                    )
                    session.lastError = error
                    return .failure(error)
                }

                if openDocument.isDirty || openDocument.conflictState.isConflicted {
                    let error = UserFacingError(
                        title: "Delete File",
                        message: "Finish with \(openDocument.displayName) before deleting it from the browser.",
                        recoverySuggestion: "Let it save or resolve the conflict first."
                    )
                    session.lastError = error
                    return .failure(error)
                }
            }

            let mutationResult = try await workspaceManager.deleteFile(at: url)
            await applyWorkspaceMutationResult(mutationResult)
            return .success(mutationResult.outcome)
        } catch let error as AppError {
            if case let .workspaceAccessInvalid(displayName) = error {
                let reconnectError = transitionToWorkspaceReconnectState(
                    displayName: session.currentWorkspaceName ?? displayName,
                    message: "The workspace can no longer be accessed."
                )
                return .failure(reconnectError)
            }

            errorReporter.report(error, context: "Deleting file")
            let userFacingError = errorReporter.makeUserFacingError(from: error)
            session.lastError = userFacingError
            return .failure(userFacingError)
        } catch {
            let appError = AppError.fileOperationFailed(
                action: "Delete File",
                name: url.lastPathComponent,
                details: "The file could not be deleted."
            )
            errorReporter.report(appError, context: "Deleting file")
            let userFacingError = errorReporter.makeUserFacingError(from: appError)
            session.lastError = userFacingError
            return .failure(userFacingError)
        }
    }

    func loadDocument(at url: URL) async -> Result<OpenDocument, UserFacingError> {
        guard let workspaceRootURL = session.workspaceSnapshot?.rootURL else {
            return .failure(errorReporter.makeUserFacingError(from: .missingWorkspaceSelection))
        }

        do {
            let document = try await documentManager.openDocument(at: url, in: workspaceRootURL)
            return .success(document)
        } catch let error as AppError {
            if case let .workspaceAccessInvalid(displayName) = error {
                let reconnectError = transitionToWorkspaceReconnectState(
                    displayName: session.currentWorkspaceName ?? displayName,
                    message: "The workspace can no longer be accessed."
                )
                return .failure(reconnectError)
            }

            let userFacingError = errorReporter.makeUserFacingError(from: error)
            errorReporter.report(error, context: "Opening document")
            return .failure(userFacingError)
        } catch {
            let appError = AppError.documentOpenFailed(
                name: url.lastPathComponent,
                details: "The document could not be opened."
            )
            let userFacingError = errorReporter.makeUserFacingError(from: appError)
            errorReporter.report(appError, context: "Opening document")
            return .failure(userFacingError)
        }
    }

    /// Applies a loaded document only after the caller has confirmed it is still the intended route.
    func activateLoadedDocument(_ document: OpenDocument) async {
        session.openDocument = document
        session.editorLoadError = nil
        session.lastError = nil
        await saveRestorableDocumentSession(for: document)
        recentFilesStore.record(document: document)
    }

    func updateDocumentText(_ text: String) {
        guard var document = session.openDocument else {
            return
        }

        document.text = text
        document.isDirty = true
        document.saveState = .unsaved
        session.openDocument = document
    }

    func saveDocument(
        _ document: OpenDocument,
        overwriteConflict: Bool = false
    ) async -> Result<OpenDocument, UserFacingError> {
        logger.log(
            category: "Persistence",
            "Saving \(document.relativePath) (overwriteConflict: \(overwriteConflict), dirty: \(document.isDirty), conflict: \(document.conflictState.isConflicted))"
        )

        do {
            let savedDocument = try await documentManager.saveDocument(
                document,
                overwriteConflict: overwriteConflict
            )
            session.lastError = nil
            await saveRestorableDocumentSession(for: savedDocument)
            logger.log(
                category: "Persistence",
                "Save completed for \(savedDocument.relativePath) (dirty: \(savedDocument.isDirty), conflict: \(savedDocument.conflictState.isConflicted))"
            )
            return .success(savedDocument)
        } catch let error as AppError {
            if case .documentUnavailable = error,
               let workspaceRootURL = session.workspaceSnapshot?.rootURL,
               let relativePath = relativePath(for: document.url, within: workspaceRootURL) {
                recentFilesStore.removeItem(
                    workspaceRootURL: workspaceRootURL,
                    relativePath: relativePath
                )
            }

            if case let .workspaceAccessInvalid(displayName) = error {
                let reconnectError = transitionToWorkspaceReconnectState(
                    displayName: session.currentWorkspaceName ?? displayName,
                    message: "The workspace can no longer be accessed."
                )
                return .failure(reconnectError)
            }

            errorReporter.report(error, context: "Saving document")
            let userFacingError = errorReporter.makeUserFacingError(from: error)
            session.lastError = userFacingError
            return .failure(userFacingError)
        } catch {
            let appError = AppError.documentSaveFailed(
                name: document.displayName,
                details: "The document could not be saved."
            )
            errorReporter.report(appError, context: "Saving document")
            let userFacingError = errorReporter.makeUserFacingError(from: appError)
            session.lastError = userFacingError
            return .failure(userFacingError)
        }
    }

    func observeDocumentChanges(
        for document: OpenDocument
    ) async -> Result<AsyncStream<Void>, UserFacingError> {
        do {
            return .success(try await documentManager.observeDocumentChanges(for: document))
        } catch let error as AppError {
            if case let .workspaceAccessInvalid(displayName) = error {
                let reconnectError = transitionToWorkspaceReconnectState(
                    displayName: session.currentWorkspaceName ?? displayName,
                    message: "The workspace can no longer be accessed."
                )
                return .failure(reconnectError)
            }

            errorReporter.report(error, context: "Observing document changes")
            let userFacingError = errorReporter.makeUserFacingError(from: error)
            session.lastError = userFacingError
            return .failure(userFacingError)
        } catch {
            let appError = AppError.documentOpenFailed(
                name: document.displayName,
                details: "The document could not be observed for external changes."
            )
            errorReporter.report(appError, context: "Observing document changes")
            let userFacingError = errorReporter.makeUserFacingError(from: appError)
            session.lastError = userFacingError
            return .failure(userFacingError)
        }
    }

    func revalidateObservedDocument(
        matching observedDocument: OpenDocument
    ) async -> Result<OpenDocument, UserFacingError>? {
        guard
            let openDocument = session.openDocument,
            isSameLogicalDocument(openDocument, observedDocument)
        else {
            return nil
        }

        do {
            let revalidatedDocument = try await documentManager.revalidateDocument(openDocument)
            guard
                let currentDocument = session.openDocument,
                isSameLogicalDocument(currentDocument, observedDocument)
            else {
                return nil
            }

            let documentChanged = revalidatedDocument != currentDocument
            logger.log(
                category: "Persistence",
                "Revalidated \(revalidatedDocument.relativePath) (changed: \(documentChanged), dirty: \(revalidatedDocument.isDirty), conflict: \(revalidatedDocument.conflictState.isConflicted))"
            )
            if documentChanged {
                session.openDocument = revalidatedDocument
            }

            if revalidatedDocument.conflictState.isConflicted {
                if revalidatedDocument.conflictState.activeConflict?.kind == .missingOnDisk {
                    await clearRestorableDocumentSession()
                } else {
                    await saveRestorableDocumentSession(for: revalidatedDocument)
                }

                if session.path.contains(where: \.isEditor) == false {
                    session.lastError = revalidatedDocument.conflictState.activeConflict?.error
                }
            } else if documentChanged {
                await saveRestorableDocumentSession(for: revalidatedDocument)
            }

            return .success(revalidatedDocument)
        } catch let error as AppError {
            if case let .workspaceAccessInvalid(displayName) = error {
                let reconnectError = transitionToWorkspaceReconnectState(
                    displayName: session.currentWorkspaceName ?? displayName,
                    message: "The workspace can no longer be accessed."
                )
                return .failure(reconnectError)
            }

            errorReporter.report(error, context: "Observed document revalidation")
            let userFacingError = errorReporter.makeUserFacingError(from: error)
            session.lastError = userFacingError
            return .failure(userFacingError)
        } catch {
            let appError = AppError.documentOpenFailed(
                name: openDocument.displayName,
                details: "The current file state could not be refreshed."
            )
            errorReporter.report(appError, context: "Observed document revalidation")
            let userFacingError = errorReporter.makeUserFacingError(from: appError)
            session.lastError = userFacingError
            return .failure(userFacingError)
        }
    }

    func reloadDocumentFromDisk(_ document: OpenDocument) async -> Result<OpenDocument, UserFacingError> {
        do {
            let reloadedDocument = try await documentManager.reloadDocument(from: document)
            session.lastError = nil
            await saveRestorableDocumentSession(for: reloadedDocument)
            return .success(reloadedDocument)
        } catch let error as AppError {
            if case let .workspaceAccessInvalid(displayName) = error {
                let reconnectError = transitionToWorkspaceReconnectState(
                    displayName: session.currentWorkspaceName ?? displayName,
                    message: "The workspace can no longer be accessed."
                )
                return .failure(reconnectError)
            }

            errorReporter.report(error, context: "Reloading document")
            let userFacingError = errorReporter.makeUserFacingError(from: error)
            session.lastError = userFacingError
            return .failure(userFacingError)
        } catch {
            let appError = AppError.documentOpenFailed(
                name: document.displayName,
                details: "The current disk contents could not be reloaded."
            )
            errorReporter.report(appError, context: "Reloading document")
            let userFacingError = errorReporter.makeUserFacingError(from: appError)
            session.lastError = userFacingError
            return .failure(userFacingError)
        }
    }

    func preserveConflictEdits() {
        guard
            var document = session.openDocument,
            let conflict = document.conflictState.activeConflict
        else {
            return
        }

        document.isDirty = true
        document.saveState = .unsaved
        document.conflictState = .preservingEdits(conflict)
        session.openDocument = document
    }

    func presentSettings() {
        guard session.path.contains(.settings) == false else {
            return
        }

        session.path.append(.settings)
    }

    func presentFolder(_ url: URL) {
        session.path.append(.folder(url))
    }

    func presentEditor(for url: URL) {
        session.editorLoadError = nil

        if let editorIndex = session.path.lastIndex(where: \.isEditor) {
            session.path = Array(session.path.prefix(upTo: editorIndex))
        }

        session.path.append(.editor(url))
    }

    func clearWorkspace() async {
        _ = nextWorkspaceTransitionGeneration()

        do {
            try await workspaceManager.clearWorkspaceSelection()
            await clearRestorableDocumentSession()
            session.workspaceSnapshot = nil
            session.workspaceAccessState = .noneSelected
            session.openDocument = nil
            session.editorLoadError = nil
            session.path = []
            session.lastError = nil
            session.launchState = .noWorkspaceSelected
        } catch let error as AppError {
            errorReporter.report(error, context: "Clearing workspace")
            session.lastError = errorReporter.makeUserFacingError(from: error)
        } catch {
            let appError = AppError.workspaceClearFailed(
                details: "The workspace could not be cleared right now."
            )
            errorReporter.report(appError, context: "Clearing workspace")
            session.lastError = errorReporter.makeUserFacingError(from: appError)
        }
    }

    func didChangeNavigationPath(_ path: [AppRoute]) {
        if path.contains(where: \.isEditor) == false, session.editorLoadError != nil {
            session.editorLoadError = nil
        }
    }

    func handleSceneDidBecomeActive() async {
        guard session.launchState == .workspaceReady else {
            return
        }

        do {
            let snapshot = try await workspaceManager.refreshCurrentWorkspace()
            await applyRefreshedWorkspaceSnapshot(snapshot)
        } catch let error as AppError {
            if case let .workspaceAccessInvalid(displayName) = error {
                _ = transitionToWorkspaceReconnectState(
                    displayName: session.currentWorkspaceName ?? displayName,
                    message: "The workspace can no longer be accessed."
                )
                return
            }

            errorReporter.report(error, context: "Foreground workspace validation")
            session.lastError = errorReporter.makeUserFacingError(from: error)
            return
        } catch {
            let appError = AppError.workspaceRestoreFailed(
                details: "The workspace could not be revalidated."
            )
            errorReporter.report(appError, context: "Foreground workspace validation")
            session.lastError = errorReporter.makeUserFacingError(from: appError)
            return
        }

        guard
            let openDocument = session.openDocument,
            openDocument.saveState != .saving
        else {
            return
        }

        _ = await revalidateObservedDocument(matching: openDocument)
    }

    func handleFolderPickerResult(_ result: Result<[URL], Error>) async {
        switch folderPickerBridge.selectedURL(from: result) {
        case .success(nil):
            return
        case let .success(.some(url)):
            let isReplacingActiveWorkspace = session.launchState == .workspaceReady && session.workspaceSnapshot != nil
            let shouldAttemptDocumentRestoreAfterSelection = session.launchState == .workspaceAccessInvalid

            if isReplacingActiveWorkspace == false {
                session.launchState = .restoringWorkspace
                session.lastError = nil
            }

            let generation = nextWorkspaceTransitionGeneration()
            logger.log("Selected workspace folder: \(url.lastPathComponent)")
            let selectionResult = await workspaceManager.selectWorkspace(at: url)
            if isReplacingActiveWorkspace {
                applyWorkspaceReplacementResult(selectionResult, generation: generation)
            } else {
                applyRestoreResult(selectionResult, generation: generation)
            }

            guard generation == workspaceTransitionGeneration else {
                return
            }

            guard case let .ready(snapshot) = selectionResult else {
                return
            }

            if shouldAttemptDocumentRestoreAfterSelection {
                await restoreLastOpenDocumentIfPossible(for: snapshot, generation: generation)
            } else {
                await clearRestorableDocumentSession()
            }
        case let .failure(error):
            if session.launchState == .workspaceReady {
                session.lastError = error
            } else {
                session.launchState = .failed(error)
                session.lastError = nil
            }
        }
    }

    private func nextWorkspaceTransitionGeneration() -> Int {
        workspaceTransitionGeneration += 1
        return workspaceTransitionGeneration
    }

    private func isSameLogicalDocument(
        _ lhs: OpenDocument,
        _ rhs: OpenDocument
    ) -> Bool {
        if lhs.url == rhs.url {
            return true
        }

        return lhs.workspaceRootURL == rhs.workspaceRootURL && lhs.relativePath == rhs.relativePath
    }

    private var shouldPreserveCurrentEditorDespiteMissingSnapshotEntry: Bool {
        guard let openDocument = session.openDocument else {
            return false
        }

        return openDocument.isDirty || openDocument.saveState == .saving || openDocument.conflictState.isConflicted
    }

    /// Reconciles stale navigation and selection after a workspace refresh without disturbing
    /// an in-flight or intentionally preserved editor session.
    private func applyRefreshedWorkspaceSnapshot(_ snapshot: WorkspaceSnapshot) async {
        let previousPath = session.path
        session.workspaceSnapshot = snapshot
        session.workspaceAccessState = .ready(displayName: snapshot.displayName)
        recentFilesStore.pruneInvalidItems(using: snapshot)

        if shouldPreserveCurrentEditorDespiteMissingSnapshotEntry == false {
            let reconciledPath = reconciledNavigationPath(from: session.path, within: snapshot)
            if reconciledPath != session.path {
                session.path = reconciledPath
            }
        }

        guard let openDocument = session.openDocument else {
            if session.path.contains(where: \.isEditor) == false {
                session.editorLoadError = nil
            }
            return
        }

        guard snapshotContainsFile(relativePath: openDocument.relativePath, in: snapshot) == false else {
            return
        }

        guard shouldPreserveCurrentEditorDespiteMissingSnapshotEntry == false else {
            return
        }

        let hadVisibleEditorRoute = previousPath.contains { $0.editorURL == openDocument.url }
        session.openDocument = nil
        session.editorLoadError = nil
        session.path.removeAll(where: \.isEditor)
        await clearRestorableDocumentSession()

        if hadVisibleEditorRoute {
            session.lastError = UserFacingError(
                title: "Document Unavailable",
                message: "\(openDocument.displayName) is no longer available in the workspace.",
                recoverySuggestion: "Choose another file from the browser."
            )
        }
    }

    private func reconciledNavigationPath(
        from path: [AppRoute],
        within snapshot: WorkspaceSnapshot
    ) -> [AppRoute] {
        var reconciledPath: [AppRoute] = []

        for route in path {
            switch route {
            case .settings:
                reconciledPath.append(route)
            case let .folder(folderURL):
                guard
                    let relativePath = WorkspaceRelativePath.make(
                        for: folderURL,
                        within: snapshot.rootURL
                    ),
                    snapshotContainsFolder(relativePath: relativePath, in: snapshot)
                else {
                    return reconciledPath
                }
                reconciledPath.append(route)
            case let .editor(documentURL):
                guard
                    let relativePath = WorkspaceRelativePath.make(
                        for: documentURL,
                        within: snapshot.rootURL
                    ),
                    snapshotContainsFile(relativePath: relativePath, in: snapshot)
                else {
                    return reconciledPath
                }
                reconciledPath.append(route)
            }
        }

        return reconciledPath
    }

    private func snapshotContainsFolder(
        relativePath: String,
        in snapshot: WorkspaceSnapshot
    ) -> Bool {
        snapshotContainsNode(
            relativePath: relativePath,
            matchingFolder: true,
            within: snapshot.rootURL,
            nodes: snapshot.rootNodes
        )
    }

    private func snapshotContainsFile(
        relativePath: String,
        in snapshot: WorkspaceSnapshot
    ) -> Bool {
        snapshotContainsNode(
            relativePath: relativePath,
            matchingFolder: false,
            within: snapshot.rootURL,
            nodes: snapshot.rootNodes
        )
    }

    private func snapshotContainsNode(
        relativePath: String,
        matchingFolder: Bool,
        within workspaceRootURL: URL,
        nodes: [WorkspaceNode]
    ) -> Bool {
        for node in nodes {
            if
                let nodeRelativePath = WorkspaceRelativePath.make(
                    for: node.url,
                    within: workspaceRootURL
                ),
                nodeRelativePath == relativePath,
                node.isFolder == matchingFolder
            {
                return true
            }

            if let children = node.children,
               snapshotContainsNode(
                   relativePath: relativePath,
                   matchingFolder: matchingFolder,
                   within: workspaceRootURL,
                   nodes: children
               ) {
                return true
            }
        }

        return false
    }

    private func applyRestoreResult(_ restoreResult: WorkspaceRestoreResult, generation: Int) {
        guard generation == workspaceTransitionGeneration else {
            return
        }

        session.openDocument = nil
        session.editorLoadError = nil
        session.path = []

        switch restoreResult {
        case .noWorkspaceSelected:
            session.workspaceSnapshot = nil
            session.workspaceAccessState = .noneSelected
            session.launchState = .noWorkspaceSelected
            session.lastError = nil
        case let .ready(snapshot):
            session.workspaceSnapshot = snapshot
            session.workspaceAccessState = .ready(displayName: snapshot.displayName)
            session.launchState = .workspaceReady
            session.lastError = nil
            recentFilesStore.pruneInvalidItems(using: snapshot)
        case let .accessInvalid(accessState):
            session.workspaceSnapshot = nil
            session.workspaceAccessState = accessState
            session.launchState = .workspaceAccessInvalid
            session.lastError = accessState.invalidationError
        case let .failed(error):
            session.workspaceSnapshot = nil
            session.launchState = .failed(error)
            session.lastError = error
        }
    }

    private func applyWorkspaceReplacementResult(_ restoreResult: WorkspaceRestoreResult, generation: Int) {
        guard generation == workspaceTransitionGeneration else {
            return
        }

        switch restoreResult {
        case let .ready(snapshot):
            applyRestoreResult(.ready(snapshot), generation: generation)
        case let .accessInvalid(accessState):
            session.lastError = accessState.invalidationError
        case let .failed(error):
            session.lastError = error
        case .noWorkspaceSelected:
            break
        }
    }

    private func present(_ error: AppError, context: String) {
        errorReporter.report(error, context: context)
        session.lastError = errorReporter.makeUserFacingError(from: error)
    }

    private func applyWorkspaceMutationResult(_ mutationResult: WorkspaceMutationResult) async {
        session.workspaceSnapshot = mutationResult.snapshot
        session.lastError = nil

        switch mutationResult.outcome {
        case .createdFile:
            break
        case let .renamedFile(oldURL, newURL, displayName, newRelativePath):
            if let workspaceRootURL = session.workspaceSnapshot?.rootURL,
               let oldRelativePath = WorkspaceRelativePath.make(for: oldURL, within: workspaceRootURL) {
                recentFilesStore.renameItem(
                    workspaceRootURL: workspaceRootURL,
                    oldRelativePath: oldRelativePath,
                    newRelativePath: newRelativePath,
                    displayName: displayName
                )
            }

            session.path = session.path.map { route in
                route.replacingEditorURL(oldURL: oldURL, newURL: newURL)
            }

            if var openDocument = session.openDocument, openDocument.url == oldURL {
                await documentManager.relocateDocumentSession(
                    for: openDocument,
                    to: newURL,
                    relativePath: newRelativePath
                )
                openDocument.url = newURL
                openDocument.relativePath = newRelativePath
                openDocument.displayName = displayName
                session.openDocument = openDocument
                await saveRestorableDocumentSession(for: openDocument)
            }
        case let .deletedFile(url, displayName):
            if let workspaceRootURL = session.workspaceSnapshot?.rootURL,
               let relativePath = WorkspaceRelativePath.make(for: url, within: workspaceRootURL) {
                recentFilesStore.removeItem(
                    workspaceRootURL: workspaceRootURL,
                    relativePath: relativePath
                )
            }

            if session.openDocument?.url == url {
                session.openDocument = nil
                session.editorLoadError = nil
                session.path.removeAll(where: { $0.editorURL == url })
                await clearRestorableDocumentSession()
                session.lastError = UserFacingError(
                    title: "Document Deleted",
                    message: "\(displayName) was deleted from the workspace.",
                    recoverySuggestion: "Choose another file from the browser."
                )
            }
        }

        recentFilesStore.pruneInvalidItems(using: mutationResult.snapshot)
    }

    private func transitionToWorkspaceReconnectState(
        displayName: String,
        message: String
    ) -> UserFacingError {
        let reconnectError = UserFacingError(
            title: "Workspace Needs Reconnect",
            message: message,
            recoverySuggestion: "Reconnect the folder to continue."
        )

        session.workspaceSnapshot = nil
        session.workspaceAccessState = .invalid(
            displayName: displayName,
            error: reconnectError
        )
        session.launchState = .workspaceAccessInvalid
        session.openDocument = nil
        session.editorLoadError = nil
        session.path = []
        session.lastError = reconnectError
        return reconnectError
    }

    private func restoreLastOpenDocumentIfPossible(
        for snapshot: WorkspaceSnapshot,
        generation: Int
    ) async {
        guard generation == workspaceTransitionGeneration else {
            return
        }

        let restorableSession: RestorableDocumentSession
        do {
            guard let loadedSession = try await sessionStore.loadRestorableDocumentSession() else {
                return
            }

            restorableSession = loadedSession
        } catch {
            logger.log("Ignoring unreadable restorable document session.")
            await clearRestorableDocumentSession()
            return
        }

        let documentURL = Self.resolveDocumentURL(
            for: restorableSession.relativePath,
            within: snapshot.rootURL
        )

        do {
            let document = try await documentManager.openDocument(
                at: documentURL,
                in: snapshot.rootURL
            )

            guard generation == workspaceTransitionGeneration else {
                return
            }

            session.openDocument = document
            session.editorLoadError = nil
            session.path = [.editor(document.url)]
            recentFilesStore.record(document: document)
        } catch let error as AppError {
            switch error {
            case .documentUnavailable:
                logger.log(
                    category: "Restore",
                    "Clearing stale last-open session for missing document \(restorableSession.relativePath)."
                )
                await clearRestorableDocumentSession()
            case .documentOpenFailed:
                logger.log(
                    category: "Restore",
                    "Clearing stale last-open session for unreadable document \(restorableSession.relativePath)."
                )
                await clearRestorableDocumentSession()
            case .workspaceAccessInvalid:
                _ = transitionToWorkspaceReconnectState(
                    displayName: snapshot.displayName,
                    message: "The workspace can no longer be accessed."
                )
            default:
                errorReporter.report(error, context: "Restoring last open document")
                session.lastError = errorReporter.makeUserFacingError(from: error)
            }
        } catch {
            let appError = AppError.documentOpenFailed(
                name: documentURL.lastPathComponent,
                details: "The previous editor document could not be restored."
            )
            errorReporter.report(appError, context: "Restoring last open document")
            session.lastError = errorReporter.makeUserFacingError(from: appError)
        }
    }

    private func saveRestorableDocumentSession(for document: OpenDocument) async {
        do {
            try await sessionStore.saveRestorableDocumentSession(
                RestorableDocumentSession(relativePath: document.relativePath)
            )
        } catch {
            logger.log("Ignoring session-store save failure for \(document.relativePath).")
        }
    }

    private func clearRestorableDocumentSession() async {
        do {
            try await sessionStore.clearRestorableDocumentSession()
        } catch {
            logger.log("Ignoring session-store clear failure.")
        }
    }

    private static func resolveDocumentURL(
        for relativePath: String,
        within rootURL: URL
    ) -> URL {
        WorkspaceRelativePath.resolve(relativePath, within: rootURL)
    }

    private func relativePath(
        for url: URL,
        within rootURL: URL
    ) -> String? {
        WorkspaceRelativePath.make(for: url, within: rootURL)
    }
}
