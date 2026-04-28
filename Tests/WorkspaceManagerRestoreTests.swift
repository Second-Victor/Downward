import Foundation
import XCTest
@testable import Downward

final class WorkspaceManagerRestoreTests: XCTestCase {
    @MainActor
    func testRestoreRefreshesStaleBookmarkAndPersistsFreshBookmarkData() async throws {
        let workspaceID = "workspace-id"
        let bookmarkStore = StubBookmarkStore(
            initialBookmark: StoredWorkspaceBookmark(
                workspaceName: "Stale Workspace",
                lastKnownPath: "/tmp/Stale Workspace",
                bookmarkData: Data("stale-bookmark".utf8),
                workspaceID: workspaceID
            )
        )
        let securityScopedAccess = RecordingSecurityScopedAccessHandler(
            resolvedURL: URL(filePath: "/tmp/Renamed Workspace"),
            makeBookmarkData: Data("fresh-bookmark".utf8),
            staleBookmarkData: [Data("stale-bookmark".utf8)]
        )
        let manager = LiveWorkspaceManager(
            bookmarkStore: bookmarkStore,
            securityScopedAccess: securityScopedAccess,
            workspaceEnumerator: StubWorkspaceEnumerator(snapshot: PreviewSampleData.emptyWorkspace)
        )

        let restoreResult = await manager.restoreWorkspace()

        guard case let .ready(snapshot) = restoreResult else {
            return XCTFail("Expected ready result when a stale bookmark can be refreshed.")
        }

        let refreshedBookmark = try await bookmarkStore.loadBookmark()

        XCTAssertEqual(snapshot.rootURL, URL(filePath: "/tmp/Renamed Workspace"))
        XCTAssertEqual(snapshot.displayName, "Renamed Workspace")
        XCTAssertEqual(snapshot.workspaceID, workspaceID)
        XCTAssertEqual(refreshedBookmark?.workspaceName, "Renamed Workspace")
        XCTAssertEqual(refreshedBookmark?.lastKnownPath, "/tmp/Renamed Workspace")
        XCTAssertEqual(refreshedBookmark?.bookmarkData, Data("fresh-bookmark".utf8))
        XCTAssertEqual(refreshedBookmark?.workspaceID, workspaceID)
        XCTAssertEqual(securityScopedAccess.makeBookmarkCallCount, 1)
    }

    @MainActor
    func testRestoreReturnsReadyWhenBookmarkResolvesAndAccessSucceeds() async throws {
        let bookmarkStore = StubBookmarkStore(
            initialBookmark: StoredWorkspaceBookmark(
                workspaceName: "Ready Workspace",
                lastKnownPath: "/tmp/Ready Workspace",
                bookmarkData: Data("ready-bookmark".utf8)
            )
        )
        let manager = LiveWorkspaceManager(
            bookmarkStore: bookmarkStore,
            securityScopedAccess: FakeSecurityScopedAccessHandler(
                resolvedURL: URL(filePath: "/tmp/Ready Workspace"),
                isStale: false,
                shouldAllowAccess: true
            ),
            workspaceEnumerator: StubWorkspaceEnumerator(snapshot: PreviewSampleData.nestedWorkspace)
        )

        let restoreResult = await manager.restoreWorkspace()

        guard case let .ready(snapshot) = restoreResult else {
            return XCTFail("Expected ready result for a valid bookmark.")
        }

        let displayName = snapshot.displayName
        let rootURL = snapshot.rootURL
        let rootNodes = snapshot.rootNodes

        XCTAssertEqual(displayName, "Ready Workspace")
        XCTAssertEqual(rootURL, URL(filePath: "/tmp/Ready Workspace"))
        XCTAssertFalse(rootNodes.isEmpty)
    }

    @MainActor
    func testSelectingFirstWorkspacePersistsBookmarkOnlyAfterUsableSnapshotSucceeds() async throws {
        let workspaceURL = URL(filePath: "/tmp/Selected Workspace")
        let bookmarkStore = StubBookmarkStore()
        let manager = LiveWorkspaceManager(
            bookmarkStore: bookmarkStore,
            securityScopedAccess: FakeSecurityScopedAccessHandler(
                resolvedURL: workspaceURL,
                isStale: false,
                shouldAllowAccess: true
            ),
            workspaceEnumerator: StubWorkspaceEnumerator(snapshot: PreviewSampleData.emptyWorkspace)
        )

        let selectionResult = await manager.selectWorkspace(at: workspaceURL)
        let persistedBookmark = try await bookmarkStore.loadBookmark()

        guard case let .ready(snapshot) = selectionResult else {
            return XCTFail("Expected workspace selection to succeed.")
        }

        XCTAssertEqual(snapshot.rootURL, workspaceURL)
        XCTAssertEqual(snapshot.displayName, "Selected Workspace")
        XCTAssertEqual(persistedBookmark?.workspaceName, "Selected Workspace")
        XCTAssertEqual(persistedBookmark?.lastKnownPath, workspaceURL.path)
        XCTAssertEqual(persistedBookmark?.bookmarkData, Data(workspaceURL.path.utf8))
    }

    @MainActor
    func testSuccessfulSelectedWorkspaceBecomesNextRestoreTarget() async throws {
        let workspaceURL = URL(filePath: "/tmp/Restorable Workspace")
        let bookmarkStore = StubBookmarkStore()
        let selectingManager = LiveWorkspaceManager(
            bookmarkStore: bookmarkStore,
            securityScopedAccess: FakeSecurityScopedAccessHandler(
                resolvedURL: workspaceURL,
                isStale: false,
                shouldAllowAccess: true
            ),
            workspaceEnumerator: StubWorkspaceEnumerator(snapshot: PreviewSampleData.emptyWorkspace)
        )

        guard case .ready = await selectingManager.selectWorkspace(at: workspaceURL) else {
            return XCTFail("Expected initial workspace selection to succeed.")
        }

        let restoringManager = LiveWorkspaceManager(
            bookmarkStore: bookmarkStore,
            securityScopedAccess: FakeSecurityScopedAccessHandler(
                resolvedURL: workspaceURL,
                isStale: false,
                shouldAllowAccess: true
            ),
            workspaceEnumerator: StubWorkspaceEnumerator(snapshot: PreviewSampleData.nestedWorkspace)
        )

        let restoreResult = await restoringManager.restoreWorkspace()
        let loadedBookmark = try await bookmarkStore.loadBookmark()
        let persistedBookmark = try XCTUnwrap(loadedBookmark)

        guard case let .ready(snapshot) = restoreResult else {
            return XCTFail("Expected successful selection to become the restore target.")
        }

        XCTAssertEqual(snapshot.rootURL, workspaceURL)
        XCTAssertEqual(snapshot.displayName, "Restorable Workspace")
        XCTAssertEqual(snapshot.workspaceID, persistedBookmark.workspaceID)
    }

