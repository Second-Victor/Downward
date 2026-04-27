import XCTest
@testable import Downward

final class MarkdownWorkspaceAppTrustedOpenAndRecentTests: MarkdownWorkspaceAppTestCase {
    @MainActor
    func testSearchResultOpensCorrectEditorDocument() async throws {
        let container = AppContainer.preview(
            launchState: .workspaceReady,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            snapshot: PreviewSampleData.nestedWorkspace
        )
        let workspaceViewModel = container.workspaceViewModel
        let editorViewModel = container.editorViewModel

        workspaceViewModel.searchQuery = "read"
        let result = try XCTUnwrap(workspaceViewModel.searchResults.first)

        container.session.path = [.trustedEditor(result.url, result.relativePath)]
        editorViewModel.handleAppear(for: result.url)

        try await waitUntil {
            container.session.openDocument?.url == result.url
        }

        XCTAssertEqual(container.session.openDocument?.displayName, result.displayName)
        XCTAssertEqual(container.session.openDocument?.relativePath, result.relativePath)
        XCTAssertEqual(container.session.path, [.trustedEditor(result.url, result.relativePath)])
        XCTAssertNil(container.session.editorLoadError)
    }

    @MainActor
    func testBrowserRootFileOpenUsesTrustedRelativePathIdentity() async throws {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        let documentManager = RelativePathOnlyDocumentManager(
            documentsByRelativePath: [
                PreviewSampleData.cleanDocument.relativePath: PreviewSampleData.cleanDocument,
            ]
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: documentManager,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: RecentFilesStore(initialItems: [])
        )
        let editorViewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            autosaveDelay: .milliseconds(20)
        )

        workspaceViewModel.openDocument(
            relativePath: PreviewSampleData.cleanDocument.relativePath,
            preferredURL: PreviewSampleData.cleanDocument.url
        )
        let routedURL = try XCTUnwrap(session.path.last?.editorURL)
        editorViewModel.handleAppear(for: routedURL)

        try await waitUntil {
            session.openDocument?.relativePath == PreviewSampleData.cleanDocument.relativePath
        }

        let openedRelativePaths = await documentManager.recordedOpenedRelativePaths()
        let attemptedURLBasedOpenURLs = await documentManager.recordedURLBasedOpenAttempts()

