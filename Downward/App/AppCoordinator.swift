import Foundation
import SwiftUI
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
    private var workspaceSnapshotApplyGeneration = 0

    /// Every async operation that can replace `session.workspaceSnapshot` claims one of these tokens
    /// before it starts. Snapshot replacement, recent-file pruning, and open-document reconciliation
    /// may run only while that token is still the newest claimed token for the current workspace
    /// transition. This keeps refreshes and mutations under one explicit winner policy.
    private struct WorkspaceSnapshotApplyContext {
        let applyGeneration: Int
        let transitionGeneration: Int
    }

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
        let applyContext = nextWorkspaceSnapshotApplyContext()

        let restoreResult = await workspaceManager.restoreWorkspace()
        applyRestoreResult(restoreResult, context: applyContext)

        if case let .ready(snapshot) = restoreResult,
           shouldApplyWorkspaceSnapshotResult(applyContext) {
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

        return await runWorkspaceRefresh(
            errorContext: "Refreshing workspace",
            fallbackDetails: "The workspace could not be reloaded."
        )
    }

    func createFile(
        named proposedName: String,
        in folderURL: URL?
    ) async -> Result<WorkspaceMutationOutcome, UserFacingError> {
        let applyContext = nextWorkspaceSnapshotApplyContext()

        do {
            let mutationResult = try await workspaceManager.createFile(
                named: proposedName,
                in: folderURL
            )
            await applyWorkspaceMutationResult(mutationResult, context: applyContext)
            return .success(mutationResult.outcome)
        } catch let error as AppError {
            guard shouldApplyWorkspaceSnapshotResult(applyContext, requiresReadyWorkspace: true) else {
                return .failure(errorReporter.makeUserFacingError(from: error))
            }

            if case let .workspaceAccessInvalid(displayName) = error {
                let reconnectError = transitionToWorkspaceReconnectState(
                    displayName: session.currentWorkspaceName ?? displayName,
                    message: "The workspace can no longer be accessed."
                )
                return .failure(reconnectError)
            }

            errorReporter.report(error, context: "Creating file")
            let userFacingError = errorReporter.makeUserFacingError(from: error)
            session.workspaceAlertError = userFacingError
            return .failure(userFacingError)
        } catch {
            guard shouldApplyWorkspaceSnapshotResult(applyContext, requiresReadyWorkspace: true) else {
                return .failure(
                    errorReporter.makeUserFacingError(
                        from: AppError.fileOperationFailed(
                            action: "Create File",
                            name: proposedName.isEmpty ? "Untitled.md" : proposedName,
                            details: "The file could not be created."
                        )
                    )
                )
            }

            let appError = AppError.fileOperationFailed(
                action: "Create File",
                name: proposedName.isEmpty ? "Untitled.md" : proposedName,
                details: "The file could not be created."
            )
            errorReporter.report(appError, context: "Creating file")
            let userFacingError = errorReporter.makeUserFacingError(from: appError)
            session.workspaceAlertError = userFacingError
            return .failure(userFacingError)
        }
    }

    func createFolder(
        named proposedName: String,
        in folderURL: URL?
    ) async -> Result<WorkspaceMutationOutcome, UserFacingError> {
        let applyContext = nextWorkspaceSnapshotApplyContext()

        do {
            let mutationResult = try await workspaceManager.createFolder(
                named: proposedName,
                in: folderURL
            )
            await applyWorkspaceMutationResult(mutationResult, context: applyContext)
            return .success(mutationResult.outcome)
        } catch let error as AppError {
            guard shouldApplyWorkspaceSnapshotResult(applyContext, requiresReadyWorkspace: true) else {
                return .failure(errorReporter.makeUserFacingError(from: error))
            }

            if case let .workspaceAccessInvalid(displayName) = error {
                let reconnectError = transitionToWorkspaceReconnectState(
                    displayName: session.currentWorkspaceName ?? displayName,
                    message: "The workspace can no longer be accessed."
                )
                return .failure(reconnectError)
            }

            errorReporter.report(error, context: "Creating folder")
            let userFacingError = errorReporter.makeUserFacingError(from: error)
            session.workspaceAlertError = userFacingError
            return .failure(userFacingError)
        } catch {
            guard shouldApplyWorkspaceSnapshotResult(applyContext, requiresReadyWorkspace: true) else {
                return .failure(
                    errorReporter.makeUserFacingError(
                        from: AppError.fileOperationFailed(
                            action: "Create Folder",
                            name: proposedName.isEmpty ? "Untitled Folder" : proposedName,
                            details: "The folder could not be created."
                        )
                    )
                )
            }

            let appError = AppError.fileOperationFailed(
                action: "Create Folder",
                name: proposedName.isEmpty ? "Untitled Folder" : proposedName,
                details: "The folder could not be created."
            )
            errorReporter.report(appError, context: "Creating folder")
            let userFacingError = errorReporter.makeUserFacingError(from: appError)
            session.workspaceAlertError = userFacingError
            return .failure(userFacingError)
        }
    }

    func renameFile(
        at url: URL,
        to proposedName: String
    ) async -> Result<WorkspaceMutationOutcome, UserFacingError> {
        var applyContext: WorkspaceSnapshotApplyContext?
        let targetKind = browserItemKind(for: url)
        let targetRelativePath = session.workspaceSnapshot?.relativePath(for: url)

        do {
            if let openDocument = session.openDocument,
               openDocument.url == url
                || targetRelativePath.map({ isSameOrDescendantPath(openDocument.relativePath, of: $0) }) == true {
                guard openDocument.saveState != .saving else {
                    let error = UserFacingError(
                        title: targetKind.renameActionTitle,
                        message: "\(openDocument.displayName) is still saving.",
                        recoverySuggestion: "Wait for the current save to finish, then try renaming it again."
                    )
                    session.workspaceAlertError = error
                    return .failure(error)
                }

                guard openDocument.conflictState.isConflicted == false else {
                    let error = UserFacingError(
                        title: targetKind.renameActionTitle,
                        message: targetKind == .folder
                            ? "Resolve the current conflict before renaming the folder containing \(openDocument.displayName)."
                            : "Resolve the current conflict before renaming \(openDocument.displayName).",
                        recoverySuggestion: "Finish resolving the document, then try again."
                    )
                    session.workspaceAlertError = error
                    return .failure(error)
                }
            }

            let claimedApplyContext = nextWorkspaceSnapshotApplyContext()
            applyContext = claimedApplyContext
            let mutationResult = try await workspaceManager.renameFile(
                at: url,
                to: proposedName
            )
            await applyWorkspaceMutationResult(mutationResult, context: claimedApplyContext)
            return .success(mutationResult.outcome)
        } catch let error as AppError {
            guard let applyContext,
                  shouldApplyWorkspaceSnapshotResult(applyContext, requiresReadyWorkspace: true) else {
                return .failure(errorReporter.makeUserFacingError(from: error))
            }

            if case let .workspaceAccessInvalid(displayName) = error {
                let reconnectError = transitionToWorkspaceReconnectState(
                    displayName: session.currentWorkspaceName ?? displayName,
                    message: "The workspace can no longer be accessed."
                )
                return .failure(reconnectError)
            }

            errorReporter.report(error, context: "Renaming file")
            let userFacingError = errorReporter.makeUserFacingError(from: error)
            session.workspaceAlertError = userFacingError
            return .failure(userFacingError)
        } catch {
            guard let applyContext,
                  shouldApplyWorkspaceSnapshotResult(applyContext, requiresReadyWorkspace: true) else {
                return .failure(
                    errorReporter.makeUserFacingError(
                        from: AppError.fileOperationFailed(
                            action: targetKind.renameActionTitle,
                            name: url.lastPathComponent,
                            details: targetKind == .folder
                                ? "The folder could not be renamed."
                                : "The file could not be renamed."
                        )
                    )
                )
            }

            let appError = AppError.fileOperationFailed(
                action: targetKind.renameActionTitle,
                name: url.lastPathComponent,
                details: targetKind == .folder
                    ? "The folder could not be renamed."
                    : "The file could not be renamed."
            )
            errorReporter.report(appError, context: "Renaming file")
            let userFacingError = errorReporter.makeUserFacingError(from: appError)
            session.workspaceAlertError = userFacingError
            return .failure(userFacingError)
        }
    }

    func deleteFile(at url: URL) async -> Result<WorkspaceMutationOutcome, UserFacingError> {
        var applyContext: WorkspaceSnapshotApplyContext?
        let targetKind = browserItemKind(for: url)
        let targetRelativePath = session.workspaceSnapshot?.relativePath(for: url)

        do {
            if let openDocument = session.openDocument,
               openDocument.url == url
                || targetRelativePath.map({ isSameOrDescendantPath(openDocument.relativePath, of: $0) }) == true {
                if openDocument.saveState == .saving {
                    let error = UserFacingError(
                        title: targetKind.deleteActionTitle,
                        message: "\(openDocument.displayName) is still saving.",
                        recoverySuggestion: "Wait for the current save to finish, then try deleting it again."
                    )
                    session.workspaceAlertError = error
                    return .failure(error)
                }

                if openDocument.isDirty || openDocument.conflictState.isConflicted {
                    let error = UserFacingError(
                        title: targetKind.deleteActionTitle,
                        message: targetKind == .folder
                            ? "Finish with \(openDocument.displayName) before deleting its folder from the browser."
                            : "Finish with \(openDocument.displayName) before deleting it from the browser.",
                        recoverySuggestion: "Let it save or resolve the conflict first."
                    )
                    session.workspaceAlertError = error
                    return .failure(error)
                }
            }

            let claimedApplyContext = nextWorkspaceSnapshotApplyContext()
            applyContext = claimedApplyContext
            let mutationResult = try await workspaceManager.deleteFile(at: url)
            await applyWorkspaceMutationResult(mutationResult, context: claimedApplyContext)
            return .success(mutationResult.outcome)
        } catch let error as AppError {
            guard let applyContext,
                  shouldApplyWorkspaceSnapshotResult(applyContext, requiresReadyWorkspace: true) else {
                return .failure(errorReporter.makeUserFacingError(from: error))
            }

            if case let .workspaceAccessInvalid(displayName) = error {
                let reconnectError = transitionToWorkspaceReconnectState(
                    displayName: session.currentWorkspaceName ?? displayName,
                    message: "The workspace can no longer be accessed."
                )
                return .failure(reconnectError)
            }

            errorReporter.report(error, context: "Deleting file")
            let userFacingError = errorReporter.makeUserFacingError(from: error)
            session.workspaceAlertError = userFacingError
            return .failure(userFacingError)
        } catch {
            guard let applyContext,
                  shouldApplyWorkspaceSnapshotResult(applyContext, requiresReadyWorkspace: true) else {
                return .failure(
                    errorReporter.makeUserFacingError(
                        from: AppError.fileOperationFailed(
                            action: targetKind.deleteActionTitle,
                            name: url.lastPathComponent,
                            details: targetKind == .folder
                                ? "The folder could not be deleted."
                                : "The file could not be deleted."
                        )
                    )
                )
            }

            let appError = AppError.fileOperationFailed(
                action: targetKind.deleteActionTitle,
                name: url.lastPathComponent,
                details: targetKind == .folder
                    ? "The folder could not be deleted."
                    : "The file could not be deleted."
            )
            errorReporter.report(appError, context: "Deleting file")
            let userFacingError = errorReporter.makeUserFacingError(from: appError)
            session.workspaceAlertError = userFacingError
            return .failure(userFacingError)
        }
    }

    func loadDocument(at url: URL) async -> Result<OpenDocument, UserFacingError> {
        guard let workspaceRootURL = session.workspaceSnapshot?.rootURL else {
            return .failure(errorReporter.makeUserFacingError(from: .missingWorkspaceSelection))
        }

        do {
            let document: OpenDocument
            if let presentedRelativePath = presentedEditorRelativePath(for: url) {
                document = try await documentManager.openDocument(
                    atRelativePath: presentedRelativePath,
                    in: workspaceRootURL
                )
            } else {
                document = try await documentManager.openDocument(at: url, in: workspaceRootURL)
            }
            return .success(document)
        } catch let error as AppError {
            if let recentOpenError = recentFileOpenError(from: error, documentURL: url) {
                return .failure(recentOpenError)
            }

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
        if let pendingPresentation = session.pendingEditorPresentation,
           pendingPresentation.relativePath == document.relativePath {
            session.applyNavigationState(
                WorkspaceNavigationPolicy.replacingEditorPresentation(
                    from: session.navigationState,
                    oldURL: pendingPresentation.routeURL,
                    newURL: document.url,
                    oldRelativePath: pendingPresentation.relativePath,
                    newRelativePath: document.relativePath,
                    openDocument: session.openDocument
                )
            )
            session.pendingEditorPresentation = nil
        }

        session.openDocument = document
        session.editorLoadError = nil
        session.editorAlertError = nil
        await saveRestorableDocumentSession(for: document)
        if let snapshot = session.workspaceSnapshot {
            recentFilesStore.record(document: document, in: snapshot)
        }
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
            await saveRestorableDocumentSession(for: savedDocument)
            logger.log(
                category: "Persistence",
                "Save completed for \(savedDocument.relativePath) (dirty: \(savedDocument.isDirty), conflict: \(savedDocument.conflictState.isConflicted))"
            )
            return .success(savedDocument)
        } catch let error as AppError {
            if case .documentUnavailable = error,
               let snapshot = session.workspaceSnapshot,
               let relativePath = relativePath(for: document.url, within: snapshot.rootURL) {
                recentFilesStore.removeItem(using: snapshot, relativePath: relativePath)
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
            return .failure(userFacingError)
        } catch {
            let appError = AppError.documentSaveFailed(
                name: document.displayName,
                details: "The document could not be saved."
            )
            errorReporter.report(appError, context: "Saving document")
            let userFacingError = errorReporter.makeUserFacingError(from: appError)
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
            return .failure(userFacingError)
        } catch {
            let appError = AppError.documentOpenFailed(
                name: document.displayName,
                details: "The document could not be observed for external changes."
            )
            errorReporter.report(appError, context: "Observing document changes")
            let userFacingError = errorReporter.makeUserFacingError(from: appError)
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

                if session.visibleEditorRelativePath == nil {
                    session.workspaceAlertError = revalidatedDocument.conflictState.activeConflict?.error
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
            return .failure(userFacingError)
        } catch {
            let appError = AppError.documentOpenFailed(
                name: openDocument.displayName,
                details: "The current file state could not be refreshed."
            )
            errorReporter.report(appError, context: "Observed document revalidation")
            let userFacingError = errorReporter.makeUserFacingError(from: appError)
            return .failure(userFacingError)
        }
    }

    func reloadDocumentFromDisk(_ document: OpenDocument) async -> Result<OpenDocument, UserFacingError> {
        do {
            let reloadedDocument = try await documentManager.reloadDocument(from: document)
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
            return .failure(userFacingError)
        } catch {
            let appError = AppError.documentOpenFailed(
                name: document.displayName,
                details: "The current disk contents could not be reloaded."
            )
            errorReporter.report(appError, context: "Reloading document")
            let userFacingError = errorReporter.makeUserFacingError(from: appError)
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

    /// Normalizes compact stack history and regular detail selection when the visible layout changes.
    func updateNavigationLayout(_ layout: WorkspaceNavigationLayout) {
        guard session.navigationLayout != layout else {
            return
        }

        let visibleSelection = session.visibleDetailSelection
        session.navigationLayout = layout
        session.applyNavigationState(
            WorkspaceNavigationPolicy.stateForLayoutChange(
                visibleSelection: visibleSelection,
                layout: layout,
                resolveEditorURL: resolvedEditorURL(for:)
            )
        )
    }

    func presentSettings() {
        session.pendingEditorPresentation = nil
        applyPresentedNavigationState(
            WorkspaceNavigationPolicy.stateForPresentedSettings(
                from: session.navigationState,
                layout: session.navigationLayout
            )
        )
    }

    func presentEditor(
        relativePath: String,
        preferredURL: URL? = nil,
        source: AppSession.EditorPresentationSource = .workspace
    ) {
        guard let routeURL = editorRouteURL(for: relativePath, preferredURL: preferredURL) else {
            return
        }

        session.editorLoadError = nil
        session.editorAlertError = nil
        session.pendingEditorPresentation = .init(
            routeURL: routeURL,
            relativePath: relativePath,
            source: source
        )
        applyPresentedNavigationState(
            WorkspaceNavigationPolicy.stateForPresentedEditor(
                relativePath: relativePath,
                routeURL: routeURL,
                layout: session.navigationLayout,
                existingNavigationState: session.navigationState
            )
        )
    }

    func presentEditor(for url: URL) {
        if let relativePath = editorRelativePath(for: url) {
            presentEditor(relativePath: relativePath, preferredURL: url)
            return
        }

        session.pendingEditorPresentation = nil
        session.editorLoadError = nil
        session.editorAlertError = nil
        applyPresentedNavigationState(
            WorkspaceNavigationPolicy.stateForPresentedEditor(
                at: url,
                layout: session.navigationLayout,
                snapshot: session.workspaceSnapshot,
                openDocument: session.openDocument,
                existingNavigationState: session.navigationState
            )
        )
    }

    func clearWorkspace() async {
        _ = nextWorkspaceTransitionGeneration()

        do {
            try await workspaceManager.clearWorkspaceSelection()
            await clearRestorableDocumentSession()
            session.workspaceSnapshot = nil
            session.workspaceAccessState = .noneSelected
            session.openDocument = nil
            session.pendingEditorPresentation = nil
            session.workspaceAlertError = nil
            session.editorLoadError = nil
            session.editorAlertError = nil
            clearNavigationState()
            session.launchState = .noWorkspaceSelected
        } catch let error as AppError {
            errorReporter.report(error, context: "Clearing workspace")
            session.workspaceAlertError = errorReporter.makeUserFacingError(from: error)
        } catch {
            let appError = AppError.workspaceClearFailed(
                details: "The workspace could not be cleared right now."
            )
            errorReporter.report(appError, context: "Clearing workspace")
            session.workspaceAlertError = errorReporter.makeUserFacingError(from: appError)
        }
    }

    func didChangeNavigationPath(_ path: [AppRoute]) {
        if path.contains(where: \.isEditor) == false, session.editorLoadError != nil {
            session.editorLoadError = nil
        }

        if path.contains(where: \.isEditor) == false, session.editorAlertError != nil {
            session.editorAlertError = nil
        }

        if path.contains(where: \.isEditor) == false {
            session.pendingEditorPresentation = nil
        }
    }

    func handleSceneDidBecomeActive() async {
        guard session.launchState == .workspaceReady else {
            return
        }

        guard let result = await runWorkspaceRefresh(
            errorContext: "Foreground workspace validation",
            fallbackDetails: "The workspace could not be revalidated."
        ) else {
            return
        }

        guard case .success = result else {
            if case let .failure(error) = result, session.launchState == .workspaceReady {
                session.workspaceAlertError = error
            }
            return
        }

        guard
            let openDocument = session.openDocument,
            openDocument.saveState != .saving
        else {
            return
        }

        let revalidationResult = await revalidateObservedDocument(matching: openDocument)
        if case let .failure(error)? = revalidationResult {
            if session.visibleEditorRelativePath == openDocument.relativePath {
                session.editorAlertError = error
            } else {
                session.workspaceAlertError = error
            }
        }
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
                session.workspaceAlertError = nil
            }

            let generation = nextWorkspaceTransitionGeneration()
            let applyContext = nextWorkspaceSnapshotApplyContext()
            logger.log("Selected workspace folder: \(url.lastPathComponent)")
            let selectionResult = await workspaceManager.selectWorkspace(at: url)
            if isReplacingActiveWorkspace {
                applyWorkspaceReplacementResult(selectionResult, context: applyContext)
            } else {
                applyRestoreResult(selectionResult, context: applyContext)
            }

            guard
                generation == workspaceTransitionGeneration,
                shouldApplyWorkspaceSnapshotResult(applyContext)
            else {
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
                session.workspaceAlertError = error
            } else {
                session.launchState = .failed(error)
                session.workspaceAlertError = nil
            }
        }
    }

    private func nextWorkspaceTransitionGeneration() -> Int {
        workspaceTransitionGeneration += 1
        return workspaceTransitionGeneration
    }

    private func nextWorkspaceSnapshotApplyContext() -> WorkspaceSnapshotApplyContext {
        workspaceSnapshotApplyGeneration += 1
        return WorkspaceSnapshotApplyContext(
            applyGeneration: workspaceSnapshotApplyGeneration,
            transitionGeneration: workspaceTransitionGeneration
        )
    }

    /// Applies a snapshot result only if it still belongs to the newest claimed workspace operation
    /// for the current workspace transition. Older refreshes and older mutations become no-ops at
    /// the apply boundary, so only one winner can replace `session.workspaceSnapshot` and run the
    /// follow-on reconciliation/pruning work.
    private func runWorkspaceRefresh(
        errorContext: String,
        fallbackDetails: String
    ) async -> Result<WorkspaceSnapshot, UserFacingError>? {
        let context = nextWorkspaceSnapshotApplyContext()

        do {
            let snapshot = try await workspaceManager.refreshCurrentWorkspace()
            guard shouldApplyWorkspaceSnapshotResult(context, requiresReadyWorkspace: true) else {
                return nil
            }

            await applyRefreshedWorkspaceSnapshot(snapshot, context: context)
            return .success(snapshot)
        } catch is CancellationError {
            return nil
        } catch let error as AppError {
            guard shouldApplyWorkspaceSnapshotResult(context, requiresReadyWorkspace: true) else {
                return nil
            }

            if case let .workspaceAccessInvalid(displayName) = error {
                let reconnectError = transitionToWorkspaceReconnectState(
                    displayName: session.currentWorkspaceName ?? displayName,
                    message: "The workspace can no longer be accessed."
                )
                return .failure(reconnectError)
            }

            errorReporter.report(error, context: errorContext)
            return .failure(errorReporter.makeUserFacingError(from: error))
        } catch {
            guard shouldApplyWorkspaceSnapshotResult(context, requiresReadyWorkspace: true) else {
                return nil
            }

            let appError = AppError.workspaceRestoreFailed(details: fallbackDetails)
            errorReporter.report(appError, context: errorContext)
            return .failure(errorReporter.makeUserFacingError(from: appError))
        }
    }

    private func shouldApplyWorkspaceSnapshotResult(
        _ context: WorkspaceSnapshotApplyContext,
        requiresReadyWorkspace: Bool = false
    ) -> Bool {
        guard
            context.applyGeneration == workspaceSnapshotApplyGeneration,
            context.transitionGeneration == workspaceTransitionGeneration
        else {
            return false
        }

        return requiresReadyWorkspace == false || session.launchState == .workspaceReady
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

    /// Reconciles stale navigation and selection after a workspace refresh without disturbing
    /// an in-flight or intentionally preserved editor session.
    private func applyRefreshedWorkspaceSnapshot(
        _ snapshot: WorkspaceSnapshot,
        context: WorkspaceSnapshotApplyContext
    ) async {
        guard shouldApplyWorkspaceSnapshotResult(context, requiresReadyWorkspace: true) else {
            return
        }

        session.workspaceSnapshot = snapshot
        session.workspaceAccessState = .ready(displayName: snapshot.displayName)
        session.workspaceAlertError = nil
        recentFilesStore.adoptWorkspaceIdentity(using: snapshot)
        recentFilesStore.pruneInvalidItems(using: snapshot)
        let reconciliation = WorkspaceSessionPolicy.reconcileAfterApplyingSnapshot(
            snapshot,
            navigationState: session.navigationState,
            navigationLayout: session.navigationLayout,
            openDocument: session.openDocument,
            visibleEditorRelativePath: session.visibleEditorRelativePath
        )
        session.applyNavigationState(reconciliation.navigationState)

        if reconciliation.shouldClearOpenDocument {
            session.openDocument = nil
        }

        if reconciliation.shouldClearEditorLoadError {
            session.editorLoadError = nil
        }

        if reconciliation.shouldClearEditorAlertError {
            session.editorAlertError = nil
        }

        if reconciliation.shouldClearRestorableDocumentSession {
            await clearRestorableDocumentSession()
        }

        if let workspaceAlertError = reconciliation.workspaceAlertError {
            session.workspaceAlertError = workspaceAlertError
        }
    }

    private func applyRestoreResult(
        _ restoreResult: WorkspaceRestoreResult,
        context: WorkspaceSnapshotApplyContext
    ) {
        guard shouldApplyWorkspaceSnapshotResult(context) else {
            return
        }

        let application = WorkspaceSessionPolicy.restoreApplication(for: restoreResult)
        applyWorkspaceSessionState(application)

        if let snapshot = application.snapshotToPruneRecentFiles {
            recentFilesStore.adoptWorkspaceIdentity(using: snapshot)
            recentFilesStore.pruneInvalidItems(using: snapshot)
        }
    }

    private func applyWorkspaceReplacementResult(
        _ restoreResult: WorkspaceRestoreResult,
        context: WorkspaceSnapshotApplyContext
    ) {
        guard shouldApplyWorkspaceSnapshotResult(context) else {
            return
        }

        switch restoreResult {
        case let .ready(snapshot):
            applyRestoreResult(.ready(snapshot), context: context)
        case let .accessInvalid(accessState):
            session.workspaceAlertError = accessState.invalidationError
        case let .failed(error):
            session.workspaceAlertError = error
        case .noWorkspaceSelected:
            break
        }
    }

    private func applyWorkspaceMutationResult(
        _ mutationResult: WorkspaceMutationResult,
        context: WorkspaceSnapshotApplyContext
    ) async {
        guard shouldApplyWorkspaceSnapshotResult(context, requiresReadyWorkspace: true) else {
            return
        }

        let previousSnapshot = session.workspaceSnapshot
        session.workspaceSnapshot = mutationResult.snapshot
        session.workspaceAlertError = nil
        recentFilesStore.adoptWorkspaceIdentity(using: mutationResult.snapshot)

        switch mutationResult.outcome {
        case .createdFile:
            break
        case .createdFolder:
            break
        case let .renamedFile(oldURL, newURL, displayName, newRelativePath):
            let oldRelativePath = previousSnapshot?.relativePath(for: oldURL)

            if let oldRelativePath {
                recentFilesStore.renameItem(
                    using: mutationResult.snapshot,
                    oldRelativePath: oldRelativePath,
                    newRelativePath: newRelativePath,
                    displayName: displayName
                )
            }

            session.applyNavigationState(
                WorkspaceNavigationPolicy.replacingEditorPresentation(
                    from: session.navigationState,
                    oldURL: oldURL,
                    newURL: newURL,
                    oldRelativePath: oldRelativePath,
                    newRelativePath: newRelativePath,
                    openDocument: session.openDocument
                )
            )

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
        case let .renamedFolder(oldURL, newURL, _, newRelativePath):
            let workspaceRootURL = previousSnapshot?.rootURL ?? mutationResult.snapshot.rootURL
            let oldRelativePath = previousSnapshot?.relativePath(for: oldURL)
                ?? relativePath(for: oldURL, within: workspaceRootURL)

            if let oldRelativePath {
                recentFilesStore.renameItemsInFolder(
                    using: mutationResult.snapshot,
                    oldFolderRelativePath: oldRelativePath,
                    newFolderRelativePath: newRelativePath
                )
            }

            if let pendingPresentation = session.pendingEditorPresentation,
               let oldRelativePath,
               let updatedRelativePath = replacingPathPrefix(
                pendingPresentation.relativePath,
                oldPrefix: oldRelativePath,
                newPrefix: newRelativePath
               ) {
                let updatedRouteURL = resolvedRenamedTrustedDescendantURL(
                    existingURL: pendingPresentation.routeURL,
                    updatedRelativePath: updatedRelativePath,
                    oldFolderURL: oldURL,
                    newFolderURL: newURL,
                    snapshot: mutationResult.snapshot
                )
                session.pendingEditorPresentation = .init(
                    routeURL: updatedRouteURL,
                    relativePath: updatedRelativePath,
                    source: pendingPresentation.source
                )
            }

            session.applyNavigationState(
                WorkspaceNavigationPolicy.replacingEditorPresentation(
                    from: session.navigationState,
                    oldURL: oldURL,
                    newURL: newURL,
                    oldRelativePath: oldRelativePath,
                    newRelativePath: newRelativePath,
                    openDocument: session.openDocument,
                    includingDescendants: true,
                    workspaceRootURL: workspaceRootURL
                )
            )

            if var openDocument = session.openDocument,
               let oldRelativePath,
               let updatedRelativePath = replacingPathPrefix(
                openDocument.relativePath,
                oldPrefix: oldRelativePath,
                newPrefix: newRelativePath
               ) {
                let updatedURL = resolvedRenamedTrustedDescendantURL(
                existingURL: openDocument.url,
                updatedRelativePath: updatedRelativePath,
                oldFolderURL: oldURL,
                newFolderURL: newURL,
                snapshot: mutationResult.snapshot
               )
                await documentManager.relocateDocumentSession(
                    for: openDocument,
                    to: updatedURL,
                    relativePath: updatedRelativePath
                )
                openDocument.url = updatedURL
                openDocument.relativePath = updatedRelativePath
                openDocument.displayName = updatedURL.lastPathComponent
                session.openDocument = openDocument
                await saveRestorableDocumentSession(for: openDocument)
            }
        case let .deletedFile(url, displayName):
            let workspaceRootURL = previousSnapshot?.rootURL ?? mutationResult.snapshot.rootURL
            let deletedRelativePath = previousSnapshot?.relativePath(for: url)
                ?? relativePath(for: url, within: workspaceRootURL)
            if let relativePath = deletedRelativePath {
                recentFilesStore.removeItem(
                    using: mutationResult.snapshot,
                    relativePath: relativePath
                )
            }

            let deletedPendingPresentation = session.pendingEditorPresentation.map { pendingPresentation in
                pendingPresentation.routeURL == url
                    || deletedRelativePath.map { pendingPresentation.relativePath == $0 } == true
            } ?? false
            let deletedOpenDocument = session.openDocument.map { openDocument in
                openDocument.url == url
                    || deletedRelativePath.map { openDocument.relativePath == $0 } == true
            } ?? false
            let hadVisibleDeletedEditor = session.visibleEditorURL == url
                || deletedRelativePath.map { session.visibleEditorRelativePath == $0 } == true
            let shouldClearDeletedEditorPresentation = hadVisibleDeletedEditor || deletedOpenDocument
            let shouldShowDeletedDocumentAlert = hadVisibleDeletedEditor

            if deletedPendingPresentation {
                session.pendingEditorPresentation = nil
            }

            if shouldClearDeletedEditorPresentation {
                session.applyNavigationState(
                    WorkspaceNavigationPolicy.removingEditorPresentation(
                        from: session.navigationState,
                        workspaceRootURL: workspaceRootURL,
                        matchingRelativePath: deletedRelativePath,
                        matchingURL: url
                    )
                )
                session.editorLoadError = nil
                session.editorAlertError = nil
            }

            if deletedOpenDocument {
                session.openDocument = nil
                await clearRestorableDocumentSession()
            }

            if shouldShowDeletedDocumentAlert {
                session.workspaceAlertError = UserFacingError(
                    title: "Document Deleted",
                    message: "\(displayName) was deleted from the workspace.",
                    recoverySuggestion: "Choose another file from the browser."
                )
            }
        case let .deletedFolder(url, displayName):
            let workspaceRootURL = previousSnapshot?.rootURL ?? mutationResult.snapshot.rootURL
            let deletedRelativePath = previousSnapshot?.relativePath(for: url)
                ?? relativePath(for: url, within: workspaceRootURL)
            if let deletedRelativePath {
                recentFilesStore.removeItemsInFolder(
                    using: mutationResult.snapshot,
                    folderRelativePath: deletedRelativePath
                )
            }

            let deletedPendingPresentation = session.pendingEditorPresentation.map { pendingPresentation in
                pendingPresentation.routeURL == url
                    || deletedRelativePath.map {
                        isSameOrDescendantPath(pendingPresentation.relativePath, of: $0)
                    } == true
            } ?? false
            let deletedOpenDocument = session.openDocument.map { openDocument in
                openDocument.url == url
                    || deletedRelativePath.map {
                        isSameOrDescendantPath(openDocument.relativePath, of: $0)
                    } == true
            } ?? false
            let hadVisibleDeletedEditor = session.visibleEditorURL == url
                || deletedRelativePath.map { deletedRelativePath in
                    session.visibleEditorRelativePath.map {
                        isSameOrDescendantPath($0, of: deletedRelativePath)
                    } ?? false
                } ?? false
            let deletedDocumentName = session.openDocument?.displayName ?? displayName
            let shouldClearDeletedEditorPresentation = hadVisibleDeletedEditor || deletedOpenDocument
            let shouldShowDeletedDocumentAlert = hadVisibleDeletedEditor

            if deletedPendingPresentation {
                session.pendingEditorPresentation = nil
            }

            if shouldClearDeletedEditorPresentation {
                session.applyNavigationState(
                    WorkspaceNavigationPolicy.removingEditorPresentation(
                        from: session.navigationState,
                        workspaceRootURL: workspaceRootURL,
                        matchingRelativePath: deletedRelativePath,
                        matchingURL: url,
                        includingDescendants: true
                    )
                )
                session.editorLoadError = nil
                session.editorAlertError = nil
            }

            if deletedOpenDocument {
                session.openDocument = nil
                await clearRestorableDocumentSession()
            }

            if shouldShowDeletedDocumentAlert {
                session.workspaceAlertError = UserFacingError(
                    title: "Document Deleted",
                    message: "\(deletedDocumentName) was deleted when \(displayName) was removed from the workspace.",
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
        let application = WorkspaceSessionPolicy.reconnectApplication(
            displayName: displayName,
            message: message
        )
        applyWorkspaceSessionState(application)
        return application.workspaceAlertError ?? application.workspaceAccessState?.invalidationError ?? UserFacingError(
            title: "Workspace Needs Reconnect",
            message: message,
            recoverySuggestion: "Reconnect the folder to continue."
        )
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

        guard let documentURL = snapshot.fileURL(forRelativePath: restorableSession.relativePath) else {
            logger.log(
                category: "Restore",
                "Clearing stale last-open session for invalid document path \(restorableSession.relativePath)."
            )
            await clearRestorableDocumentSession()
            return
        }

        do {
            let document = try await documentManager.openDocument(
                atRelativePath: restorableSession.relativePath,
                in: snapshot.rootURL
            )

            guard generation == workspaceTransitionGeneration else {
                return
            }

            session.openDocument = document
            session.editorLoadError = nil
            session.editorAlertError = nil
            session.applyNavigationState(
                WorkspaceNavigationPolicy.stateForRestoredEditor(
                    document,
                    layout: session.navigationLayout
                )
            )
            recentFilesStore.record(document: document, in: snapshot)
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
                session.workspaceAlertError = errorReporter.makeUserFacingError(from: error)
            }
        } catch {
            let appError = AppError.documentOpenFailed(
                name: documentURL.lastPathComponent,
                details: "The previous editor document could not be restored."
            )
            errorReporter.report(appError, context: "Restoring last open document")
            session.workspaceAlertError = errorReporter.makeUserFacingError(from: appError)
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

    private func relativePath(
        for url: URL,
        within rootURL: URL
    ) -> String? {
        WorkspaceRelativePath.make(for: url, within: rootURL)
    }

    private func clearNavigationState() {
        session.applyNavigationState(.placeholder)
    }

    /// Compact-width editor/settings pushes are driven by direct path mutation, so wrap those
    /// presentation updates in an animation transaction to preserve the expected push transition.
    private func applyPresentedNavigationState(_ navigationState: WorkspaceNavigationState) {
        if session.navigationLayout == .compact {
            withAnimation {
                session.applyNavigationState(navigationState)
            }
        } else {
            session.applyNavigationState(navigationState)
        }
    }

    private func resolvedEditorURL(for relativePath: String) -> URL? {
        if let openDocument = session.openDocument, openDocument.relativePath == relativePath {
            return openDocument.url
        }

        return session.workspaceSnapshot?.fileURL(forRelativePath: relativePath)
    }

    private func editorRelativePath(for url: URL) -> String? {
        if let openDocument = session.openDocument, openDocument.url == url {
            return openDocument.relativePath
        }

        return session.workspaceSnapshot?.relativePath(for: url)
    }

    private func editorRouteURL(for relativePath: String, preferredURL: URL?) -> URL? {
        if let preferredURL {
            return preferredURL
        }

        if let openDocument = session.openDocument, openDocument.relativePath == relativePath {
            return openDocument.url
        }

        if let snapshotURL = session.workspaceSnapshot?.fileURL(forRelativePath: relativePath) {
            return snapshotURL
        }

        guard let workspaceRootURL = session.workspaceSnapshot?.rootURL else {
            return nil
        }

        return WorkspaceRelativePath.resolve(relativePath, within: workspaceRootURL)
    }

    /// Stale recent-file taps should clean up the entry immediately while keeping final file access
    /// inside the existing document/workspace boundary checks.
    private func recentFileOpenError(
        from error: AppError,
        documentURL: URL
    ) -> UserFacingError? {
        guard case .documentUnavailable = error else {
            return nil
        }

        guard
            let pendingPresentation = session.pendingEditorPresentation,
            pendingPresentation.source == .recentFile,
            pendingPresentation.routeURL == documentURL
                || presentedEditorRelativePath(for: documentURL) == pendingPresentation.relativePath,
            let snapshot = session.workspaceSnapshot
        else {
            return nil
        }

        recentFilesStore.removeItem(
            using: snapshot,
            relativePath: pendingPresentation.relativePath
        )

        let documentName = documentURL.lastPathComponent
        return UserFacingError(
            title: "Recent File Unavailable",
            message: "\(documentName) is no longer available in this workspace.",
            recoverySuggestion: "It was removed from Recent Files. Choose another file from the browser."
        )
    }

    /// Browser/search/recent-file loads should resolve through the UI's trusted relative-path
    /// presentation state whenever that identity is available, regardless of whether the current
    /// route/detail URL is a preferred alias or the snapshot-resolved live URL.
    private func presentedEditorRelativePath(for documentURL: URL) -> String? {
        switch session.navigationLayout {
        case .compact:
            guard let route = session.path.last, route.editorURL == documentURL else {
                return nil
            }

            return route.editorRelativePath
        case .regular:
            guard case let .editor(relativePath) = session.regularDetailSelection else {
                return nil
            }

            if session.regularWorkspaceDetail.editorURL == documentURL {
                return relativePath
            }

            if session.pendingEditorPresentation?.relativePath == relativePath {
                return relativePath
            }

            return nil
        }
    }

    private func browserItemKind(for url: URL) -> WorkspaceBrowserItemKind {
        guard
            let snapshot = session.workspaceSnapshot,
            let node = workspaceNode(at: url, in: snapshot.rootNodes)
        else {
            return .file
        }

        return node.isFolder ? .folder : .file
    }

    private func workspaceNode(at url: URL, in nodes: [WorkspaceNode]) -> WorkspaceNode? {
        for node in nodes {
            if WorkspaceIdentity.normalizedPath(for: node.url) == WorkspaceIdentity.normalizedPath(for: url) {
                return node
            }

            guard case let .folder(folder) = node,
                  let descendant = workspaceNode(at: url, in: folder.children) else {
                continue
            }

            return descendant
        }

        return nil
    }

    private func isSameOrDescendantPath(_ path: String, of prefix: String) -> Bool {
        path == prefix || path.hasPrefix("\(prefix)/")
    }

    /// Folder mutations rewrite descendant identities by relative path first so bookmark-scoped
    /// browser/search/restore state stays aligned even if route URLs were aliases.
    private func resolvedRenamedTrustedDescendantURL(
        existingURL: URL,
        updatedRelativePath: String,
        oldFolderURL: URL,
        newFolderURL: URL,
        snapshot: WorkspaceSnapshot
    ) -> URL {
        if let rewrittenURL = replacingDescendantURL(
            existingURL,
            oldPrefix: oldFolderURL,
            newPrefix: newFolderURL
        ) {
            return rewrittenURL
        }

        if let snapshotURL = snapshot.fileURL(forRelativePath: updatedRelativePath) {
            return snapshotURL
        }

        return WorkspaceRelativePath.resolve(
            updatedRelativePath,
            within: snapshot.rootURL
        )
    }

    private func replacingPathPrefix(
        _ path: String,
        oldPrefix: String,
        newPrefix: String
    ) -> String? {
        guard isSameOrDescendantPath(path, of: oldPrefix) else {
            return nil
        }

        if path == oldPrefix {
            return newPrefix
        }

        let suffix = path.dropFirst(oldPrefix.count + 1)
        return "\(newPrefix)/\(suffix)"
    }

    private func replacingDescendantURL(
        _ url: URL,
        oldPrefix: URL,
        newPrefix: URL
    ) -> URL? {
        let urlComponents = url.standardizedFileURL.pathComponents
        let oldComponents = oldPrefix.standardizedFileURL.pathComponents
        guard urlComponents.starts(with: oldComponents) else {
            return nil
        }

        let suffixComponents = urlComponents.dropFirst(oldComponents.count)
        return suffixComponents.reduce(newPrefix.standardizedFileURL) { partialURL, component in
            partialURL.appending(path: component)
        }
    }

    private func applyWorkspaceSessionState(_ application: WorkspaceSessionStateApplication) {
        session.workspaceSnapshot = application.workspaceSnapshot

        if let workspaceAccessState = application.workspaceAccessState {
            session.workspaceAccessState = workspaceAccessState
        }

        session.launchState = application.launchState
        session.workspaceAlertError = application.workspaceAlertError

        if application.shouldClearOpenDocument {
            session.openDocument = nil
        }

        if application.shouldClearEditorLoadError {
            session.editorLoadError = nil
        }

        if application.shouldClearEditorAlertError {
            session.editorAlertError = nil
        }

        session.applyNavigationState(application.navigationState)
    }
}

private enum WorkspaceBrowserItemKind {
    case file
    case folder

    var renameActionTitle: String {
        switch self {
        case .file:
            "Rename File"
        case .folder:
            "Rename Folder"
        }
    }

    var deleteActionTitle: String {
        switch self {
        case .file:
            "Delete File"
        case .folder:
            "Delete Folder"
        }
    }
}
