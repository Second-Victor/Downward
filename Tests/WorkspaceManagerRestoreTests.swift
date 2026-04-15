import Foundation
import XCTest
@testable import Downward

final class WorkspaceManagerRestoreTests: XCTestCase {
    @MainActor
    func testRestoreReturnsReconnectStateWhenBookmarkIsStale() async throws {
        let bookmarkStore = StubBookmarkStore(
            initialBookmark: StoredWorkspaceBookmark(
                workspaceName: "Stale Workspace",
                lastKnownPath: "/tmp/Stale Workspace",
                bookmarkData: Data("stale-bookmark".utf8)
            )
        )
        let manager = LiveWorkspaceManager(
            bookmarkStore: bookmarkStore,
            securityScopedAccess: FakeSecurityScopedAccessHandler(
                resolvedURL: URL(filePath: "/tmp/Stale Workspace"),
                isStale: true,
                shouldAllowAccess: true
            ),
            workspaceEnumerator: StubWorkspaceEnumerator(snapshot: PreviewSampleData.emptyWorkspace)
        )

        let restoreResult = await manager.restoreWorkspace()

        guard case let .accessInvalid(accessState) = restoreResult else {
            return XCTFail("Expected accessInvalid result for stale bookmark.")
        }

        let displayName = accessState.displayName
        let errorTitle = accessState.invalidationError?.title

        XCTAssertEqual(displayName, "Stale Workspace")
        XCTAssertEqual(errorTitle, "Workspace Needs Reconnect")
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
    func testCreateFileAddsMarkdownFileAndReturnsRefreshedSnapshot() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }

        let manager = makeLiveWorkspaceManager(for: workspaceURL)
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.createFile(named: "Notes", in: nil)

        guard case let .createdFile(url, displayName) = mutationResult.outcome else {
            return XCTFail("Expected createdFile result.")
        }

        XCTAssertEqual(displayName, "Notes.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(mutationResult.snapshot.rootNodes.contains(where: { $0.displayName == "Notes.md" }))
    }

    @MainActor
    func testCreateFileUsesUniqueNameWhenDuplicateExists() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        try Data("# Existing".utf8).write(to: workspaceURL.appending(path: "Notes.md"))

        let manager = makeLiveWorkspaceManager(for: workspaceURL)
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.createFile(named: "Notes.md", in: nil)

        guard case let .createdFile(url, _) = mutationResult.outcome else {
            return XCTFail("Expected createdFile result.")
        }

        XCTAssertEqual(url.lastPathComponent, "Notes 2.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceURL.appending(path: "Notes 2.md").path))
        XCTAssertTrue(mutationResult.snapshot.rootNodes.contains(where: { $0.displayName == "Notes 2.md" }))
    }

    @MainActor
    func testRenameFileUpdatesSnapshot() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        let fileURL = workspaceURL.appending(path: "Draft.md")
        try Data("# Draft".utf8).write(to: fileURL)

        let manager = makeLiveWorkspaceManager(for: workspaceURL)
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
    }

    @MainActor
    func testDeleteFileRemovesFileAndReturnsRefreshedSnapshot() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: workspaceURL) }
        let fileURL = workspaceURL.appending(path: "Trash.md")
        try Data("# Trash".utf8).write(to: fileURL)

        let manager = makeLiveWorkspaceManager(for: workspaceURL)
        _ = await manager.selectWorkspace(at: workspaceURL)

        let mutationResult = try await manager.deleteFile(at: fileURL)

        guard case let .deletedFile(url, displayName) = mutationResult.outcome else {
            return XCTFail("Expected deletedFile result.")
        }

        XCTAssertEqual(url, fileURL)
        XCTAssertEqual(displayName, "Trash.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(mutationResult.snapshot.rootNodes.contains(where: { $0.displayName == "Trash.md" }))
    }

    @MainActor
    private func makeLiveWorkspaceManager(for workspaceURL: URL) -> LiveWorkspaceManager {
        LiveWorkspaceManager(
            bookmarkStore: StubBookmarkStore(),
            securityScopedAccess: FakeSecurityScopedAccessHandler(
                resolvedURL: workspaceURL,
                isStale: false,
                shouldAllowAccess: true
            ),
            workspaceEnumerator: LiveWorkspaceEnumerator()
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
            try operation(
                relativePath
                    .split(separator: "/", omittingEmptySubsequences: true)
                    .reduce(rootURL) { partialURL, component in
                        partialURL.appending(path: String(component))
                    }
            )
        }
    }
}
