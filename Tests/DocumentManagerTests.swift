import Foundation
import XCTest
@testable import Downward

final class DocumentManagerTests: XCTestCase {
    @MainActor
    func testOpenDocumentLoadsTextAndMetadata() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let fileURL = try makeTemporaryFile(
            in: workspaceURL,
            named: "Entry.md",
            contents: """
            # Entry

            Plain text body.
            """
        )

        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())

        let document = try await manager.openDocument(at: fileURL, in: workspaceURL)

        XCTAssertEqual(document.url, fileURL)
        XCTAssertEqual(document.workspaceRootURL, workspaceURL)
        XCTAssertEqual(document.relativePath, "Entry.md")
        XCTAssertEqual(document.displayName, "Entry.md")
        XCTAssertTrue(document.text.contains("Plain text body."))
        XCTAssertFalse(document.loadedVersion.contentDigest.isEmpty)
        XCTAssertFalse(document.isDirty)
    }

    @MainActor
    func testOpenDocumentThrowsForMissingFile() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let missingFileURL = workspaceURL.appending(path: "Missing.md")
        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())

        do {
            _ = try await manager.openDocument(at: missingFileURL, in: workspaceURL)
            XCTFail("Expected missing file open to throw.")
        } catch let error as AppError {
            guard case let .documentUnavailable(name) = error else {
                return XCTFail("Expected documentUnavailable error.")
            }

            XCTAssertEqual(name, "Missing.md")
        }
    }

    @MainActor
    func testOpenDocumentUsesWorkspaceRootSecurityScopeForDescendants() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let nestedFolderURL = workspaceURL.appending(path: "Journal").appending(path: "2026")
        try FileManager.default.createDirectory(
            at: nestedFolderURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let fileURL = try makeTemporaryFile(
            in: nestedFolderURL,
            named: "Entry.md",
            contents: "# Entry\n\nNested file."
        )

        let accessHandler = RecordingDocumentSecurityAccessHandler()
        let manager = LiveDocumentManager(securityScopedAccess: accessHandler)

        let document = try await manager.openDocument(at: fileURL, in: workspaceURL)
        let accessedRoots = accessHandler.accessedRoots
        let accessedDescendants = accessHandler.accessedDescendants

        XCTAssertEqual(document.relativePath, "Journal/2026/Entry.md")
        XCTAssertEqual(accessedRoots, [workspaceURL])
        XCTAssertEqual(accessedDescendants, ["Journal/2026/Entry.md"])
    }

    @MainActor
    func testSaveDetectsExternalModificationBeforeOverwrite() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let fileURL = try makeTemporaryFile(
            in: workspaceURL,
            named: "Conflict.md",
            contents: """
            # Entry

            Original text.
            """
        )

        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())
        var document = try await manager.openDocument(at: fileURL, in: workspaceURL)
        document.text = "# Entry\n\nLocal edits."
        document.isDirty = true
        document.saveState = .unsaved

        try Data("# Entry\n\nChanged elsewhere.".utf8).write(to: fileURL, options: .atomic)

        let saveResult = try await manager.saveDocument(document, overwriteConflict: false)

        guard case let .needsResolution(conflict) = saveResult.conflictState else {
            return XCTFail("Expected a conflict state when disk contents changed externally.")
        }

        XCTAssertEqual(conflict.kind, .modifiedOnDisk)
        XCTAssertTrue(saveResult.isDirty)
        XCTAssertEqual(saveResult.saveState, .unsaved)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "# Entry\n\nChanged elsewhere.")
    }

    @MainActor
    func testSaveDetectsDeletedFileWhileOpen() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let fileURL = try makeTemporaryFile(
            in: workspaceURL,
            named: "Deleted.md",
            contents: """
            # Entry

            Original text.
            """
        )

        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())
        var document = try await manager.openDocument(at: fileURL, in: workspaceURL)
        document.text = "# Entry\n\nStill here locally."
        document.isDirty = true
        document.saveState = .unsaved

        try FileManager.default.removeItem(at: fileURL)

        let saveResult = try await manager.saveDocument(document, overwriteConflict: false)

        guard case let .needsResolution(conflict) = saveResult.conflictState else {
            return XCTFail("Expected a missing-file conflict when the path disappears.")
        }

        XCTAssertEqual(conflict.kind, .missingOnDisk)
        XCTAssertTrue(saveResult.isDirty)
        XCTAssertEqual(saveResult.saveState, .unsaved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @MainActor
    func testConflictResolutionSupportsReloadAndExplicitOverwrite() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let fileURL = try makeTemporaryFile(
            in: workspaceURL,
            named: "Resolution.md",
            contents: """
            # Entry

            Original text.
            """
        )

        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())
        var document = try await manager.openDocument(at: fileURL, in: workspaceURL)
        document.text = "# Entry\n\nLocal edits."
        document.isDirty = true
        document.saveState = .unsaved

        try Data("# Entry\n\nDisk replacement.".utf8).write(to: fileURL, options: .atomic)
        let conflictedDocument = try await manager.saveDocument(document, overwriteConflict: false)

        let reloadedDocument = try await manager.reloadDocument(from: conflictedDocument)
        XCTAssertEqual(reloadedDocument.text, "# Entry\n\nDisk replacement.")
        XCTAssertFalse(reloadedDocument.isDirty)
        XCTAssertEqual(reloadedDocument.conflictState, .none)

        let overwrittenDocument = try await manager.saveDocument(document, overwriteConflict: true)
        XCTAssertFalse(overwrittenDocument.isDirty)
        XCTAssertEqual(overwrittenDocument.conflictState, .none)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "# Entry\n\nLocal edits.")
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "DocumentManagerTests")
            .appending(path: UUID().uuidString)
            .appending(path: name)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        return directoryURL
    }

    private func makeTemporaryFile(in directoryURL: URL, named name: String, contents: String) throws -> URL {
        let fileURL = directoryURL.appending(path: name)
        try Data(contents.utf8).write(to: fileURL)
        return fileURL
    }

    private func removeItemIfPresent(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

private struct FakeDocumentSecurityAccessHandler: SecurityScopedAccessHandling {
    func makeBookmark(for url: URL) throws -> Data {
        Data()
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedSecurityScopedURL {
        ResolvedSecurityScopedURL(url: URL(filePath: "/tmp"), displayName: "tmp", isStale: false)
    }

    func validateAccess(to url: URL) throws {}

    func withAccess<Value>(to url: URL, operation: (URL) throws -> Value) throws -> Value {
        try operation(url)
    }

    func withAccess<Value>(
        toDescendantAt relativePath: String,
        within workspaceRootURL: URL,
        operation: (URL) throws -> Value
    ) throws -> Value {
        try operation(
            relativePath
                .split(separator: "/", omittingEmptySubsequences: true)
                .reduce(workspaceRootURL) { partialURL, component in
                    partialURL.appending(path: String(component))
                }
        )
    }
}

private final class RecordingDocumentSecurityAccessHandler: @unchecked Sendable, SecurityScopedAccessHandling {
    private let lock = NSLock()
    private var roots: [URL] = []
    private var descendants: [String] = []

    var accessedRoots: [URL] {
        lock.withLock { roots }
    }

    var accessedDescendants: [String] {
        lock.withLock { descendants }
    }

    func makeBookmark(for url: URL) throws -> Data {
        Data()
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedSecurityScopedURL {
        ResolvedSecurityScopedURL(url: URL(filePath: "/tmp"), displayName: "tmp", isStale: false)
    }

    func validateAccess(to url: URL) throws {}

    func withAccess<Value>(to url: URL, operation: (URL) throws -> Value) throws -> Value {
        fatalError("Document access should go through the workspace root descendant API.")
    }

    func withAccess<Value>(
        toDescendantAt relativePath: String,
        within workspaceRootURL: URL,
        operation: (URL) throws -> Value
    ) throws -> Value {
        lock.withLock {
            roots.append(workspaceRootURL)
            descendants.append(relativePath)
        }
        let descendantURL = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .reduce(workspaceRootURL) { partialURL, component in
                partialURL.appending(path: String(component))
            }
        return try operation(descendantURL)
    }
}

private extension NSLock {
    func withLock<Value>(_ operation: () throws -> Value) rethrows -> Value {
        lock()
        defer { unlock() }
        return try operation()
    }
}
