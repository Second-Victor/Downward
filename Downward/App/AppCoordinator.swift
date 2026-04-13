import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppCoordinator {
    let session: AppSession

    private let workspaceManager: any WorkspaceManager
    private let documentManager: any DocumentManager
    private let errorReporter: any ErrorReporter
    private let folderPickerBridge: any FolderPickerBridge
    private let logger: DebugLogger
    private var workspaceTransitionGeneration = 0

    init(
        session: AppSession,
        workspaceManager: any WorkspaceManager,
        documentManager: any DocumentManager,
        errorReporter: any ErrorReporter,
        folderPickerBridge: any FolderPickerBridge,
        logger: DebugLogger
    ) {
        self.session = session
        self.workspaceManager = workspaceManager
        self.documentManager = documentManager
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
            return .success(try await workspaceManager.refreshCurrentWorkspace())
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
            applyWorkspaceMutationResult(mutationResult)
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
            applyWorkspaceMutationResult(mutationResult)
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
            applyWorkspaceMutationResult(mutationResult)
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
            let userFacingError = errorReporter.makeUserFacingError(from: .missingWorkspaceSelection)
            session.editorLoadError = userFacingError
            return .failure(userFacingError)
        }

        do {
            session.editorLoadError = nil
            let document = try await documentManager.openDocument(at: url, in: workspaceRootURL)
            session.openDocument = document
            session.lastError = nil
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
            session.editorLoadError = userFacingError
            errorReporter.report(error, context: "Opening document")
            session.lastError = nil
            return .failure(userFacingError)
        } catch {
            let appError = AppError.documentOpenFailed(
                name: url.lastPathComponent,
                details: "The document could not be opened."
            )
            let userFacingError = errorReporter.makeUserFacingError(from: appError)
            session.editorLoadError = userFacingError
            errorReporter.report(appError, context: "Opening document")
            session.lastError = nil
            return .failure(userFacingError)
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
        do {
            let savedDocument = try await documentManager.saveDocument(
                document,
                overwriteConflict: overwriteConflict
            )
            session.lastError = nil
            return .success(savedDocument)
        } catch let error as AppError {
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

    func reloadDocumentFromDisk(_ document: OpenDocument) async -> Result<OpenDocument, UserFacingError> {
        do {
            let reloadedDocument = try await documentManager.reloadDocument(from: document)
            session.lastError = nil
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

    func clearWorkspace() async {
        _ = nextWorkspaceTransitionGeneration()
        await workspaceManager.clearWorkspaceSelection()
        session.workspaceSnapshot = nil
        session.workspaceAccessState = .noneSelected
        session.openDocument = nil
        session.editorLoadError = nil
        session.path = []
        session.lastError = nil
        session.launchState = .noWorkspaceSelected
    }

    func didChangeNavigationPath(_ path: [AppRoute]) {
        if path.contains(where: \.isEditor) == false, session.editorLoadError != nil {
            session.editorLoadError = nil
        }
    }

    func handleFolderPickerResult(_ result: Result<[URL], Error>) async {
        switch folderPickerBridge.selectedURL(from: result) {
        case .success(nil):
            return
        case let .success(.some(url)):
            session.launchState = .restoringWorkspace
            session.lastError = nil
            let generation = nextWorkspaceTransitionGeneration()
            logger.log("Selected workspace folder: \(url.lastPathComponent)")
            let selectionResult = await workspaceManager.selectWorkspace(at: url)
            applyRestoreResult(selectionResult, generation: generation)
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

    private func present(_ error: AppError, context: String) {
        errorReporter.report(error, context: context)
        session.lastError = errorReporter.makeUserFacingError(from: error)
    }

    private func applyWorkspaceMutationResult(_ mutationResult: WorkspaceMutationResult) {
        session.workspaceSnapshot = mutationResult.snapshot
        session.lastError = nil

        switch mutationResult.outcome {
        case .createdFile:
            break
        case let .renamedFile(oldURL, newURL, displayName, relativePath):
            session.path = session.path.map { route in
                route.replacingEditorURL(oldURL: oldURL, newURL: newURL)
            }

            if var openDocument = session.openDocument, openDocument.url == oldURL {
                openDocument.url = newURL
                openDocument.relativePath = relativePath
                openDocument.displayName = displayName
                session.openDocument = openDocument
            }
        case let .deletedFile(url, displayName):
            if session.openDocument?.url == url {
                session.openDocument = nil
                session.editorLoadError = nil
                session.path.removeAll(where: { $0.editorURL == url })
                session.lastError = UserFacingError(
                    title: "Document Deleted",
                    message: "\(displayName) was deleted from the workspace.",
                    recoverySuggestion: "Choose another file from the browser."
                )
            }
        }
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
}
