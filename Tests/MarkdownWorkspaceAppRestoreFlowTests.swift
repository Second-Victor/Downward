import XCTest
@testable import Downward

final class MarkdownWorkspaceAppRestoreFlowTests: MarkdownWorkspaceAppTestCase {
    @MainActor
    func testBootstrapWithMissingLastFileKeepsWorkspaceReadyWithoutReconnect() async throws {
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: "Missing.md")
        )
        let session = AppSession()
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace,
                forcedRestoreResult: .ready(PreviewSampleData.nestedWorkspace)
            ),
            documentManager: FailingDocumentManager(
                openError: .documentUnavailable(name: "Missing.md")
            ),
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.bootstrapIfNeeded()

        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.workspaceAlertError)
        XCTAssertNil(restoredSession)
    }

    @MainActor
    func testBootstrapWithRenamedLastFileKeepsWorkspaceReadyAndClearsStaleRestoreTarget() async throws {
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: "Journal/2026/OldName.md")
        )
        let session = AppSession()
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace,
                forcedRestoreResult: .ready(PreviewSampleData.nestedWorkspace)
            ),
            documentManager: FailingDocumentManager(
                openError: .documentUnavailable(name: "OldName.md")
            ),
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.bootstrapIfNeeded()
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.workspaceAlertError)
        XCTAssertNil(restoredSession)
    }

    @MainActor
    func testBootstrapWithUnreadableLastFileKeepsWorkspaceReadyAndClearsStaleRestoreTarget() async throws {
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: "Broken.md")
        )
        let session = AppSession()
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace,
                forcedRestoreResult: .ready(PreviewSampleData.nestedWorkspace)
            ),
            documentManager: FailingDocumentManager(
                openError: .documentOpenFailed(
                    name: "Broken.md",
                    details: "The file is not valid UTF-8 text."
                )
            ),
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.bootstrapIfNeeded()
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.workspaceAlertError)
        XCTAssertNil(restoredSession)
    }

    @MainActor
    func testBootstrapInvalidWorkspaceRestoreClearsStaleEditorRouteAndShowsReconnectState() async throws {
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: PreviewSampleData.cleanDocument.relativePath)
        )
        let session = AppSession()
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.editor(PreviewSampleData.cleanDocument.url)]

        let reconnectError = UserFacingError(
            title: "Workspace Needs Reconnect",
            message: "The previous folder reference is stale.",
            recoverySuggestion: "Choose the folder again or clear the stored workspace."
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace,
                forcedRestoreResult: .accessInvalid(
                    .invalid(
                        displayName: PreviewSampleData.nestedWorkspace.displayName,
                        error: reconnectError
                    )
                )
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.bootstrapIfNeeded()
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.launchState, .workspaceAccessInvalid)
        XCTAssertEqual(
            session.workspaceAccessState,
            .invalid(
                displayName: PreviewSampleData.nestedWorkspace.displayName,
                error: reconnectError
            )
        )
        XCTAssertNil(session.workspaceSnapshot)
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.workspaceAlertError)
        XCTAssertEqual(restoredSession?.relativePath, PreviewSampleData.cleanDocument.relativePath)
    }

    @MainActor
    func testClearWorkspaceResetsAppStateAndNavigation() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: PreviewSampleData.nestedWorkspace.displayName)
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.editorLoadError = PreviewSampleData.failedLoadError
        session.editorAlertError = PreviewSampleData.failedLoadError
        session.path = [.settings, .editor(PreviewSampleData.cleanDocument.url)]
        session.workspaceAlertError = PreviewSampleData.saveFailedError

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.clearWorkspace()

        XCTAssertEqual(session.launchState, RootLaunchState.noWorkspaceSelected)
        XCTAssertEqual(session.workspaceAccessState, WorkspaceAccessState.noneSelected)
        XCTAssertNil(session.workspaceSnapshot)
        XCTAssertNil(session.openDocument)
        XCTAssertNil(session.editorLoadError)
        XCTAssertNil(session.editorAlertError)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.workspaceAlertError)
    }

    @MainActor
    func testClearWorkspaceRemovesStoredBookmark() async throws {
        let bookmarkStore = StubBookmarkStore(
            initialBookmark: StoredWorkspaceBookmark(
                workspaceName: PreviewSampleData.nestedWorkspace.displayName,
                lastKnownPath: PreviewSampleData.nestedWorkspace.rootURL.path,
                bookmarkData: Data("workspace-bookmark".utf8)
            )
        )
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: PreviewSampleData.nestedWorkspace.displayName)
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.settings]

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: LiveWorkspaceManager(
                bookmarkStore: bookmarkStore,
                securityScopedAccess: SmokeTestSecurityScopedAccessHandler(),
                workspaceEnumerator: StubWorkspaceEnumerator(snapshot: PreviewSampleData.nestedWorkspace)
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.clearWorkspace()

        let bookmark = try await bookmarkStore.loadBookmark()
        XCTAssertNil(bookmark)
        XCTAssertEqual(session.launchState, RootLaunchState.noWorkspaceSelected)
        XCTAssertEqual(session.path, [])
    }

    @MainActor
    func testClearWorkspaceFailureKeepsExistingStateAndShowsError() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: PreviewSampleData.nestedWorkspace.displayName)
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.settings]

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: PreviewSampleData.nestedWorkspace,
                clearError: .workspaceClearFailed(details: "The bookmark store is unavailable.")
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.clearWorkspace()

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertEqual(session.openDocument?.url, PreviewSampleData.cleanDocument.url)
        XCTAssertEqual(session.path, [.settings])
        XCTAssertEqual(session.workspaceAlertError?.title, "Can’t Clear Workspace")
    }

    @MainActor
    func testClearWorkspaceAfterInvalidRestoreClearsBookmarkAndDocumentSession() async throws {
        let bookmarkStore = StubBookmarkStore(
            initialBookmark: StoredWorkspaceBookmark(
                workspaceName: PreviewSampleData.nestedWorkspace.displayName,
                lastKnownPath: PreviewSampleData.nestedWorkspace.rootURL.path,
                bookmarkData: Data("workspace-bookmark".utf8)
            )
        )
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: PreviewSampleData.cleanDocument.relativePath)
        )
        let session = AppSession()
        session.launchState = .workspaceAccessInvalid
        session.workspaceAccessState = .invalid(
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            error: PreviewSampleData.invalidWorkspaceError
        )
        session.workspaceAlertError = PreviewSampleData.saveFailedError

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: LiveWorkspaceManager(
                bookmarkStore: bookmarkStore,
                securityScopedAccess: SmokeTestSecurityScopedAccessHandler(),
                workspaceEnumerator: StubWorkspaceEnumerator(snapshot: PreviewSampleData.nestedWorkspace)
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.clearWorkspace()

        let bookmark = try await bookmarkStore.loadBookmark()
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertNil(bookmark)
        XCTAssertNil(restoredSession)
        XCTAssertEqual(session.launchState, RootLaunchState.noWorkspaceSelected)
        XCTAssertEqual(session.workspaceAccessState, WorkspaceAccessState.noneSelected)
        XCTAssertNil(session.workspaceSnapshot)
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.workspaceAlertError)
    }

    @MainActor
    func testReconnectFromSettingsReplacesWorkspaceAndClearsNavigationState() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: PreviewSampleData.nestedWorkspace.displayName)
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.settings]

        let replacementWorkspaceURL = URL(filePath: "/preview/ReconnectedWorkspace")
        let replacementSnapshot = WorkspaceSnapshot(
            rootURL: replacementWorkspaceURL,
            displayName: "ReconnectedWorkspace",
            rootNodes: PreviewSampleData.emptyWorkspace.rootNodes,
            lastUpdated: PreviewSampleData.previewDate
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: replacementSnapshot,
                selectResult: .ready(replacementSnapshot)
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.handleFolderPickerResult(.success([replacementWorkspaceURL]))

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, replacementSnapshot)
        XCTAssertEqual(session.workspaceAccessState, .ready(displayName: "ReconnectedWorkspace"))
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.workspaceAlertError)
    }

    @MainActor
    func testReconnectFromInvalidWorkspaceRestoresLastOpenDocumentWhenStillValid() async throws {
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: PreviewSampleData.cleanDocument.relativePath)
        )
        let session = AppSession()
        session.launchState = .workspaceAccessInvalid
        session.workspaceAccessState = .invalid(
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            error: PreviewSampleData.invalidWorkspaceError
        )

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: PreviewSampleData.nestedWorkspace,
                selectResult: .ready(PreviewSampleData.nestedWorkspace)
            ),
            documentManager: RestorationDocumentManager(
                openedDocument: PreviewSampleData.cleanDocument
            ),
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.handleFolderPickerResult(.success([PreviewSampleData.workspaceRootURL]))
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertEqual(session.workspaceAccessState, .ready(displayName: PreviewSampleData.nestedWorkspace.displayName))
        XCTAssertEqual(session.openDocument, PreviewSampleData.cleanDocument)
        XCTAssertEqual(session.path, trustedEditorPath(for: PreviewSampleData.cleanDocument))
        XCTAssertNil(session.workspaceAlertError)
        XCTAssertEqual(restoredSession?.relativePath, PreviewSampleData.cleanDocument.relativePath)
    }

    @MainActor
    func testReconnectFromInvalidWorkspaceWithMissingLastFileKeepsBrowserAndClearsStaleRestoreTarget() async throws {
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: "Journal/2026/Missing.md")
        )
        let session = AppSession()
        session.launchState = .workspaceAccessInvalid
        session.workspaceAccessState = .invalid(
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            error: PreviewSampleData.invalidWorkspaceError
        )

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: PreviewSampleData.nestedWorkspace,
                selectResult: .ready(PreviewSampleData.nestedWorkspace)
            ),
            documentManager: FailingDocumentManager(
                openError: .documentUnavailable(name: "Missing.md")
            ),
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.handleFolderPickerResult(.success([PreviewSampleData.workspaceRootURL]))
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertEqual(session.workspaceAccessState, .ready(displayName: PreviewSampleData.nestedWorkspace.displayName))
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.workspaceAlertError)
        XCTAssertNil(restoredSession)
    }

    @MainActor
    func testReconnectFromInvalidWorkspaceWithUnreadableLastFileKeepsBrowserAndClearsStaleRestoreTarget() async throws {
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: "Broken.md")
        )
        let session = AppSession()
        session.launchState = .workspaceAccessInvalid
        session.workspaceAccessState = .invalid(
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            error: PreviewSampleData.invalidWorkspaceError
        )

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: PreviewSampleData.nestedWorkspace,
                selectResult: .ready(PreviewSampleData.nestedWorkspace)
            ),
            documentManager: FailingDocumentManager(
                openError: .documentOpenFailed(
                    name: "Broken.md",
                    details: "The file is not valid UTF-8 text."
                )
            ),
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.handleFolderPickerResult(.success([PreviewSampleData.workspaceRootURL]))
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertEqual(session.workspaceAccessState, .ready(displayName: PreviewSampleData.nestedWorkspace.displayName))
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.workspaceAlertError)
        XCTAssertNil(restoredSession)
    }

    @MainActor
    func testFailedReconnectFromSettingsKeepsExistingWorkspaceAndEditorState() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: PreviewSampleData.nestedWorkspace.displayName)
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.settings]

        let reconnectError = UserFacingError(
            title: "Can’t Open Folder",
            message: "The selected folder could not be loaded.",
            recoverySuggestion: "Try choosing the folder again."
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: PreviewSampleData.nestedWorkspace,
                selectResult: .failed(reconnectError)
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.handleFolderPickerResult(.success([URL(filePath: "/preview/BrokenWorkspace")]))

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertEqual(session.openDocument?.url, PreviewSampleData.cleanDocument.url)
        XCTAssertEqual(session.path, [.settings])
        XCTAssertEqual(session.workspaceAlertError, reconnectError)
    }

    @MainActor
    func testFailedWorkspaceReplacementDoesNotOverwriteStoredBookmark() async throws {
        let oldBookmark = StoredWorkspaceBookmark(
            workspaceName: PreviewSampleData.nestedWorkspace.displayName,
            lastKnownPath: PreviewSampleData.nestedWorkspace.rootURL.path,
            bookmarkData: Data("old-workspace-bookmark".utf8)
        )
        let bookmarkStore = StubBookmarkStore(initialBookmark: oldBookmark)
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: PreviewSampleData.nestedWorkspace.displayName)
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.settings]

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: LiveWorkspaceManager(
                bookmarkStore: bookmarkStore,
                securityScopedAccess: SmokeTestSecurityScopedAccessHandler(),
                workspaceEnumerator: FailingSmokeWorkspaceEnumerator(
                    error: AppError.workspaceRestoreFailed(
                        details: "The selected folder could not be loaded."
                    )
                )
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.handleFolderPickerResult(.success([URL(filePath: "/preview/BrokenWorkspace")]))
        let bookmark = try await bookmarkStore.loadBookmark()

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertEqual(session.openDocument?.url, PreviewSampleData.cleanDocument.url)
        XCTAssertEqual(session.path, [.settings])
        XCTAssertEqual(bookmark, oldBookmark)
        XCTAssertEqual(session.workspaceAlertError?.title, "Unable to Restore Workspace")
    }

    @MainActor
    func testForegroundRevalidationMarksMissingOpenDocumentWithoutReconnect() async throws {
        let sessionStore = StubSessionStore(
            initialSession: RestorableDocumentSession(relativePath: PreviewSampleData.cleanDocument.relativePath)
        )
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: PreviewSampleData.nestedWorkspace.displayName)
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.editor(PreviewSampleData.cleanDocument.url)]

        let missingDocument = LiveDocumentManager.makeConflictDocument(
            from: PreviewSampleData.cleanDocument,
            kind: .missingOnDisk
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: RestorationDocumentManager(
                openedDocument: PreviewSampleData.cleanDocument,
                revalidatedDocument: missingDocument
            ),
            sessionStore: sessionStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.handleSceneDidBecomeActive()
        let restoredSession = try await sessionStore.loadRestorableDocumentSession()

        XCTAssertEqual(session.launchState, .workspaceReady)
        XCTAssertEqual(session.path, trustedEditorPath(for: PreviewSampleData.cleanDocument))
        XCTAssertEqual(session.openDocument?.conflictState, missingDocument.conflictState)
        XCTAssertNil(session.workspaceAlertError)
        XCTAssertNil(restoredSession)
    }

    @MainActor
    func testForegroundWorkspaceAccessLossTransitionsToReconnectAndClearsEditorState() async {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: PreviewSampleData.nestedWorkspace.displayName)
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        session.openDocument = PreviewSampleData.cleanDocument
        session.path = [.editor(PreviewSampleData.cleanDocument.url)]

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: PreviewSampleData.nestedWorkspace,
                refreshError: .workspaceAccessInvalid(displayName: PreviewSampleData.nestedWorkspace.displayName)
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        await coordinator.handleSceneDidBecomeActive()

        XCTAssertEqual(session.launchState, .workspaceAccessInvalid)
        XCTAssertEqual(
            session.workspaceAccessState,
            .invalid(
                displayName: PreviewSampleData.nestedWorkspace.displayName,
                error: UserFacingError(
                    title: "Workspace Needs Reconnect",
                    message: "The workspace can no longer be accessed.",
                    recoverySuggestion: "Reconnect the folder to continue."
                )
            )
        )
        XCTAssertNil(session.workspaceSnapshot)
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.workspaceAlertError)
    }
}