    @MainActor
    func testSelectingFirstWorkspaceWithFailingInitialSnapshotDoesNotPersistBrokenRestoreState() async throws {
        let workspaceURL = URL(filePath: "/tmp/Broken Workspace")
        let bookmarkStore = StubBookmarkStore()
        let manager = LiveWorkspaceManager(
            bookmarkStore: bookmarkStore,
            securityScopedAccess: FakeSecurityScopedAccessHandler(
                resolvedURL: workspaceURL,
                isStale: false,
                shouldAllowAccess: true
            ),
            workspaceEnumerator: ScriptedWorkspaceEnumerator(
                behaviors: [
                    .failure(
                        AppError.workspaceRestoreFailed(
                            details: "The selected folder could not be loaded."
                        )
                    )
                ]
            )
        )

        let selectionResult = await manager.selectWorkspace(at: workspaceURL)
        let persistedBookmark = try await bookmarkStore.loadBookmark()

        guard case let .failed(error) = selectionResult else {
            return XCTFail("Expected failed result when the first snapshot cannot be built.")
        }

        XCTAssertEqual(error.title, "Unable to Restore Workspace")
        XCTAssertNil(persistedBookmark)

        do {
            _ = try await manager.refreshCurrentWorkspace()
            XCTFail("Expected no persisted workspace after failed first selection.")
        } catch let error as AppError {
            guard case .missingWorkspaceSelection = error else {
                return XCTFail("Expected missing workspace selection after failed first selection.")
            }
        }
    }

    @MainActor
    func testRefreshUsesResolvedBookmarkURLInsteadOfLastKnownPathFallback() async throws {
        let bookmarkStore = StubBookmarkStore(
            initialBookmark: StoredWorkspaceBookmark(
                workspaceName: "Resolved Workspace",
                lastKnownPath: "/tmp/Outdated Workspace Path",
                bookmarkData: Data("resolved-bookmark".utf8)
            )
        )
        let manager = LiveWorkspaceManager(
            bookmarkStore: bookmarkStore,
            securityScopedAccess: FakeSecurityScopedAccessHandler(
                resolvedURL: URL(filePath: "/tmp/Resolved Workspace"),
                isStale: false,
                shouldAllowAccess: true
            ),
            workspaceEnumerator: StubWorkspaceEnumerator(snapshot: PreviewSampleData.nestedWorkspace)
        )

        let snapshot = try await manager.refreshCurrentWorkspace()

        XCTAssertEqual(snapshot.rootURL, URL(filePath: "/tmp/Resolved Workspace"))
        XCTAssertEqual(snapshot.displayName, "Resolved Workspace")
    }

    @MainActor
    func testReplacingWorkingWorkspaceWithFailingNewSelectionPreservesPreviousPersistedWorkspace() async throws {
        let oldWorkspaceURL = URL(filePath: "/tmp/Old Workspace")
        let newWorkspaceURL = URL(filePath: "/tmp/Broken Workspace")
        let oldBookmark = StoredWorkspaceBookmark(
            workspaceName: "Old Workspace",
            lastKnownPath: oldWorkspaceURL.path,
            bookmarkData: Data("old-bookmark".utf8)
        )
        let oldSnapshot = WorkspaceSnapshot(
            rootURL: oldWorkspaceURL,
            displayName: "Old Workspace",
            rootNodes: PreviewSampleData.emptyWorkspace.rootNodes,
            lastUpdated: PreviewSampleData.previewDate
        )
        let bookmarkStore = StubBookmarkStore(initialBookmark: oldBookmark)
        let manager = LiveWorkspaceManager(
            bookmarkStore: bookmarkStore,
            securityScopedAccess: RecordingSecurityScopedAccessHandler(
                resolvedBookmarks: [
                    Data("old-bookmark".utf8): ResolvedSecurityScopedURL(
                        url: oldWorkspaceURL,
                        displayName: "Old Workspace",
                        isStale: false
                    )
                ],
                makeBookmarkData: Data(newWorkspaceURL.path.utf8)
            ),
            workspaceEnumerator: ScriptedWorkspaceEnumerator(
                behaviors: [
                    .immediate(oldSnapshot),
                    .failure(
                        AppError.workspaceRestoreFailed(
                            details: "The selected folder could not be loaded."
                        )
                    )
                ]
            )
        )

        guard case .ready = await manager.restoreWorkspace() else {
            return XCTFail("Expected initial restore to establish the current workspace.")
        }

        let selectionResult = await manager.selectWorkspace(at: newWorkspaceURL)
        let persistedBookmark = try await bookmarkStore.loadBookmark()
        let refreshedSnapshot = try await manager.refreshCurrentWorkspace()

        guard case let .failed(error) = selectionResult else {
            return XCTFail("Expected replacement selection to fail.")
        }

        XCTAssertEqual(error.title, "Unable to Restore Workspace")
        XCTAssertEqual(persistedBookmark, oldBookmark)
        XCTAssertEqual(refreshedSnapshot.rootURL, oldWorkspaceURL)
        XCTAssertEqual(refreshedSnapshot.displayName, "Old Workspace")
    }

