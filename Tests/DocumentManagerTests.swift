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
    func testOpenDocumentThrowsForInvalidUTF8File() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let fileURL = workspaceURL.appending(path: "Broken.md")
        try Data([0xFF, 0xFE, 0x00]).write(to: fileURL)

        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())

        do {
            _ = try await manager.openDocument(at: fileURL, in: workspaceURL)
            XCTFail("Expected invalid UTF-8 open to throw.")
        } catch let error as AppError {
            guard case let .documentOpenFailed(name, details) = error else {
                return XCTFail("Expected documentOpenFailed error.")
            }

            XCTAssertEqual(name, "Broken.md")
            XCTAssertEqual(details, "The file is not valid UTF-8 text.")
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
    func testSaveOverwritesOutsideWriteForActiveBufferWithoutConflict() async throws {
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

        let savedDocument = try await manager.saveDocument(document, overwriteConflict: false)

        XCTAssertEqual(savedDocument.conflictState, .none)
        XCTAssertFalse(savedDocument.isDirty)
        XCTAssertEqual(savedDocument.text, "# Entry\n\nLocal edits.")
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "# Entry\n\nLocal edits.")
    }

    @MainActor
    func testRevalidateRefreshesCleanDocumentAfterOutsideWriteWithoutConflict() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let fileURL = try makeTemporaryFile(
            in: workspaceURL,
            named: "External.md",
            contents: """
            # Entry

            Original text.
            """
        )

        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())
        let document = try await manager.openDocument(at: fileURL, in: workspaceURL)

        try "# Entry\n\nChanged elsewhere.".write(to: fileURL, atomically: true, encoding: .utf8)

        let revalidatedDocument = try await manager.revalidateDocument(document)

        XCTAssertEqual(revalidatedDocument.conflictState, .none)
        XCTAssertFalse(revalidatedDocument.isDirty)
        XCTAssertEqual(revalidatedDocument.text, "# Entry\n\nChanged elsewhere.")
    }

    @MainActor
    func testRevalidatePreservesDirtyBufferAfterOutsideWriteWithoutConflict() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let fileURL = try makeTemporaryFile(
            in: workspaceURL,
            named: "Dirty.md",
            contents: """
            # Entry

            Original text.
            """
        )

        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())
        var document = try await manager.openDocument(at: fileURL, in: workspaceURL)
        document.text = "# Entry\n\nLocal edits still in memory."
        document.isDirty = true
        document.saveState = .unsaved

        try "# Entry\n\nChanged elsewhere.".write(to: fileURL, atomically: true, encoding: .utf8)

        let revalidatedDocument = try await manager.revalidateDocument(document)

        XCTAssertEqual(revalidatedDocument.conflictState, .none)
        XCTAssertTrue(revalidatedDocument.isDirty)
        XCTAssertEqual(revalidatedDocument.text, "# Entry\n\nLocal edits still in memory.")
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
    func testMissingFileCanBeRecreatedWithExplicitOverwrite() async throws {
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

        try FileManager.default.removeItem(at: fileURL)
        let conflictedDocument = try await manager.saveDocument(document, overwriteConflict: false)

        let overwrittenDocument = try await manager.saveDocument(document, overwriteConflict: true)
        XCTAssertFalse(overwrittenDocument.isDirty)
        XCTAssertEqual(overwrittenDocument.conflictState, .none)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "# Entry\n\nLocal edits.")

        guard case let .needsResolution(conflict) = conflictedDocument.conflictState else {
            return XCTFail("Expected a missing-file conflict before explicit overwrite.")
        }
        XCTAssertEqual(conflict.kind, .missingOnDisk)
    }

    @MainActor
    func testSuccessfulSaveReturnsUpdatedLoadedVersionForFutureConflictChecks() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let fileURL = try makeTemporaryFile(
            in: workspaceURL,
            named: "Revalidate.md",
            contents: """
            # Entry

            Original text.
            """
        )

        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())
        var document = try await manager.openDocument(at: fileURL, in: workspaceURL)
        let originalVersion = document.loadedVersion
        document.text = "# Entry\n\nSaved text."
        document.isDirty = true
        document.saveState = .unsaved

        let savedDocument = try await manager.saveDocument(document, overwriteConflict: false)

        XCTAssertEqual(savedDocument.text, "# Entry\n\nSaved text.")
        XCTAssertNotEqual(savedDocument.loadedVersion.contentDigest, originalVersion.contentDigest)
        XCTAssertFalse(savedDocument.isDirty)
        XCTAssertEqual(savedDocument.conflictState, .none)
    }

    @MainActor
    func testRelocatedSessionSavesRenamedDocumentAtNewPath() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let originalURL = try makeTemporaryFile(
            in: workspaceURL,
            named: "Draft.md",
            contents: """
            # Entry

            Original text.
            """
        )
        let renamedURL = workspaceURL.appending(path: "Published.md")

        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())
        var document = try await manager.openDocument(at: originalURL, in: workspaceURL)
        let observation = try await manager.observeDocumentChanges(for: document)

        try FileManager.default.moveItem(at: originalURL, to: renamedURL)
        await manager.relocateDocumentSession(
            for: document,
            to: renamedURL,
            relativePath: "Published.md"
        )

        document.url = renamedURL
        document.relativePath = "Published.md"
        document.displayName = "Published.md"
        document.text = "# Entry\n\nRenamed file edits."
        document.isDirty = true
        document.saveState = .unsaved

        let savedDocument = try await manager.saveDocument(document, overwriteConflict: false)

        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertEqual(try String(contentsOf: renamedURL, encoding: .utf8), "# Entry\n\nRenamed file edits.")
        XCTAssertEqual(savedDocument.url, renamedURL)
        XCTAssertEqual(savedDocument.relativePath, "Published.md")
        XCTAssertEqual(savedDocument.displayName, "Published.md")

        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testFallbackObservationBacksOffWithoutSyntheticChangesWhenFileIsUnchanged() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        _ = try makeTemporaryFile(
            in: workspaceURL,
            named: "Observed.md",
            contents: "# Entry\n\nStable text."
        )
        let recorder = FallbackObservationRecorder()
        let session = PlainTextDocumentSession(
            relativePath: "Observed.md",
            workspaceRootURL: workspaceURL,
            securityScopedAccess: FakeDocumentSecurityAccessHandler(),
            filePresenterEnabled: false,
            observationFallbackSchedule: .init(
                intervals: [.milliseconds(20), .milliseconds(40), .milliseconds(80)]
            ),
            onFallbackPoll: {
                Task {
                    await recorder.recordPoll()
                }
            }
        )

        let stream = try await session.observeChanges()
        let observationTask = Task {
            for await _ in stream {
                await recorder.recordEvent()
            }
        }

        try await waitUntil(timeout: .milliseconds(120)) {
            await recorder.pollCount > 0
        }
        try await Task.sleep(for: .milliseconds(150))

        let eventCount = await recorder.eventCount
        let pollCount = await recorder.pollCount
        XCTAssertEqual(eventCount, 0)
        XCTAssertLessThanOrEqual(pollCount, 3)

        observationTask.cancel()
    }

    @MainActor
    func testFallbackObservationDetectsExternalChangeWithoutPresenterCallbacks() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let fileURL = try makeTemporaryFile(
            in: workspaceURL,
            named: "Observed.md",
            contents: "# Entry\n\nOriginal text."
        )
        let recorder = FallbackObservationRecorder()
        let session = PlainTextDocumentSession(
            relativePath: "Observed.md",
            workspaceRootURL: workspaceURL,
            securityScopedAccess: FakeDocumentSecurityAccessHandler(),
            filePresenterEnabled: false,
            observationFallbackSchedule: .init(
                intervals: [.milliseconds(20), .milliseconds(20), .milliseconds(20)]
            ),
            onFallbackPoll: {
                Task {
                    await recorder.recordPoll()
                }
            }
        )

        let stream = try await session.observeChanges()
        let observationTask = Task {
            for await _ in stream {
                await recorder.recordEvent()
            }
        }

        try await waitUntil(timeout: .milliseconds(120)) {
            await recorder.pollCount > 0
        }
        try """
        # Entry

        Changed elsewhere with clearly different size.
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        try await waitUntil(timeout: .milliseconds(400)) {
            await recorder.eventCount > 0
        }

        observationTask.cancel()
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

    @MainActor
    private func waitUntil(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(10),
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            if await condition() {
                return
            }

            try await Task.sleep(for: pollInterval)
        }

        XCTFail("Timed out waiting for condition.")
    }
}

private actor FallbackObservationRecorder {
    private(set) var pollCount = 0
    private(set) var eventCount = 0

    func recordPoll() {
        pollCount += 1
    }

    func recordEvent() {
        eventCount += 1
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

    func beginAccess(to url: URL) throws -> SecurityScopedAccessLease {
        SecurityScopedAccessLease(url: url, stopHandler: nil)
    }

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

    func beginAccess(to url: URL) throws -> SecurityScopedAccessLease {
        SecurityScopedAccessLease(url: url, stopHandler: nil)
    }

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