        XCTAssertEqual(session.openDocument?.displayName, PreviewSampleData.cleanDocument.displayName)
        XCTAssertEqual(openedRelativePaths, [PreviewSampleData.cleanDocument.relativePath])
        XCTAssertTrue(attemptedURLBasedOpenURLs.isEmpty)
        XCTAssertNil(session.editorLoadError)
    }

    @MainActor
    func testBrowserNestedFileOpenUsesTrustedRelativePathIdentity() async throws {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        let nestedDocument = makePreviewReadmeDocument()
        let documentManager = RelativePathOnlyDocumentManager(
            documentsByRelativePath: [
                nestedDocument.relativePath: nestedDocument,
            ]
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: documentManager,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: RecentFilesStore(initialItems: [])
        )
        let editorViewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            autosaveDelay: .milliseconds(20)
        )

        workspaceViewModel.openDocument(
            relativePath: nestedDocument.relativePath,
            preferredURL: nestedDocument.url
        )
        let routedURL = try XCTUnwrap(session.path.last?.editorURL)
        editorViewModel.handleAppear(for: routedURL)

        try await waitUntil {
            session.openDocument?.relativePath == nestedDocument.relativePath
        }

        let openedRelativePaths = await documentManager.recordedOpenedRelativePaths()
        let attemptedURLBasedOpenURLs = await documentManager.recordedURLBasedOpenAttempts()

        XCTAssertEqual(session.openDocument?.displayName, nestedDocument.displayName)
        XCTAssertEqual(openedRelativePaths, [nestedDocument.relativePath])
        XCTAssertTrue(attemptedURLBasedOpenURLs.isEmpty)
        XCTAssertNil(session.editorLoadError)
    }

    @MainActor
    func testBrowserJSONFileOpenLoadsEditorDocumentWithoutThemeImport() async throws {
        let workspaceURL = try makeTemporaryWorkspace(named: "JSONBrowserWorkspace")
        defer { removeItemIfPresent(at: workspaceURL) }
        let jsonText = #"{"kind":"ordinary workspace JSON"}"#
        let jsonURL = try createFile(named: "Theme.json", contents: jsonText, in: workspaceURL)
        let snapshot = WorkspaceSnapshot(
            rootURL: workspaceURL,
            displayName: "JSON Browser Workspace",
            rootNodes: [
                .file(
                    .init(
                        url: jsonURL,
                        displayName: "Theme.json",
                        subtitle: "Root document"
                    )
                ),
            ],
            lastUpdated: PreviewSampleData.previewDate
        )
        let document = Self.makeOpenDocument(
            url: jsonURL,
            workspaceRootURL: workspaceURL,
            relativePath: "Theme.json",
            text: jsonText
        )
        let existingTheme = Self.makeTheme(name: "Existing Theme")
        let themeStore = ThemeStore(fileURL: try makeTemporaryThemeURL())
        await themeStore.waitForInitialLoad()
        let didAddExistingTheme = await themeStore.add(existingTheme)
        XCTAssertTrue(didAddExistingTheme)
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: snapshot.displayName)
        session.workspaceSnapshot = snapshot
        let documentManager = RelativePathOnlyDocumentManager(
            documentsByRelativePath: [document.relativePath: document]
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: snapshot
            ),
            documentManager: documentManager,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: RecentFilesStore(initialItems: [])
        )
        let editorViewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            themeStore: themeStore,
            autosaveDelay: .milliseconds(20)
        )

        workspaceViewModel.openDocument(relativePath: "Theme.json", preferredURL: jsonURL)
        let routedURL = try XCTUnwrap(session.path.last?.editorURL)
        editorViewModel.handleAppear(for: routedURL)

        try await waitUntil {
            session.openDocument?.relativePath == "Theme.json"
        }

        let openedRelativePaths = await documentManager.recordedOpenedRelativePaths()
        let attemptedURLBasedOpenURLs = await documentManager.recordedURLBasedOpenAttempts()

        XCTAssertEqual(session.openDocument, document)
        XCTAssertEqual(session.path, [.trustedEditor(jsonURL, "Theme.json")])
        XCTAssertEqual(openedRelativePaths, ["Theme.json"])
        XCTAssertTrue(attemptedURLBasedOpenURLs.isEmpty)
        XCTAssertEqual(themeStore.themes, [existingTheme])
        XCTAssertNil(themeStore.lastError)
        XCTAssertNil(session.editorLoadError)
    }

    @MainActor
    func testSearchResultOpenUsesTrustedRelativePathIdentity() async throws {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        let nestedDocument = makePreviewReadmeDocument()
        let documentManager = RelativePathOnlyDocumentManager(
            documentsByRelativePath: [
                nestedDocument.relativePath: nestedDocument,
            ]
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: documentManager,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: RecentFilesStore(initialItems: [])
        )
        let editorViewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            autosaveDelay: .milliseconds(20)
        )

        workspaceViewModel.searchQuery = "read"
        let result = try XCTUnwrap(workspaceViewModel.searchResults.first)

        workspaceViewModel.openSearchResult(result)
        let routedURL = try XCTUnwrap(session.path.last?.editorURL)
        editorViewModel.handleAppear(for: routedURL)

        try await waitUntil {
            session.openDocument?.relativePath == result.relativePath
        }

        let openedRelativePaths = await documentManager.recordedOpenedRelativePaths()
        let attemptedURLBasedOpenURLs = await documentManager.recordedURLBasedOpenAttempts()

        XCTAssertEqual(session.openDocument?.displayName, result.displayName)
        XCTAssertEqual(openedRelativePaths, [result.relativePath])
        XCTAssertTrue(attemptedURLBasedOpenURLs.isEmpty)
        XCTAssertNil(session.editorLoadError)
    }

    @MainActor
    func testTrustedRelativeBrowserOpenDoesNotBecomeNoOpBeforeDocumentLoad() {
        let container = AppContainer.preview(
            launchState: .workspaceReady,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            snapshot: PreviewSampleData.nestedWorkspace
        )

        container.workspaceViewModel.openDocument(
            relativePath: PreviewSampleData.cleanDocument.relativePath,
            preferredURL: PreviewSampleData.cleanDocument.url
        )

        XCTAssertEqual(
            container.session.path,
            [.trustedEditor(
                PreviewSampleData.cleanDocument.url,
                PreviewSampleData.cleanDocument.relativePath
            )]
        )
        XCTAssertEqual(
            container.session.visibleEditorRelativePath,
            PreviewSampleData.cleanDocument.relativePath
        )
    }

    @MainActor
    func testTrustedCompactRouteShowsOpenedDocumentWhenResolvedURLDiffersFromRouteURL() async throws {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        let preferredRouteURL = URL(
            filePath: "\(PreviewSampleData.workspaceRootURL.path)/References/../Inbox.md"
        )
        XCTAssertNotEqual(preferredRouteURL, PreviewSampleData.cleanDocument.url)

        let documentManager = RelativePathOnlyDocumentManager(
            documentsByRelativePath: [
                PreviewSampleData.cleanDocument.relativePath: PreviewSampleData.cleanDocument,
            ]
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: documentManager,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: RecentFilesStore(initialItems: [])
        )
        let editorViewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            autosaveDelay: .milliseconds(20)
        )

        workspaceViewModel.openDocument(
            relativePath: PreviewSampleData.cleanDocument.relativePath,
            preferredURL: preferredRouteURL
        )

        let routedURL = try XCTUnwrap(session.path.last?.editorURL)
        XCTAssertEqual(routedURL, preferredRouteURL)

        editorViewModel.handleAppear(for: routedURL)

        try await waitUntil {
            editorViewModel.currentRouteDocument?.relativePath == PreviewSampleData.cleanDocument.relativePath
        }

        XCTAssertEqual(session.openDocument?.url, PreviewSampleData.cleanDocument.url)
        XCTAssertEqual(
            editorViewModel.currentRouteDocument?.relativePath,
            PreviewSampleData.cleanDocument.relativePath
        )
        XCTAssertNil(session.editorLoadError)
    }

    @MainActor
    func testRegularTreeOpenUsesTrustedRelativeIdentity() async throws {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        let document = makePreviewReadmeDocument()
        let preferredRouteURL = URL(
            filePath: "\(PreviewSampleData.workspaceRootURL.path)/References/../References/README.md"
        )
        XCTAssertNotEqual(preferredRouteURL, document.url)

        let documentManager = RelativePathOnlyDocumentManager(
            documentsByRelativePath: [
                document.relativePath: document,
            ]
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: documentManager,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: RecentFilesStore(initialItems: [])
        )
        let editorViewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            autosaveDelay: .milliseconds(20)
        )

        coordinator.updateNavigationLayout(WorkspaceNavigationLayout.regular)
        workspaceViewModel.openDocument(
            relativePath: document.relativePath,
            preferredURL: preferredRouteURL
        )

        let detailURL = try XCTUnwrap(session.regularWorkspaceDetail.editorURL)
        XCTAssertEqual(detailURL, preferredRouteURL)

        editorViewModel.handleAppear(for: detailURL)

        try await waitUntil {
            session.openDocument?.relativePath == document.relativePath
        }

        let openedRelativePaths = await documentManager.recordedOpenedRelativePaths()
        let attemptedURLBasedOpenURLs = await documentManager.recordedURLBasedOpenAttempts()

        XCTAssertEqual(session.openDocument?.displayName, document.displayName)
        XCTAssertEqual(openedRelativePaths, [document.relativePath])
        XCTAssertTrue(attemptedURLBasedOpenURLs.isEmpty)
        XCTAssertNil(session.editorLoadError)
    }

    @MainActor
    func testRegularPendingEditorLoadUsesRelativeIdentityWhenResolvedDetailURLDiffersFromPreferredRouteURL() async throws {
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace
        let document = makePreviewReadmeDocument()
        let preferredRouteURL = URL(
            filePath: "\(PreviewSampleData.workspaceRootURL.path)/References/../References/README.md"
        )
        let resolvedDetailURL = document.url
        XCTAssertNotEqual(preferredRouteURL, resolvedDetailURL)

        let documentManager = RelativePathOnlyDocumentManager(
            documentsByRelativePath: [
                document.relativePath: document,
            ]
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: PreviewSampleData.nestedWorkspace
            ),
            documentManager: documentManager,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        coordinator.updateNavigationLayout(WorkspaceNavigationLayout.regular)
        session.pendingEditorPresentation = .init(
            routeURL: preferredRouteURL,
            relativePath: document.relativePath
        )
        session.regularDetailSelection = .editor(document.relativePath)

        let result = await coordinator.loadDocument(at: resolvedDetailURL)

        guard case let .success(openedDocument) = result else {
            return XCTFail("Expected trusted relative-path open to succeed.")
        }

        let openedRelativePaths = await documentManager.recordedOpenedRelativePaths()
        let attemptedURLBasedOpenURLs = await documentManager.recordedURLBasedOpenAttempts()

        XCTAssertEqual(openedDocument.relativePath, document.relativePath)
        XCTAssertEqual(openedRelativePaths, [document.relativePath])
        XCTAssertTrue(attemptedURLBasedOpenURLs.isEmpty)
    }

    @MainActor
    func testWorkspaceViewModelProgrammaticFileOpenUsesOnlyEditorRoute() {
        let container = AppContainer.preview(
            launchState: .workspaceReady,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            snapshot: PreviewSampleData.nestedWorkspace
        )
        let workspaceViewModel = container.workspaceViewModel

        workspaceViewModel.openDocument(
            relativePath: PreviewSampleData.cleanDocument.relativePath,
            preferredURL: PreviewSampleData.cleanDocument.url
        )

        XCTAssertEqual(
            container.session.path,
            [.trustedEditor(
                PreviewSampleData.cleanDocument.url,
                PreviewSampleData.cleanDocument.relativePath
            )]
        )
    }

    @MainActor
    func testRegularWorkspaceDetailBecomesEditorWhenTreeSelectionOpensFile() {
        let container = AppContainer.preview(
            launchState: .workspaceReady,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            snapshot: PreviewSampleData.nestedWorkspace
        )
        container.coordinator.updateNavigationLayout(.regular)

        container.workspaceViewModel.openDocument(PreviewSampleData.cleanDocument.url)

        XCTAssertEqual(
            container.session.regularWorkspaceDetail,
            .editor(PreviewSampleData.cleanDocument.url)
        )
    }

    @MainActor
    func testRecentFileOpenedFromSecondarySurfaceUsesTrustedRelativePathIdentity() async throws {
        let workspaceURL = try makeTemporaryWorkspace(named: "RecentFileWorkspace")
        defer { removeItemIfPresent(at: workspaceURL) }
        let canonicalFileURL = try createFile(
            named: "Inbox.md",
            contents: PreviewSampleData.cleanDocument.text,
            in: workspaceURL
        )
        let snapshot = WorkspaceSnapshot(
            rootURL: workspaceURL,
            displayName: "Recent File Workspace",
            rootNodes: [
                .file(
                    .init(
                        url: canonicalFileURL,
                        displayName: "Inbox.md",
                        subtitle: "Root document"
                    )
                ),
            ],
            lastUpdated: PreviewSampleData.previewDate
        )
        let document = OpenDocument(
            url: canonicalFileURL,
            workspaceRootURL: workspaceURL,
            relativePath: "Inbox.md",
            displayName: "Inbox.md",
            text: PreviewSampleData.cleanDocument.text,
            loadedVersion: PreviewSampleData.cleanDocument.loadedVersion,
            isDirty: false,
            saveState: .idle,
            conflictState: .none
        )
        let recentItem = RecentFileItem(
            workspaceID: snapshot.workspaceID,
            workspaceRootPath: workspaceURL.path,
            relativePath: document.relativePath,
            displayName: document.displayName,
            lastOpenedAt: PreviewSampleData.previewDate
        )
        let recentFilesStore = RecentFilesStore(initialItems: [recentItem])
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: snapshot.displayName)
        session.workspaceSnapshot = snapshot
        let documentManager = RelativePathOnlyDocumentManager(
            documentsByRelativePath: [document.relativePath: document]
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: snapshot
            ),
            documentManager: documentManager,
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: recentFilesStore
        )
        let editorViewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            autosaveDelay: .milliseconds(20)
        )
        let item = try XCTUnwrap(workspaceViewModel.recentFiles.first)

        workspaceViewModel.presentRecentFiles()
        XCTAssertTrue(workspaceViewModel.isShowingRecentFiles)

        workspaceViewModel.openRecentFile(item)
        XCTAssertFalse(workspaceViewModel.isShowingRecentFiles)
        XCTAssertEqual(session.path, [.trustedEditor(canonicalFileURL, document.relativePath)])

        let resolvedURL = try XCTUnwrap(session.path.last?.editorURL)
        editorViewModel.handleAppear(for: resolvedURL)

        try await waitUntil {
            session.openDocument?.relativePath == document.relativePath
        }

        let openedRelativePaths = await documentManager.recordedOpenedRelativePaths()
        let attemptedURLBasedOpenURLs = await documentManager.recordedURLBasedOpenAttempts()

        XCTAssertEqual(session.openDocument?.url, canonicalFileURL)
        XCTAssertEqual(session.openDocument?.relativePath, document.relativePath)
        XCTAssertEqual(session.path, [.trustedEditor(canonicalFileURL, document.relativePath)])
        XCTAssertEqual(openedRelativePaths, [document.relativePath])
        XCTAssertTrue(attemptedURLBasedOpenURLs.isEmpty)
        XCTAssertNil(session.editorLoadError)
    }

    @MainActor
    func testRecentJSONFileOpenLoadsEditorDocumentWithoutThemeImport() async throws {
        let workspaceURL = try makeTemporaryWorkspace(named: "JSONRecentWorkspace")
        defer { removeItemIfPresent(at: workspaceURL) }
        let jsonText = #"{"palette":["text","background"]}"#
        let jsonURL = try createFile(named: "palette.json", contents: jsonText, in: workspaceURL)
        let snapshot = WorkspaceSnapshot(
            rootURL: workspaceURL,
            displayName: "JSON Recent Workspace",
            rootNodes: [
                .file(
                    .init(
                        url: jsonURL,
                        displayName: "palette.json",
                        subtitle: "Root document"
                    )
                ),
            ],
            lastUpdated: PreviewSampleData.previewDate
        )
        let document = Self.makeOpenDocument(
            url: jsonURL,
            workspaceRootURL: workspaceURL,
            relativePath: "palette.json",
            text: jsonText
        )
        let recentFilesStore = RecentFilesStore(
            initialItems: [
                RecentFileItem(
                    workspaceID: snapshot.workspaceID,
                    workspaceRootPath: workspaceURL.path,
                    relativePath: document.relativePath,
                    displayName: document.displayName,
                    lastOpenedAt: PreviewSampleData.previewDate
                ),
            ]
        )
        let existingTheme = Self.makeTheme(name: "Existing Theme")
        let themeStore = ThemeStore(fileURL: try makeTemporaryThemeURL())
        await themeStore.waitForInitialLoad()
        let didAddExistingTheme = await themeStore.add(existingTheme)
        XCTAssertTrue(didAddExistingTheme)
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: snapshot.displayName)
        session.workspaceSnapshot = snapshot
        let documentManager = RelativePathOnlyDocumentManager(
            documentsByRelativePath: [document.relativePath: document]
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: snapshot
            ),
            documentManager: documentManager,
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: recentFilesStore
        )
        let editorViewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            themeStore: themeStore,
            autosaveDelay: .milliseconds(20)
        )
        let item = try XCTUnwrap(workspaceViewModel.recentFiles.first)

        workspaceViewModel.openRecentFile(item)
        let routedURL = try XCTUnwrap(session.path.last?.editorURL)
        editorViewModel.handleAppear(for: routedURL)

        try await waitUntil {
            session.openDocument?.relativePath == "palette.json"
        }

        let openedRelativePaths = await documentManager.recordedOpenedRelativePaths()
        let attemptedURLBasedOpenURLs = await documentManager.recordedURLBasedOpenAttempts()

        XCTAssertEqual(session.openDocument, document)
        XCTAssertEqual(openedRelativePaths, ["palette.json"])
        XCTAssertTrue(attemptedURLBasedOpenURLs.isEmpty)
        XCTAssertEqual(themeStore.themes, [existingTheme])
        XCTAssertNil(themeStore.lastError)
        XCTAssertNil(session.editorLoadError)
    }

    @MainActor
    func testStaleRecentFileOpenRemovesEntryAndShowsRecentSpecificError() async throws {
        let workspaceURL = try makeTemporaryWorkspace(named: "StaleRecentWorkspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let snapshot = WorkspaceSnapshot(
            rootURL: workspaceURL,
            displayName: "Stale Recent Workspace",
            rootNodes: [],
            lastUpdated: PreviewSampleData.previewDate
        )
        let staleItem = RecentFileItem(
            workspaceID: snapshot.workspaceID,
            workspaceRootPath: workspaceURL.path,
            relativePath: "Missing.md",
            displayName: "Missing.md",
            lastOpenedAt: PreviewSampleData.previewDate
        )
        let otherWorkspaceItem = RecentFileItem(
            workspaceRootPath: "/preview/OtherWorkspace",
            relativePath: "Elsewhere.md",
            displayName: "Elsewhere.md",
            lastOpenedAt: PreviewSampleData.previewDate.addingTimeInterval(-60)
        )
        let recentFilesStore = RecentFilesStore(initialItems: [staleItem, otherWorkspaceItem])
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: snapshot.displayName)
        session.workspaceSnapshot = snapshot
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: snapshot
            ),
            documentManager: RelativePathOnlyDocumentManager(documentsByRelativePath: [:]),
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: recentFilesStore
        )
        let editorViewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            autosaveDelay: .milliseconds(20)
        )

        let item = try XCTUnwrap(workspaceViewModel.recentFiles.first)
        workspaceViewModel.openRecentFile(item)

        let routedURL = try XCTUnwrap(session.path.last?.editorURL)
        editorViewModel.handleAppear(for: routedURL)

        try await waitUntil {
            session.editorLoadError?.title == "Recent File Unavailable"
        }

        XCTAssertEqual(recentFilesStore.items.map(\.displayName), ["Elsewhere.md"])
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.pendingEditorPresentation)
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.editorLoadError?.title, "Recent File Unavailable")
        XCTAssertEqual(
            session.editorLoadError?.recoverySuggestion,
            "It was removed from Recent Files. Choose another file from the browser."
        )
        XCTAssertEqual(session.workspaceAlertError?.title, "Recent File Unavailable")
    }

    @MainActor
    func testStaleRecentJSONFileOpenKeepsRecentMissingFileHandling() async throws {
        let workspaceURL = try makeTemporaryWorkspace(named: "StaleRecentJSONWorkspace")
        defer { removeItemIfPresent(at: workspaceURL) }
        let snapshot = WorkspaceSnapshot(
            rootURL: workspaceURL,
            displayName: "Stale Recent JSON Workspace",
            rootNodes: [],
            lastUpdated: PreviewSampleData.previewDate
        )
        let staleItem = RecentFileItem(
            workspaceID: snapshot.workspaceID,
            workspaceRootPath: workspaceURL.path,
            relativePath: "Missing.json",
            displayName: "Missing.json",
            lastOpenedAt: PreviewSampleData.previewDate
        )
        let recentFilesStore = RecentFilesStore(initialItems: [staleItem])
        let existingTheme = Self.makeTheme(name: "Existing Theme")
        let themeStore = ThemeStore(fileURL: try makeTemporaryThemeURL())
        await themeStore.waitForInitialLoad()
        let didAddExistingTheme = await themeStore.add(existingTheme)
        XCTAssertTrue(didAddExistingTheme)
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: snapshot.displayName)
        session.workspaceSnapshot = snapshot
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: snapshot
            ),
            documentManager: RelativePathOnlyDocumentManager(documentsByRelativePath: [:]),
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: recentFilesStore
        )
        let editorViewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            themeStore: themeStore,
            autosaveDelay: .milliseconds(20)
        )
        let item = try XCTUnwrap(workspaceViewModel.recentFiles.first)

        workspaceViewModel.openRecentFile(item)
        let routedURL = try XCTUnwrap(session.path.last?.editorURL)
        editorViewModel.handleAppear(for: routedURL)

        try await waitUntil {
            session.editorLoadError?.title == "Recent File Unavailable"
        }

        XCTAssertTrue(recentFilesStore.items.isEmpty)
        XCTAssertEqual(session.path, [])
        XCTAssertNil(session.openDocument)
        XCTAssertEqual(session.editorLoadError?.title, "Recent File Unavailable")
        XCTAssertEqual(session.workspaceAlertError?.title, "Recent File Unavailable")
        XCTAssertEqual(themeStore.themes, [existingTheme])
        XCTAssertNil(themeStore.lastError)
    }

    @MainActor
    func testRemovingRecentFileFromSheetOnlyRemovesCurrentWorkspaceEntry() {
        let snapshot = PreviewSampleData.nestedWorkspace
        let currentWorkspaceItem = RecentFileItem(
            workspaceID: snapshot.workspaceID,
            workspaceRootPath: snapshot.rootURL.path,
            relativePath: "References/README.md",
            displayName: "README.md",
            lastOpenedAt: PreviewSampleData.previewDate
        )
        let otherWorkspaceItem = RecentFileItem(
            workspaceRootPath: "/preview/OtherWorkspace",
            relativePath: "Elsewhere.md",
            displayName: "Elsewhere.md",
            lastOpenedAt: PreviewSampleData.previewDate.addingTimeInterval(-60)
        )
        let recentFilesStore = RecentFilesStore(initialItems: [currentWorkspaceItem, otherWorkspaceItem])
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceAccessState = .ready(displayName: snapshot.displayName)
        session.workspaceSnapshot = snapshot
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: AppCoordinator(
                session: session,
                workspaceManager: StubWorkspaceManager(
                    bookmarkStore: StubBookmarkStore(),
                    readySnapshot: snapshot
                ),
                documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
                recentFilesStore: recentFilesStore,
                errorReporter: DefaultErrorReporter(logger: DebugLogger()),
                folderPickerBridge: StubFolderPickerBridge(),
                logger: DebugLogger()
            ),
            recentFilesStore: recentFilesStore
        )

        workspaceViewModel.removeRecentFiles(at: IndexSet(integer: 0))

        XCTAssertTrue(workspaceViewModel.recentFiles.isEmpty)
        XCTAssertEqual(recentFilesStore.items.map(\.displayName), ["Elsewhere.md"])
    }

    @MainActor
    func testRestoreMovedWorkspacePreservesLegacyRecentFilesThroughStableWorkspaceIdentity() async {
        let workspaceID = "workspace-stable-id"
        let oldWorkspaceURL = URL(filePath: "/preview/OriginalWorkspace")
        let movedWorkspaceURL = URL(filePath: "/preview/MovedWorkspace")
        let bookmarkStore = StubBookmarkStore(
            initialBookmark: StoredWorkspaceBookmark(
                workspaceName: "Moved Workspace",
                lastKnownPath: oldWorkspaceURL.path,
                bookmarkData: Data("workspace-bookmark".utf8),
                workspaceID: workspaceID
            )
        )
        let session = AppSession()
        let recentFilesStore = RecentFilesStore(
            initialItems: [
                RecentFileItem(
                    workspaceRootPath: oldWorkspaceURL.path,
                    relativePath: PreviewSampleData.cleanDocument.relativePath,
                    displayName: PreviewSampleData.cleanDocument.displayName,
                    lastOpenedAt: PreviewSampleData.previewDate
                ),
            ]
        )
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: LiveWorkspaceManager(
                bookmarkStore: bookmarkStore,
                securityScopedAccess: RestoringSmokeSecurityScopedAccessHandler(
                    resolvedBookmarks: [
                        Data("workspace-bookmark".utf8): ResolvedSecurityScopedURL(
                            url: movedWorkspaceURL,
                            displayName: "Moved Workspace",
                            isStale: false
                        )
                    ]
                ),
                workspaceEnumerator: StubWorkspaceEnumerator(snapshot: PreviewSampleData.nestedWorkspace)
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )
        let workspaceViewModel = WorkspaceViewModel(
            session: session,
            coordinator: coordinator,
            recentFilesStore: recentFilesStore
        )

        await coordinator.bootstrapIfNeeded()
        let recentFiles = workspaceViewModel.recentFiles

        XCTAssertEqual(session.workspaceSnapshot?.rootURL, movedWorkspaceURL)
        XCTAssertEqual(session.workspaceSnapshot?.workspaceID, workspaceID)
        XCTAssertEqual(recentFiles.map(\.displayName), ["Inbox.md"])
        XCTAssertEqual(recentFilesStore.items.first?.workspaceID, workspaceID)
        XCTAssertEqual(recentFilesStore.items.first?.workspaceRootPath, movedWorkspaceURL.path)
    }

    @MainActor
    func testRefreshWorkspacePrunesMissingRecentFiles() async {
        let staleRecentItem = RecentFileItem(
            workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
            relativePath: "Missing.md",
            displayName: "Missing.md",
            lastOpenedAt: PreviewSampleData.previewDate
        )
        let recentFilesStore = RecentFilesStore(
            initialItems: [
                staleRecentItem,
                RecentFileItem(
                    workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                    relativePath: PreviewSampleData.cleanDocument.relativePath,
                    displayName: PreviewSampleData.cleanDocument.displayName,
                    lastOpenedAt: PreviewSampleData.previewDate.addingTimeInterval(-10)
                ),
            ]
        )
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(refreshSnapshot: PreviewSampleData.nestedWorkspace),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.refreshWorkspace()

        XCTAssertEqual(recentFilesStore.items.map(\.displayName), ["Inbox.md"])
    }

    @MainActor
    func testRenameUpdatesRecentFileEntry() async {
        let renamedURL = PreviewSampleData.inboxDocumentURL.deletingLastPathComponent().appending(path: "Inbox Renamed.md")
        let recentFilesStore = RecentFilesStore(
            initialItems: [
                RecentFileItem(
                    workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                    relativePath: PreviewSampleData.cleanDocument.relativePath,
                    displayName: PreviewSampleData.cleanDocument.displayName,
                    lastOpenedAt: PreviewSampleData.previewDate
                ),
            ]
        )
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = PreviewSampleData.nestedWorkspace

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: makeWorkspaceSnapshotReplacingRootFile(
                    oldURL: PreviewSampleData.inboxDocumentURL,
                    with: .file(
                        .init(
                            url: renamedURL,
                            displayName: "Localized Inbox Renamed.md",
                            subtitle: "Root document"
                        )
                    )
                ),
                renameOutcome: .renamedFile(
                    oldURL: PreviewSampleData.inboxDocumentURL,
                    newURL: renamedURL,
                    displayName: "Localized Inbox Renamed.md",
                    relativePath: "Inbox Renamed.md"
                )
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.renameFile(at: PreviewSampleData.inboxDocumentURL, to: "Inbox Renamed")

        XCTAssertEqual(recentFilesStore.items.map(\.displayName), ["Localized Inbox Renamed.md"])
        XCTAssertEqual(recentFilesStore.items.first?.relativePath, "Inbox Renamed.md")
    }

    @MainActor
    func testDeleteRemovesRecentFileEntry() async {
        let recentFilesStore = RecentFilesStore(
            initialItems: [
                RecentFileItem(
                    workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                    relativePath: PreviewSampleData.cleanDocument.relativePath,
                    displayName: PreviewSampleData.cleanDocument.displayName,
                    lastOpenedAt: PreviewSampleData.previewDate
                ),
            ]
        )
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = makeWorkspaceSnapshotRemovingRootFile(url: PreviewSampleData.inboxDocumentURL)

        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: MutationTestingWorkspaceManager(
                refreshSnapshot: makeWorkspaceSnapshotRemovingRootFile(url: PreviewSampleData.inboxDocumentURL),
                deleteOutcome: .deletedFile(
                    url: PreviewSampleData.inboxDocumentURL,
                    displayName: PreviewSampleData.cleanDocument.displayName
                )
            ),
            documentManager: StubDocumentManager(sampleDocuments: PreviewSampleData.sampleDocumentsByURL),
            recentFilesStore: recentFilesStore,
            errorReporter: DefaultErrorReporter(logger: DebugLogger()),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: DebugLogger()
        )

        _ = await coordinator.deleteFile(at: PreviewSampleData.inboxDocumentURL)

        XCTAssertTrue(recentFilesStore.items.isEmpty)
    }

    private func makeTemporaryThemeURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "MarkdownWorkspaceJSONThemeStore-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appending(path: "themes.json")
    }

    @MainActor
    private static func makeOpenDocument(
        url: URL,
        workspaceRootURL: URL,
        relativePath: String,
        text: String
    ) -> OpenDocument {
        OpenDocument(
            url: url,
            workspaceRootURL: workspaceRootURL,
            relativePath: relativePath,
            displayName: url.lastPathComponent,
            text: text,
            loadedVersion: PreviewSampleData.cleanDocument.loadedVersion,
            isDirty: false,
            saveState: .idle,
            conflictState: .none
        )
    }

    private static func makeTheme(id: UUID = UUID(), name: String) -> CustomTheme {
        CustomTheme(
            id: id,
            name: name,
            background: HexColor(hex: "#1E1E1E"),
            text: HexColor(hex: "#D4D4D4"),
            tint: HexColor(hex: "#569CD6"),
            boldItalicMarker: HexColor(hex: "#72727F"),
            strikethrough: HexColor(hex: "#808080"),
            inlineCode: HexColor(hex: "#CE9178"),
            codeBackground: HexColor(hex: "#2D2D2D"),
            horizontalRule: HexColor(hex: "#404040"),
            checkboxUnchecked: HexColor(hex: "#F44747"),
            checkboxChecked: HexColor(hex: "#6A9955")
        )
    }
}
