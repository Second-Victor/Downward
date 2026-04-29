import Foundation

@MainActor
final class AppContainer {
    let logger: DebugLogger
    let bookmarkStore: any BookmarkStore
    let sessionStore: any SessionStore
    let recentFilesStore: RecentFilesStore
    let editorAppearanceStore: EditorAppearanceStore
    let themeStore: ThemeStore
    let workspaceManager: any WorkspaceManager
    let documentManager: any DocumentManager
    let errorReporter: any ErrorReporter
    let folderPickerBridge: any FolderPickerBridge
    let session: AppSession
    let coordinator: AppCoordinator
    let workspaceViewModel: WorkspaceViewModel
    let editorViewModel: EditorViewModel
    let rootViewModel: RootViewModel

    init(
        logger: DebugLogger,
        bookmarkStore: any BookmarkStore,
        sessionStore: any SessionStore = StubSessionStore(),
        recentFilesStore: RecentFilesStore,
        editorAppearanceStore: EditorAppearanceStore,
        themeStore: ThemeStore = ThemeStore(),
        workspaceManager: any WorkspaceManager,
        documentManager: any DocumentManager,
        errorReporter: any ErrorReporter,
        folderPickerBridge: any FolderPickerBridge
    ) {
        self.logger = logger
        self.bookmarkStore = bookmarkStore
        self.sessionStore = sessionStore
        self.recentFilesStore = recentFilesStore
        self.editorAppearanceStore = editorAppearanceStore
        self.themeStore = themeStore
        self.workspaceManager = workspaceManager
        self.documentManager = documentManager
        self.errorReporter = errorReporter
        self.folderPickerBridge = folderPickerBridge

        let session = AppSession()
        self.session = session

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: workspaceManager,
            documentManager: documentManager,
            editorAppearanceStore: editorAppearanceStore,
            sessionStore: sessionStore,
            recentFilesStore: recentFilesStore,
            errorReporter: errorReporter,
            folderPickerBridge: folderPickerBridge,
            logger: logger
        )
        self.coordinator = coordinator

        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: recentFilesStore
        )
        self.workspaceViewModel = workspaceViewModel

        let editorViewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: editorAppearanceStore,
            themeStore: themeStore
        )
        self.editorViewModel = editorViewModel

        self.rootViewModel = RootViewModel(
            session: session,
            coordinator: coordinator,
            workspaceViewModel: workspaceViewModel,
            editorViewModel: editorViewModel,
            editorAppearanceStore: editorAppearanceStore,
            themeStore: themeStore
        )
    }

    static func live() -> AppContainer {
        let logger = DebugLogger()
        let securityScopedAccess = LiveSecurityScopedAccessHandler()
        let bookmarkStore = UserDefaultsBookmarkStore()
        let sessionStore = UserDefaultsSessionStore()
        let recentFilesStore = RecentFilesStore()
        let editorAppearanceStore = EditorAppearanceStore()
        let themeStore = ThemeStore()
        let workspaceManager = LiveWorkspaceManager(
            bookmarkStore: bookmarkStore,
            securityScopedAccess: securityScopedAccess,
            workspaceEnumerator: LiveWorkspaceEnumerator(logger: logger)
        )
        let documentManager = LiveDocumentManager(
            securityScopedAccess: securityScopedAccess,
            logger: logger
        )
        let errorReporter = DefaultErrorReporter(logger: logger)

        return AppContainer(
            logger: logger,
            bookmarkStore: bookmarkStore,
            sessionStore: sessionStore,
            recentFilesStore: recentFilesStore,
            editorAppearanceStore: editorAppearanceStore,
            themeStore: themeStore,
            workspaceManager: workspaceManager,
            documentManager: documentManager,
            errorReporter: errorReporter,
            folderPickerBridge: LiveFolderPickerBridge()
        )
    }

    static func preview(
        launchState: RootLaunchState,
        accessState: WorkspaceAccessState? = nil,
        snapshot: WorkspaceSnapshot? = nil,
        document: OpenDocument? = nil,
        path: [AppRoute] = [],
        recentFiles: [RecentFileItem] = [],
        editorAppearancePreferences: EditorAppearancePreferences = .default
    ) -> AppContainer {
        let logger = DebugLogger()
        let bookmarkStore = StubBookmarkStore()
        let sessionStore = StubSessionStore()
        let recentFilesStore = RecentFilesStore(initialItems: recentFiles)
        let editorAppearanceStore = EditorAppearanceStore(initialPreferences: editorAppearancePreferences)
        let themeStore = ThemeStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "preview-themes-\(UUID().uuidString).json"))
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
        let errorReporter = DefaultErrorReporter(logger: logger)

        let container = AppContainer(
            logger: logger,
            bookmarkStore: bookmarkStore,
            sessionStore: sessionStore,
            recentFilesStore: recentFilesStore,
            editorAppearanceStore: editorAppearanceStore,
            themeStore: themeStore,
            workspaceManager: workspaceManager,
            documentManager: documentManager,
            errorReporter: errorReporter,
            folderPickerBridge: StubFolderPickerBridge()
        )

        container.session.launchState = launchState
        container.session.workspaceSnapshot = snapshot
        container.session.openDocument = document
        container.session.path = path
        container.session.hasBootstrapped = true

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
