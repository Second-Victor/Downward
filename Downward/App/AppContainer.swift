import Foundation

@MainActor
final class AppContainer {
    let logger: DebugLogger
    let bookmarkStore: any BookmarkStore
    let sessionStore: any SessionStore
    let workspaceManager: any WorkspaceManager
    let documentManager: any DocumentManager
    let errorReporter: any ErrorReporter
    let folderPickerBridge: any FolderPickerBridge
    let lifecycleObserver: LifecycleObserver
    let session: AppSession
    let coordinator: AppCoordinator
    let workspaceViewModel: WorkspaceViewModel
    let editorViewModel: EditorViewModel
    let rootViewModel: RootViewModel

    init(
        logger: DebugLogger,
        bookmarkStore: any BookmarkStore,
        sessionStore: any SessionStore = StubSessionStore(),
        workspaceManager: any WorkspaceManager,
        documentManager: any DocumentManager,
        errorReporter: any ErrorReporter,
        folderPickerBridge: any FolderPickerBridge,
        lifecycleObserver: LifecycleObserver
    ) {
        self.logger = logger
        self.bookmarkStore = bookmarkStore
        self.sessionStore = sessionStore
        self.workspaceManager = workspaceManager
        self.documentManager = documentManager
        self.errorReporter = errorReporter
        self.folderPickerBridge = folderPickerBridge
        self.lifecycleObserver = lifecycleObserver

        let session = AppSession()
        self.session = session

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: workspaceManager,
            documentManager: documentManager,
            sessionStore: sessionStore,
            errorReporter: errorReporter,
            folderPickerBridge: folderPickerBridge,
            logger: logger
        )
        self.coordinator = coordinator

        let workspaceViewModel = WorkspaceViewModel(session: session, coordinator: coordinator)
        self.workspaceViewModel = workspaceViewModel

        let editorViewModel = EditorViewModel(session: session, coordinator: coordinator)
        self.editorViewModel = editorViewModel

        self.rootViewModel = RootViewModel(
            session: session,
            coordinator: coordinator,
            workspaceViewModel: workspaceViewModel,
            editorViewModel: editorViewModel
        )
    }

    static func live() -> AppContainer {
        let logger = DebugLogger()
        let securityScopedAccess = LiveSecurityScopedAccessHandler()
        let bookmarkStore = UserDefaultsBookmarkStore()
        let sessionStore = UserDefaultsSessionStore()
        let workspaceManager = LiveWorkspaceManager(
            bookmarkStore: bookmarkStore,
            securityScopedAccess: securityScopedAccess,
            workspaceEnumerator: LiveWorkspaceEnumerator()
        )
        let documentManager = LiveDocumentManager(securityScopedAccess: securityScopedAccess)
        let errorReporter = StubErrorReporter(logger: logger)

        return AppContainer(
            logger: logger,
            bookmarkStore: bookmarkStore,
            sessionStore: sessionStore,
            workspaceManager: workspaceManager,
            documentManager: documentManager,
            errorReporter: errorReporter,
            folderPickerBridge: LiveFolderPickerBridge(),
            lifecycleObserver: LifecycleObserver()
        )
    }

    static func preview(
        launchState: RootLaunchState,
        accessState: WorkspaceAccessState? = nil,
        snapshot: WorkspaceSnapshot? = nil,
        document: OpenDocument? = nil,
        path: [AppRoute] = []
    ) -> AppContainer {
        let logger = DebugLogger()
        let bookmarkStore = StubBookmarkStore()
        let sessionStore = StubSessionStore()
        let forcedRestoreResult: WorkspaceRestoreResult? = switch launchState {
        case .noWorkspaceSelected:
            .noWorkspaceSelected
        case .restoringWorkspace:
            nil
        case .workspaceReady:
            .ready(snapshot ?? PreviewSampleData.nestedWorkspace)
        case .workspaceAccessInvalid:
            .accessInvalid(
                accessState ?? .invalid(
                    displayName: PreviewSampleData.nestedWorkspace.displayName,
                    error: PreviewSampleData.invalidWorkspaceError
                )
            )
        case let .failed(error):
            .failed(error)
        }

        let workspaceManager = StubWorkspaceManager(
            bookmarkStore: bookmarkStore,
            readySnapshot: snapshot ?? PreviewSampleData.nestedWorkspace,
            forcedRestoreResult: forcedRestoreResult
        )
        let documentManager = StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL)
        let errorReporter = StubErrorReporter(logger: logger)

        let container = AppContainer(
            logger: logger,
            bookmarkStore: bookmarkStore,
            sessionStore: sessionStore,
            workspaceManager: workspaceManager,
            documentManager: documentManager,
            errorReporter: errorReporter,
            folderPickerBridge: StubFolderPickerBridge(),
            lifecycleObserver: LifecycleObserver()
        )

        container.session.launchState = launchState
        container.session.workspaceSnapshot = snapshot
        container.session.openDocument = document
        container.session.path = path
        container.session.lastError = {
            if case let .failed(error) = launchState {
                return error
            }

            return accessState?.invalidationError
        }()

        if let accessState {
            container.session.workspaceAccessState = accessState
        } else {
            switch launchState {
            case .noWorkspaceSelected, .restoringWorkspace, .failed:
                container.session.workspaceAccessState = .noneSelected
            case .workspaceReady:
                let workspaceName = snapshot?.displayName ?? PreviewSampleData.nestedWorkspace.displayName
                container.session.workspaceAccessState = .ready(displayName: workspaceName)
            case .workspaceAccessInvalid:
                container.session.workspaceAccessState = .invalid(
                    displayName: PreviewSampleData.nestedWorkspace.displayName,
                    error: PreviewSampleData.invalidWorkspaceError
                )
            }
        }

        return container
    }
}