    @MainActor
    func testCancelledRefreshPropagatesCancellationIntoStructuredEnumeration() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }

        let enumerator = ScriptedWorkspaceEnumerator(
            behaviors: [
                .immediate(PreviewSampleData.nestedWorkspace),
                .delayedUntilCancellation(PreviewSampleData.emptyWorkspace),
            ]
        )
        let manager = LiveWorkspaceManager(
            bookmarkStore: StubBookmarkStore(),
            securityScopedAccess: FakeSecurityScopedAccessHandler(
                resolvedURL: workspaceURL,
                isStale: false,
                shouldAllowAccess: true
            ),
            workspaceEnumerator: enumerator
        )

        guard case .ready = await manager.selectWorkspace(at: workspaceURL) else {
            return XCTFail("Expected workspace selection to succeed before refresh cancellation test.")
        }

        let refreshTask = Task {
            try await manager.refreshCurrentWorkspace()
        }

        try await Task.sleep(for: .milliseconds(30))
        refreshTask.cancel()

        do {
            _ = try await refreshTask.value
            XCTFail("Expected cancelled refresh to throw CancellationError.")
        } catch is CancellationError {
            XCTAssertEqual(enumerator.cancelledEnumerationCount, 1)
            XCTAssertEqual(enumerator.completedEnumerationCount, 1)
        }
    }

    @MainActor
    func testRefreshStillSucceedsAfterEarlierRefreshWasCancelled() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }

        let refreshedSnapshot = WorkspaceSnapshot(
            rootURL: workspaceURL,
            displayName: workspaceURL.lastPathComponent,
            rootNodes: PreviewSampleData.nestedWorkspace.rootNodes,
            lastUpdated: PreviewSampleData.previewDate
        )
        let enumerator = ScriptedWorkspaceEnumerator(
            behaviors: [
                .immediate(PreviewSampleData.emptyWorkspace),
                .delayedUntilCancellation(PreviewSampleData.nestedWorkspace),
                .immediate(refreshedSnapshot),
            ]
        )
        let manager = LiveWorkspaceManager(
            bookmarkStore: StubBookmarkStore(),
            securityScopedAccess: FakeSecurityScopedAccessHandler(
                resolvedURL: workspaceURL,
                isStale: false,
                shouldAllowAccess: true
            ),
            workspaceEnumerator: enumerator
        )

        guard case .ready = await manager.selectWorkspace(at: workspaceURL) else {
            return XCTFail("Expected workspace selection to succeed before retry test.")
        }

        let cancelledRefreshTask = Task {
            try await manager.refreshCurrentWorkspace()
        }

        try await Task.sleep(for: .milliseconds(30))
        cancelledRefreshTask.cancel()
        do {
            _ = try await cancelledRefreshTask.value
            XCTFail("Expected cancelled refresh to throw CancellationError.")
        } catch is CancellationError {}

        let snapshot = try await manager.refreshCurrentWorkspace()

        XCTAssertEqual(snapshot.rootURL, refreshedSnapshot.rootURL)
        XCTAssertEqual(snapshot.displayName, refreshedSnapshot.displayName)
        XCTAssertEqual(snapshot.rootNodes, refreshedSnapshot.rootNodes)
        XCTAssertEqual(enumerator.cancelledEnumerationCount, 1)
        XCTAssertEqual(enumerator.completedEnumerationCount, 2)
    }

    @MainActor
    func testRestoreUsesRefreshedBookmarkAcrossRelaunchStyleFlow() async throws {
        let workspaceID = "workspace-id"
        let bookmarkStore = StubBookmarkStore(
            initialBookmark: StoredWorkspaceBookmark(
                workspaceName: "Original Workspace",
                lastKnownPath: "/tmp/Original Workspace",
                bookmarkData: Data("stale-bookmark".utf8),
                workspaceID: workspaceID
            )
        )
        let securityScopedAccess = RecordingSecurityScopedAccessHandler(
            resolvedBookmarks: [
                Data("stale-bookmark".utf8): ResolvedSecurityScopedURL(
                    url: URL(filePath: "/tmp/Renamed Workspace"),
                    displayName: "Renamed Workspace",
                    isStale: true
                ),
                Data("fresh-bookmark".utf8): ResolvedSecurityScopedURL(
                    url: URL(filePath: "/tmp/Renamed Workspace"),
                    displayName: "Renamed Workspace",
                    isStale: false
                ),
            ],
            makeBookmarkData: Data("fresh-bookmark".utf8)
        )
        let firstManager = LiveWorkspaceManager(
            bookmarkStore: bookmarkStore,
            securityScopedAccess: securityScopedAccess,
            workspaceEnumerator: StubWorkspaceEnumerator(snapshot: PreviewSampleData.emptyWorkspace)
        )

        let firstRestoreResult = await firstManager.restoreWorkspace()

        guard case .ready = firstRestoreResult else {
            return XCTFail("Expected first restore to refresh the stale bookmark.")
        }

        let relaunchedManager = LiveWorkspaceManager(
            bookmarkStore: bookmarkStore,
            securityScopedAccess: securityScopedAccess,
            workspaceEnumerator: StubWorkspaceEnumerator(snapshot: PreviewSampleData.emptyWorkspace)
        )

        let secondRestoreResult = await relaunchedManager.restoreWorkspace()

        guard case let .ready(snapshot) = secondRestoreResult else {
            return XCTFail("Expected second restore to reuse the refreshed bookmark.")
        }

        XCTAssertEqual(snapshot.rootURL, URL(filePath: "/tmp/Renamed Workspace"))
        XCTAssertEqual(snapshot.displayName, "Renamed Workspace")
        XCTAssertEqual(snapshot.workspaceID, workspaceID)
        XCTAssertEqual(securityScopedAccess.makeBookmarkCallCount, 1)
        XCTAssertEqual(securityScopedAccess.resolvedBookmarkData, [
            Data("stale-bookmark".utf8),
            Data("fresh-bookmark".utf8),
        ])
    }

    @MainActor
    func testCreateFileAddsMarkdownFileAndReturnsRefreshedSnapshot() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        let fileCoordinator = RecordingWorkspaceFileCoordinator()

        let manager = makeLiveWorkspaceManager(
            for: workspaceURL,
            fileCoordinator: fileCoordinator
        )
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.createFile(named: "Notes", in: nil)

        guard case let .createdFile(url, displayName) = mutationResult.outcome else {
            return XCTFail("Expected createdFile result.")
        }

        XCTAssertEqual(displayName, "Notes.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(mutationResult.snapshot.rootNodes.contains(where: { $0.displayName == "Notes.md" }))
        XCTAssertEqual(fileCoordinator.createdURLs, [url])
    }

    @MainActor
    func testCreateFileUsesUniqueNameWhenDuplicateExists() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        try Data("# Existing".utf8).write(to: workspaceURL.appending(path: "Notes.md"))
        let fileCoordinator = RecordingWorkspaceFileCoordinator()

        let manager = makeLiveWorkspaceManager(
            for: workspaceURL,
            fileCoordinator: fileCoordinator
        )
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.createFile(named: "Notes.md", in: nil)

        guard case let .createdFile(url, _) = mutationResult.outcome else {
            return XCTFail("Expected createdFile result.")
        }

        XCTAssertEqual(url.lastPathComponent, "Notes 2.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceURL.appending(path: "Notes 2.md").path))
        XCTAssertTrue(mutationResult.snapshot.rootNodes.contains(where: { $0.displayName == "Notes 2.md" }))
        XCTAssertEqual(fileCoordinator.createdURLs, [url])
    }

    @MainActor
    func testCreateMarkdownFileCanStartWithTitleFromCreatedFilename() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }

        let manager = makeLiveWorkspaceManager(for: workspaceURL)
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.createFile(
            named: "random.md",
            in: nil,
            initialContent: .markdownTitleFromFilename
        )

        guard case let .createdFile(url, _) = mutationResult.outcome else {
            return XCTFail("Expected createdFile result.")
        }

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# random\n\n")
    }

    @MainActor
    func testCreateMarkdownTitleUsesUniqueCreatedFilename() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        try Data("# Existing".utf8).write(to: workspaceURL.appending(path: "Notes.md"))

        let manager = makeLiveWorkspaceManager(for: workspaceURL)
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.createFile(
            named: "Notes.md",
            in: nil,
            initialContent: .markdownTitleFromFilename
        )

        guard case let .createdFile(url, _) = mutationResult.outcome else {
            return XCTFail("Expected createdFile result.")
        }

        XCTAssertEqual(url.lastPathComponent, "Notes 2.md")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# Notes 2\n\n")
    }

    @MainActor
    func testMarkdownTitleInitialContentLeavesNonMarkdownFilesEmpty() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }

        let manager = makeLiveWorkspaceManager(for: workspaceURL)
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.createFile(
            named: "App.swift",
            in: nil,
            initialContent: .markdownTitleFromFilename
        )

        guard case let .createdFile(url, _) = mutationResult.outcome else {
            return XCTFail("Expected createdFile result.")
        }

        XCTAssertEqual(try Data(contentsOf: url), Data())
    }

    @MainActor
    func testCreateFileAcceptsSupportedSourceExtension() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        let fileCoordinator = RecordingWorkspaceFileCoordinator()

        let manager = makeLiveWorkspaceManager(
            for: workspaceURL,
            fileCoordinator: fileCoordinator
        )
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.createFile(named: "App.swift", in: nil)

        guard case let .createdFile(url, displayName) = mutationResult.outcome else {
            return XCTFail("Expected createdFile result.")
        }

        XCTAssertEqual(displayName, "App.swift")
        XCTAssertEqual(url.lastPathComponent, "App.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(mutationResult.snapshot.rootNodes.contains(where: { $0.displayName == "App.swift" }))
        XCTAssertEqual(fileCoordinator.createdURLs, [url])
    }

    @MainActor
    func testCreateFileAcceptsWorkspaceRootAliasURL() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        let fileCoordinator = RecordingWorkspaceFileCoordinator()

        let manager = makeLiveWorkspaceManager(
            for: workspaceURL,
            fileCoordinator: fileCoordinator
        )
        _ = await manager.selectWorkspace(at: workspaceURL)

        let rootAliasURL = URL(filePath: "\(workspaceURL.path)/.")
        let mutationResult = try await manager.createFile(named: "Notes", in: rootAliasURL)

        guard case let .createdFile(url, displayName) = mutationResult.outcome else {
            return XCTFail("Expected createdFile result.")
        }

        XCTAssertEqual(displayName, "Notes.md")
        XCTAssertEqual(url, workspaceURL.appending(path: "Notes.md"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(fileCoordinator.createdURLs, [url])
    }

    @MainActor
    func testCreateFolderCreatesDirectoryAndUpdatesSnapshot() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        let fileCoordinator = RecordingWorkspaceFileCoordinator()

        let manager = makeLiveWorkspaceManager(
            for: workspaceURL,
            fileCoordinator: fileCoordinator
        )
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.createFolder(named: "Notes", in: nil)

        guard case let .createdFolder(url, displayName) = mutationResult.outcome else {
            return XCTFail("Expected createdFolder result.")
        }

        var isDirectory = ObjCBool(false)
        XCTAssertEqual(displayName, "Notes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(mutationResult.snapshot.rootNodes.contains(where: { $0.displayName == "Notes" }))
        XCTAssertEqual(
            fileCoordinator.createdURLs.map(WorkspaceIdentity.normalizedPath(for:)),
            [WorkspaceIdentity.normalizedPath(for: url)]
        )
    }

    @MainActor
    func testCreateFolderUsesUniqueNameWhenDuplicateExists() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        try FileManager.default.createDirectory(
            at: workspaceURL.appending(path: "Notes"),
            withIntermediateDirectories: false
        )
        let fileCoordinator = RecordingWorkspaceFileCoordinator()

        let manager = makeLiveWorkspaceManager(
            for: workspaceURL,
            fileCoordinator: fileCoordinator
        )
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.createFolder(named: "Notes", in: nil)

        guard case let .createdFolder(url, _) = mutationResult.outcome else {
            return XCTFail("Expected createdFolder result.")
        }

        XCTAssertEqual(url.lastPathComponent, "Notes 2")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceURL.appending(path: "Notes 2").path))
        XCTAssertTrue(mutationResult.snapshot.rootNodes.contains(where: { $0.displayName == "Notes 2" }))
        XCTAssertEqual(
            fileCoordinator.createdURLs.map(WorkspaceIdentity.normalizedPath(for:)),
            [WorkspaceIdentity.normalizedPath(for: url)]
        )
    }

    @MainActor
    func testRenameFolderUpdatesSnapshot() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        let folderURL = workspaceURL.appending(path: "Drafts")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        try Data("# Note".utf8).write(to: folderURL.appending(path: "Note.md"))
        let fileCoordinator = RecordingWorkspaceFileCoordinator()

        let manager = makeLiveWorkspaceManager(
            for: workspaceURL,
            fileCoordinator: fileCoordinator
        )
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.renameFile(at: folderURL, to: "Archive")

        guard case let .renamedFolder(oldURL, newURL, displayName, relativePath) = mutationResult.outcome else {
            return XCTFail("Expected renamedFolder result.")
        }

        XCTAssertEqual(WorkspaceIdentity.normalizedPath(for: oldURL), WorkspaceIdentity.normalizedPath(for: folderURL))
        XCTAssertEqual(
            WorkspaceIdentity.normalizedPath(for: newURL),
            WorkspaceIdentity.normalizedPath(for: workspaceURL.appending(path: "Archive"))
        )
        XCTAssertEqual(displayName, "Archive")
        XCTAssertEqual(relativePath, "Archive")
        XCTAssertTrue(mutationResult.snapshot.rootNodes.contains(where: { $0.displayName == "Archive" }))
        XCTAssertEqual(fileCoordinator.movedURLs.count, 1)
        XCTAssertEqual(
            fileCoordinator.movedURLs.first.map { WorkspaceIdentity.normalizedPath(for: $0.0) },
            WorkspaceIdentity.normalizedPath(for: oldURL)
        )
        XCTAssertEqual(
            fileCoordinator.movedURLs.first.map { WorkspaceIdentity.normalizedPath(for: $0.1) },
            WorkspaceIdentity.normalizedPath(for: newURL)
        )
    }

    @MainActor
    func testRenameFolderAllowsCaseOnlyRenameOnCaseInsensitiveVolume() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        let folderURL = workspaceURL.appending(path: "Drafts")
        let destinationURL = workspaceURL.appending(path: "drafts")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        try Data("# Note".utf8).write(to: folderURL.appending(path: "Note.md"))
        try XCTSkipIf(
            FileManager.default.fileExists(atPath: destinationURL.path) == false,
            "Case-only rename coverage requires a case-insensitive volume."
        )
        let fileCoordinator = RecordingWorkspaceFileCoordinator()

        let manager = makeLiveWorkspaceManager(
            for: workspaceURL,
            fileCoordinator: fileCoordinator
        )
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.renameFile(at: folderURL, to: "drafts")

        guard case let .renamedFolder(oldURL, newURL, displayName, relativePath) = mutationResult.outcome else {
            return XCTFail("Expected renamedFolder result.")
        }

        let rootEntryNames = try FileManager.default.contentsOfDirectory(atPath: workspaceURL.path)

        XCTAssertEqual(WorkspaceIdentity.normalizedPath(for: oldURL), WorkspaceIdentity.normalizedPath(for: folderURL))
        XCTAssertEqual(WorkspaceIdentity.normalizedPath(for: newURL), WorkspaceIdentity.normalizedPath(for: destinationURL))
        XCTAssertEqual(displayName, "drafts")
        XCTAssertEqual(relativePath, "drafts")
        XCTAssertTrue(rootEntryNames.contains("drafts"))
        XCTAssertFalse(rootEntryNames.contains("Drafts"))
        XCTAssertTrue(mutationResult.snapshot.rootNodes.contains(where: { $0.displayName == "drafts" }))
        XCTAssertEqual(fileCoordinator.movedURLs.count, 1)
    }

    @MainActor
    func testDeleteFolderRemovesFolderAndReturnsRefreshedSnapshot() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        let folderURL = workspaceURL.appending(path: "Drafts")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        try Data("# Note".utf8).write(to: folderURL.appending(path: "Note.md"))
        let fileCoordinator = RecordingWorkspaceFileCoordinator()

        let manager = makeLiveWorkspaceManager(
            for: workspaceURL,
            fileCoordinator: fileCoordinator
        )
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.deleteFile(at: folderURL)

        guard case let .deletedFolder(url, displayName) = mutationResult.outcome else {
            return XCTFail("Expected deletedFolder result.")
        }

        XCTAssertEqual(WorkspaceIdentity.normalizedPath(for: url), WorkspaceIdentity.normalizedPath(for: folderURL))
        XCTAssertEqual(displayName, "Drafts")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folderURL.path))
        XCTAssertFalse(
            mutationResult.snapshot.rootNodes.contains {
                WorkspaceIdentity.normalizedPath(for: $0.url) == WorkspaceIdentity.normalizedPath(for: folderURL)
            }
        )
        XCTAssertEqual(
            fileCoordinator.deletedURLs.map(WorkspaceIdentity.normalizedPath(for:)),
            [WorkspaceIdentity.normalizedPath(for: folderURL)]
        )
    }

    @MainActor
    func testMoveFolderIntoAnotherFolderUpdatesSnapshot() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        let archiveURL = workspaceURL.appending(path: "Archive")
        let draftsURL = workspaceURL.appending(path: "Drafts")
        try FileManager.default.createDirectory(at: archiveURL, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: draftsURL, withIntermediateDirectories: false)
        try Data("# Note".utf8).write(to: draftsURL.appending(path: "Note.md"))
        let fileCoordinator = RecordingWorkspaceFileCoordinator()

        let manager = makeLiveWorkspaceManager(
            for: workspaceURL,
            fileCoordinator: fileCoordinator
        )
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.moveItem(at: draftsURL, toFolder: archiveURL)

        guard case let .renamedFolder(oldURL, newURL, displayName, relativePath) = mutationResult.outcome else {
            return XCTFail("Expected renamedFolder result for move.")
        }

        let expectedURL = archiveURL.appending(path: "Drafts")
        XCTAssertEqual(WorkspaceIdentity.normalizedPath(for: oldURL), WorkspaceIdentity.normalizedPath(for: draftsURL))
        XCTAssertEqual(WorkspaceIdentity.normalizedPath(for: newURL), WorkspaceIdentity.normalizedPath(for: expectedURL))
        XCTAssertEqual(displayName, "Drafts")
        XCTAssertEqual(relativePath, "Archive/Drafts")
        XCTAssertFalse(FileManager.default.fileExists(atPath: draftsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL.appending(path: "Note.md").path))
        XCTAssertEqual(mutationResult.snapshot.relativePath(for: expectedURL), "Archive/Drafts")
        XCTAssertEqual(fileCoordinator.movedURLs.count, 1)
    }

    @MainActor
    func testMoveRootFolderToWorkspaceRootIsHarmlessNoOp() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        let draftsURL = workspaceURL.appending(path: "Drafts")
        try FileManager.default.createDirectory(at: draftsURL, withIntermediateDirectories: false)
        try Data("# Note".utf8).write(to: draftsURL.appending(path: "Note.md"))
        let fileCoordinator = RecordingWorkspaceFileCoordinator()

        let manager = makeLiveWorkspaceManager(
            for: workspaceURL,
            fileCoordinator: fileCoordinator
        )
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.moveItem(at: draftsURL, toFolder: nil)

        guard case let .renamedFolder(oldURL, newURL, displayName, relativePath) = mutationResult.outcome else {
            return XCTFail("Expected renamedFolder no-op result.")
        }

        XCTAssertEqual(WorkspaceIdentity.normalizedPath(for: oldURL), WorkspaceIdentity.normalizedPath(for: draftsURL))
        XCTAssertEqual(WorkspaceIdentity.normalizedPath(for: newURL), WorkspaceIdentity.normalizedPath(for: draftsURL))
        XCTAssertEqual(displayName, "Drafts")
        XCTAssertEqual(relativePath, "Drafts")
        XCTAssertTrue(FileManager.default.fileExists(atPath: draftsURL.appending(path: "Note.md").path))
        XCTAssertEqual(mutationResult.snapshot.relativePath(for: draftsURL), "Drafts")
        XCTAssertTrue(fileCoordinator.movedURLs.isEmpty)
    }

    @MainActor
    func testRenameFileUpdatesSnapshot() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        let fileURL = workspaceURL.appending(path: "Draft.md")
        try Data("# Draft".utf8).write(to: fileURL)
        let fileCoordinator = RecordingWorkspaceFileCoordinator()

        let manager = makeLiveWorkspaceManager(
            for: workspaceURL,
            fileCoordinator: fileCoordinator
        )
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.renameFile(at: fileURL, to: "Published")

        guard case let .renamedFile(oldURL, newURL, displayName, relativePath) = mutationResult.outcome else {
            return XCTFail("Expected renamedFile result.")
        }

        XCTAssertEqual(oldURL, fileURL)
        XCTAssertEqual(newURL.lastPathComponent, "Published.md")
        XCTAssertEqual(displayName, "Published.md")
        XCTAssertEqual(relativePath, "Published.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertTrue(mutationResult.snapshot.rootNodes.contains(where: { $0.displayName == "Published.md" }))
        XCTAssertFalse(mutationResult.snapshot.rootNodes.contains(where: { $0.displayName == "Draft.md" }))
        XCTAssertEqual(fileCoordinator.movedURLs.count, 1)
        XCTAssertEqual(fileCoordinator.movedURLs.first?.0, fileURL)
        XCTAssertEqual(fileCoordinator.movedURLs.first?.1, newURL)
    }

    @MainActor
    func testRenameFileAllowsCaseOnlyRenameOnCaseInsensitiveVolume() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        let fileURL = workspaceURL.appending(path: "Draft.md")
        let destinationURL = workspaceURL.appending(path: "draft.md")
        try Data("# Draft".utf8).write(to: fileURL)
        try XCTSkipIf(
            FileManager.default.fileExists(atPath: destinationURL.path) == false,
            "Case-only rename coverage requires a case-insensitive volume."
        )
        let fileCoordinator = RecordingWorkspaceFileCoordinator()

        let manager = makeLiveWorkspaceManager(
            for: workspaceURL,
            fileCoordinator: fileCoordinator
        )
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.renameFile(at: fileURL, to: "draft")

        guard case let .renamedFile(oldURL, newURL, displayName, relativePath) = mutationResult.outcome else {
            return XCTFail("Expected renamedFile result.")
        }

        let rootEntryNames = try FileManager.default.contentsOfDirectory(atPath: workspaceURL.path)

        XCTAssertEqual(oldURL, fileURL)
        XCTAssertEqual(newURL.lastPathComponent, "draft.md")
        XCTAssertEqual(displayName, "draft.md")
        XCTAssertEqual(relativePath, "draft.md")
        XCTAssertTrue(rootEntryNames.contains("draft.md"))
        XCTAssertFalse(rootEntryNames.contains("Draft.md"))
        XCTAssertEqual(try String(contentsOf: newURL, encoding: .utf8), "# Draft")
        XCTAssertTrue(mutationResult.snapshot.rootNodes.contains(where: { $0.displayName == "draft.md" }))
        XCTAssertEqual(fileCoordinator.movedURLs.count, 1)
    }

    @MainActor
    func testRenameFileRejectsDifferentExistingTarget() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        let fileURL = workspaceURL.appending(path: "Draft.md")
        let existingTargetURL = workspaceURL.appending(path: "Published.md")
        try Data("# Draft".utf8).write(to: fileURL)
        try Data("# Published".utf8).write(to: existingTargetURL)
        let fileCoordinator = RecordingWorkspaceFileCoordinator()

        let manager = makeLiveWorkspaceManager(
            for: workspaceURL,
            fileCoordinator: fileCoordinator
        )
        _ = await manager.selectWorkspace(at: workspaceURL)

        do {
            _ = try await manager.renameFile(at: fileURL, to: "Published")
            XCTFail("Expected rename to reject a different existing destination.")
        } catch let error as AppError {
            guard case let .fileOperationFailed(action, name, details) = error else {
                return XCTFail("Expected fileOperationFailed for duplicate rename.")
            }

            XCTAssertEqual(action, "Rename File")
            XCTAssertEqual(name, "Draft.md")
            XCTAssertEqual(details, "Published.md already exists in this folder.")
        }

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "# Draft")
        XCTAssertEqual(try String(contentsOf: existingTargetURL, encoding: .utf8), "# Published")
    }

    @MainActor
    func testMoveFileIntoAnotherFolderUpdatesSnapshot() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        let archiveURL = workspaceURL.appending(path: "Archive")
        let fileURL = workspaceURL.appending(path: "Draft.md")
        try FileManager.default.createDirectory(at: archiveURL, withIntermediateDirectories: false)
        try Data("# Draft".utf8).write(to: fileURL)
        let fileCoordinator = RecordingWorkspaceFileCoordinator()

        let manager = makeLiveWorkspaceManager(
            for: workspaceURL,
            fileCoordinator: fileCoordinator
        )
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.moveItem(at: fileURL, toFolder: archiveURL)

        guard case let .renamedFile(oldURL, newURL, displayName, relativePath) = mutationResult.outcome else {
            return XCTFail("Expected renamedFile result for move.")
        }

        let expectedURL = archiveURL.appending(path: "Draft.md")
        XCTAssertEqual(oldURL, fileURL)
        XCTAssertEqual(newURL, expectedURL)
        XCTAssertEqual(displayName, "Draft.md")
        XCTAssertEqual(relativePath, "Archive/Draft.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL.path))
        XCTAssertEqual(try String(contentsOf: expectedURL, encoding: .utf8), "# Draft")
        XCTAssertEqual(mutationResult.snapshot.relativePath(for: expectedURL), "Archive/Draft.md")
        XCTAssertEqual(fileCoordinator.movedURLs.first?.0, fileURL)
        XCTAssertEqual(fileCoordinator.movedURLs.first?.1, expectedURL)
    }

    @MainActor
    func testMoveRootFileToWorkspaceRootIsHarmlessNoOp() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        let fileURL = workspaceURL.appending(path: "Draft.md")
        try Data("# Draft".utf8).write(to: fileURL)
        let fileCoordinator = RecordingWorkspaceFileCoordinator()

        let manager = makeLiveWorkspaceManager(
            for: workspaceURL,
            fileCoordinator: fileCoordinator
        )
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.moveItem(at: fileURL, toFolder: nil)

        guard case let .renamedFile(oldURL, newURL, displayName, relativePath) = mutationResult.outcome else {
            return XCTFail("Expected renamedFile no-op result.")
        }

        XCTAssertEqual(oldURL, fileURL)
        XCTAssertEqual(newURL, fileURL)
        XCTAssertEqual(displayName, "Draft.md")
        XCTAssertEqual(relativePath, "Draft.md")
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "# Draft")
        XCTAssertEqual(mutationResult.snapshot.relativePath(for: fileURL), "Draft.md")
        XCTAssertTrue(fileCoordinator.movedURLs.isEmpty)
    }

    @MainActor
    func testMoveFileRejectsDifferentExistingTargetInDestinationFolder() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        let archiveURL = workspaceURL.appending(path: "Archive")
        let fileURL = workspaceURL.appending(path: "Draft.md")
        let existingTargetURL = archiveURL.appending(path: "Draft.md")
        try FileManager.default.createDirectory(at: archiveURL, withIntermediateDirectories: false)
        try Data("# Draft".utf8).write(to: fileURL)
        try Data("# Existing".utf8).write(to: existingTargetURL)
        let fileCoordinator = RecordingWorkspaceFileCoordinator()

        let manager = makeLiveWorkspaceManager(
            for: workspaceURL,
            fileCoordinator: fileCoordinator
        )
        _ = await manager.selectWorkspace(at: workspaceURL)

        do {
            _ = try await manager.moveItem(at: fileURL, toFolder: archiveURL)
            XCTFail("Expected move to reject a different existing destination.")
        } catch let error as AppError {
            guard case let .fileOperationFailed(action, name, details) = error else {
                return XCTFail("Expected fileOperationFailed for duplicate move.")
            }

            XCTAssertEqual(action, "Move File")
            XCTAssertEqual(name, "Draft.md")
            XCTAssertEqual(details, "Draft.md already exists in this folder.")
        }

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "# Draft")
        XCTAssertEqual(try String(contentsOf: existingTargetURL, encoding: .utf8), "# Existing")
    }

    @MainActor
    func testDeleteFileRemovesFileAndReturnsRefreshedSnapshot() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        let fileURL = workspaceURL.appending(path: "Trash.md")
        try Data("# Trash".utf8).write(to: fileURL)
        let fileCoordinator = RecordingWorkspaceFileCoordinator()

        let manager = makeLiveWorkspaceManager(
            for: workspaceURL,
            fileCoordinator: fileCoordinator
        )
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.deleteFile(at: fileURL)

        guard case let .deletedFile(url, displayName) = mutationResult.outcome else {
            return XCTFail("Expected deletedFile result.")
        }

        XCTAssertEqual(url, fileURL)
        XCTAssertEqual(displayName, "Trash.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(mutationResult.snapshot.rootNodes.contains(where: { $0.displayName == "Trash.md" }))
        XCTAssertEqual(fileCoordinator.deletedURLs, [fileURL])
    }

    @MainActor
    func testRenameFileRejectsSymbolicLinkPointingOutsideWorkspace() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        let externalURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        defer { removeItemIfPresent(at: externalURL) }

        let externalFileURL = externalURL.appending(path: "Escaped.md")
        try Data("# Escaped".utf8).write(to: externalFileURL)
        let symbolicLinkURL = workspaceURL.appending(path: "Escaped.md")
        try FileManager.default.createSymbolicLink(
            at: symbolicLinkURL,
            withDestinationURL: externalFileURL
        )
        let fileCoordinator = RecordingWorkspaceFileCoordinator()

        let manager = makeLiveWorkspaceManager(
            for: workspaceURL,
            fileCoordinator: fileCoordinator
        )
        _ = await manager.selectWorkspace(at: workspaceURL)

        do {
            _ = try await manager.renameFile(at: symbolicLinkURL, to: "Published")
            XCTFail("Expected escaped symbolic link rename to throw.")
        } catch let error as AppError {
            guard case let .fileOperationFailed(action, name, details) = error else {
                return XCTFail("Expected fileOperationFailed for escaped symbolic link rename.")
            }

            XCTAssertEqual(action, "Workspace File Operation")
            XCTAssertEqual(name, "Escaped.md")
            XCTAssertEqual(details, "The file is outside the current workspace.")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: symbolicLinkURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalFileURL.path))
        XCTAssertTrue(fileCoordinator.movedURLs.isEmpty)
    }

    @MainActor
    func testDeleteFileRejectsSymbolicLinkPointingOutsideWorkspace() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        let externalURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        defer { removeItemIfPresent(at: externalURL) }

        let externalFileURL = externalURL.appending(path: "Escaped.md")
        try Data("# Escaped".utf8).write(to: externalFileURL)
        let symbolicLinkURL = workspaceURL.appending(path: "Escaped.md")
        try FileManager.default.createSymbolicLink(
            at: symbolicLinkURL,
            withDestinationURL: externalFileURL
        )
        let fileCoordinator = RecordingWorkspaceFileCoordinator()

        let manager = makeLiveWorkspaceManager(
            for: workspaceURL,
            fileCoordinator: fileCoordinator
        )
        _ = await manager.selectWorkspace(at: workspaceURL)

        do {
            _ = try await manager.deleteFile(at: symbolicLinkURL)
            XCTFail("Expected escaped symbolic link delete to throw.")
        } catch let error as AppError {
            guard case let .fileOperationFailed(action, name, details) = error else {
                return XCTFail("Expected fileOperationFailed for escaped symbolic link delete.")
            }

            XCTAssertEqual(action, "Workspace File Operation")
            XCTAssertEqual(name, "Escaped.md")
            XCTAssertEqual(details, "The file is outside the current workspace.")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: symbolicLinkURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalFileURL.path))
        XCTAssertTrue(fileCoordinator.deletedURLs.isEmpty)
    }

    @MainActor
    private func makeLiveWorkspaceManager(
        for workspaceURL: URL,
        fileCoordinator: any WorkspaceFileCoordinating = RecordingWorkspaceFileCoordinator()
    ) -> LiveWorkspaceManager {
        LiveWorkspaceManager(
            bookmarkStore: StubBookmarkStore(),
            securityScopedAccess: FakeSecurityScopedAccessHandler(
                resolvedURL: workspaceURL,
                isStale: false,
                shouldAllowAccess: true
            ),
            workspaceEnumerator: LiveWorkspaceEnumerator(),
            fileCoordinator: fileCoordinator
        )
    }

    @MainActor
    private func makeTemporaryWorkspace() throws -> URL {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appending(path: "WorkspaceManagerRestoreTests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: workspaceURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return workspaceURL
    }

    @MainActor
    private func removeItemIfPresent(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

private final class RecordingWorkspaceFileCoordinator: @unchecked Sendable, WorkspaceFileCoordinating {
    private let lock = NSLock()
    private var storedCreatedURLs: [URL] = []
    private var storedMovedURLs: [(URL, URL)] = []
    private var storedDeletedURLs: [URL] = []

    var createdURLs: [URL] {
        lock.withLock { storedCreatedURLs }
    }

    var movedURLs: [(URL, URL)] {
        lock.withLock { storedMovedURLs }
    }

    var deletedURLs: [URL] {
        lock.withLock { storedDeletedURLs }
    }

    func coordinateCreation(
        at url: URL,
        accessor: (URL) throws -> Void
    ) throws {
        lock.withLock {
            storedCreatedURLs.append(url)
        }
        try accessor(url)
    }

    func coordinateMove(
        from sourceURL: URL,
        to destinationURL: URL,
        accessor: (URL, URL) throws -> Void
    ) throws {
        lock.withLock {
            storedMovedURLs.append((sourceURL, destinationURL))
        }
        try accessor(sourceURL, destinationURL)
    }

    func coordinateDeletion(
        at url: URL,
        accessor: (URL) throws -> Void
    ) throws {
        lock.withLock {
            storedDeletedURLs.append(url)
        }
        try accessor(url)
    }
}

private final class ScriptedWorkspaceEnumerator: @unchecked Sendable, WorkspaceEnumerating {
    enum Behavior {
        case immediate(WorkspaceSnapshot)
        case delayedUntilCancellation(WorkspaceSnapshot)
        case failure(AppError)
    }

    private let lock = NSLock()
    private var behaviors: [Behavior]
    private var completedEnumerations = 0
    private var cancelledEnumerations = 0

    init(behaviors: [Behavior]) {
        self.behaviors = behaviors
    }

    var completedEnumerationCount: Int {
        lock.withLock { completedEnumerations }
    }

    var cancelledEnumerationCount: Int {
        lock.withLock { cancelledEnumerations }
    }

    nonisolated func makeSnapshot(rootURL: URL, displayName: String) throws -> WorkspaceSnapshot {
        let behavior = lock.withLock {
            behaviors.isEmpty
                ? Behavior.immediate(
                    WorkspaceSnapshot(
                        rootURL: rootURL,
                        displayName: displayName,
                        rootNodes: [],
                        lastUpdated: Date()
                    )
                )
                : behaviors.removeFirst()
        }

        switch behavior {
        case let .immediate(snapshot):
            lock.withLock {
                completedEnumerations += 1
            }
            return WorkspaceSnapshot(
                rootURL: rootURL,
                displayName: displayName,
                rootNodes: snapshot.rootNodes,
                lastUpdated: snapshot.lastUpdated
            )
        case let .delayedUntilCancellation(snapshot):
            do {
                for _ in 0..<200 {
                    try Task.checkCancellation()
                    Thread.sleep(forTimeInterval: 0.005)
                }
            } catch is CancellationError {
                lock.withLock {
                    cancelledEnumerations += 1
                }
                throw CancellationError()
            }

            lock.withLock {
                completedEnumerations += 1
            }
            return WorkspaceSnapshot(
                rootURL: rootURL,
                displayName: displayName,
                rootNodes: snapshot.rootNodes,
                lastUpdated: snapshot.lastUpdated
            )
        case let .failure(error):
            throw error
        }
    }
}

private struct FakeSecurityScopedAccessHandler: SecurityScopedAccessHandling {
    let resolvedURL: URL
    let isStale: Bool
    let shouldAllowAccess: Bool

    func makeBookmark(for url: URL) throws -> Data {
        Data(url.path.utf8)
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedSecurityScopedURL {
        ResolvedSecurityScopedURL(
            url: resolvedURL,
            displayName: resolvedURL.lastPathComponent,
            isStale: isStale
        )
    }

    func validateAccess(to url: URL) throws {
        guard shouldAllowAccess else {
            throw AppError.workspaceAccessInvalid(displayName: url.lastPathComponent)
        }
    }

    func beginAccess(to url: URL) throws -> SecurityScopedAccessLease {
        try validateAccess(to: url)
        return SecurityScopedAccessLease(url: url, stopHandler: nil)
    }

    func withAccess<Value>(to url: URL, operation: (URL) throws -> Value) throws -> Value {
        try validateAccess(to: url)
        return try operation(url)
    }

    func withAccess<Value>(
        toDescendantAt relativePath: String,
        within workspaceRootURL: URL,
        operation: (URL) throws -> Value
    ) throws -> Value {
        try withAccess(to: workspaceRootURL) { rootURL in
            guard let descendantURL = WorkspaceRelativePath.resolveCandidate(
                relativePath,
                within: rootURL
            ) else {
                throw AppError.documentUnavailable(
                    name: relativePath.split(separator: "/").last.map(String.init) ?? "Document"
                )
            }

            return try operation(descendantURL)
        }
    }
}

private final class RecordingSecurityScopedAccessHandler: @unchecked Sendable, SecurityScopedAccessHandling {
    private let lock = NSLock()
    private let resolvedBookmarks: [Data: ResolvedSecurityScopedURL]
    private let defaultResolvedURL: URL?
    private let makeBookmarkDataValue: Data
    private let staleBookmarkData: Set<Data>
    private let shouldAllowAccess: Bool
    private var makeBookmarkCalls = 0
    private var resolvedBookmarksHistory: [Data] = []

    init(
        resolvedURL: URL? = nil,
        makeBookmarkData: Data = Data("bookmark".utf8),
        staleBookmarkData: Set<Data> = [],
        shouldAllowAccess: Bool = true
    ) {
        self.resolvedBookmarks = [:]
        self.defaultResolvedURL = resolvedURL
        self.makeBookmarkDataValue = makeBookmarkData
        self.staleBookmarkData = staleBookmarkData
        self.shouldAllowAccess = shouldAllowAccess
    }

    init(
        resolvedBookmarks: [Data: ResolvedSecurityScopedURL],
        makeBookmarkData: Data,
        shouldAllowAccess: Bool = true
    ) {
        self.resolvedBookmarks = resolvedBookmarks
        self.defaultResolvedURL = nil
        self.makeBookmarkDataValue = makeBookmarkData
        self.staleBookmarkData = []
        self.shouldAllowAccess = shouldAllowAccess
    }

    var makeBookmarkCallCount: Int {
        lock.withLock { makeBookmarkCalls }
    }

    var resolvedBookmarkData: [Data] {
        lock.withLock { resolvedBookmarksHistory }
    }

    func makeBookmark(for url: URL) throws -> Data {
        lock.withLock {
            makeBookmarkCalls += 1
        }
        return makeBookmarkDataValue
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedSecurityScopedURL {
        lock.withLock {
            resolvedBookmarksHistory.append(data)
        }

        if let resolvedBookmark = resolvedBookmarks[data] {
            return resolvedBookmark
        }

        guard let defaultResolvedURL else {
            throw AppError.workspaceRestoreFailed(details: "Missing resolved bookmark fixture.")
        }

        return ResolvedSecurityScopedURL(
            url: defaultResolvedURL,
            displayName: defaultResolvedURL.lastPathComponent,
            isStale: staleBookmarkData.contains(data)
        )
    }

    func validateAccess(to url: URL) throws {
        guard shouldAllowAccess else {
            throw AppError.workspaceAccessInvalid(displayName: url.lastPathComponent)
        }
    }

    func beginAccess(to url: URL) throws -> SecurityScopedAccessLease {
        try validateAccess(to: url)
        return SecurityScopedAccessLease(url: url, stopHandler: nil)
    }

    func withAccess<Value>(to url: URL, operation: (URL) throws -> Value) throws -> Value {
        try validateAccess(to: url)
        return try operation(url)
    }

    func withAccess<Value>(
        toDescendantAt relativePath: String,
        within workspaceRootURL: URL,
        operation: (URL) throws -> Value
    ) throws -> Value {
        try withAccess(to: workspaceRootURL) { rootURL in
            guard let descendantURL = WorkspaceRelativePath.resolveCandidate(
                relativePath,
                within: rootURL
            ) else {
                throw AppError.documentUnavailable(
                    name: relativePath.split(separator: "/").last.map(String.init) ?? "Document"
                )
            }

            return try operation(descendantURL)
        }
    }
}

private extension NSLock {
    func withLock<Value>(_ operation: () -> Value) -> Value {
        lock()
        defer { unlock() }
        return operation()
    }
}
