import Foundation
import XCTest
@testable import Downward

final class WorkspaceManagerRestoreTests: XCTestCase {
    @MainActor
    func testRestoreRefreshesStaleBookmarkAndPersistsFreshBookmarkData() async throws {
        let bookmarkStore = StubBookmarkStore(
            initialBookmark: StoredWorkspaceBookmark(
                workspaceName: "Stale Workspace",
                lastKnownPath: "/tmp/Stale Workspace",
                bookmarkData: Data("stale-bookmark".utf8)
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
        XCTAssertEqual(refreshedBookmark?.workspaceName, "Renamed Workspace")
        XCTAssertEqual(refreshedBookmark?.lastKnownPath, "/tmp/Renamed Workspace")
        XCTAssertEqual(refreshedBookmark?.bookmarkData, Data("fresh-bookmark".utf8))
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
    func testRestoreUsesRefreshedBookmarkAcrossRelaunchStyleFlow() async throws {
        let bookmarkStore = StubBookmarkStore(
            initialBookmark: StoredWorkspaceBookmark(
                workspaceName: "Original Workspace",
                lastKnownPath: "/tmp/Original Workspace",
                bookmarkData: Data("stale-bookmark".utf8)
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
        fileCoordinator: any WorkspaceFileCoordinating
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
