import CryptoKit
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
    func testOpenDocumentLoadedVersionMatchesRawUTF8FileBytes() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let contents = """
        # Entry

        Cafe
        Emoji: 😀
        """
        let fileURL = try makeTemporaryFile(
            in: workspaceURL,
            named: "Entry.md",
            contents: contents
        )
        let expectedData = Data(contents.utf8)
        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())

        let document = try await manager.openDocument(at: fileURL, in: workspaceURL)

        XCTAssertEqual(document.text, contents)
        XCTAssertEqual(document.loadedVersion.fileSize, expectedData.count)
        XCTAssertEqual(document.loadedVersion.contentDigest, expectedDigest(for: expectedData))
    }

    @MainActor
    func testOpenDocumentLoadedVersionMatchesEmptyFileBytes() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let fileURL = try makeTemporaryFile(
            in: workspaceURL,
            named: "Empty.md",
            contents: ""
        )
        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())

        let document = try await manager.openDocument(at: fileURL, in: workspaceURL)

        XCTAssertEqual(document.text, "")
        XCTAssertEqual(document.loadedVersion.fileSize, 0)
        XCTAssertEqual(document.loadedVersion.contentDigest, expectedDigest(for: Data()))
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
    func testOpenDocumentAtRelativePathLoadsNestedDocument() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let nestedFolderURL = workspaceURL.appending(path: "Journal").appending(path: "2026")
        try FileManager.default.createDirectory(
            at: nestedFolderURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        _ = try makeTemporaryFile(
            in: nestedFolderURL,
            named: "Entry.md",
            contents: "# Entry\n\nNested file."
        )

        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())

        let document = try await manager.openDocument(
            atRelativePath: "Journal/2026/Entry.md",
            in: workspaceURL
        )

        XCTAssertEqual(document.relativePath, "Journal/2026/Entry.md")
        XCTAssertEqual(document.displayName, "Entry.md")
        XCTAssertTrue(document.text.contains("Nested file."))
    }

    @MainActor
    func testOpenDocumentAcceptsEquivalentWorkspaceRootNormalizationForValidDescendant() async throws {
        let (workspaceURL, aliasedWorkspaceURL, cleanupRootURL) = try makeAliasedWorkspace(named: "Workspace")
        defer { removeItemIfPresent(at: cleanupRootURL) }

        let nestedFolderURL = workspaceURL.appending(path: "Journal").appending(path: "2026")
        try FileManager.default.createDirectory(
            at: nestedFolderURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let fileURL = try makeTemporaryFile(
            in: nestedFolderURL,
            named: "Entry.md",
            contents: "# Entry\n\nNormalized root mismatch."
        )

        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())

        let document = try await manager.openDocument(at: fileURL, in: aliasedWorkspaceURL)

        XCTAssertEqual(document.relativePath, "Journal/2026/Entry.md")
        XCTAssertEqual(document.displayName, "Entry.md")
    }

    @MainActor
    func testEnumeratedDocumentStillOpensWhenWorkspaceRootNormalizationDiffers() async throws {
        let (workspaceURL, aliasedWorkspaceURL, cleanupRootURL) = try makeAliasedWorkspace(named: "Workspace")
        defer { removeItemIfPresent(at: cleanupRootURL) }

        let nestedFolderURL = workspaceURL.appending(path: "Projects").appending(path: "Downward")
        try FileManager.default.createDirectory(
            at: nestedFolderURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        _ = try makeTemporaryFile(
            in: nestedFolderURL,
            named: "README.md",
            contents: "# Downward\n\nSnapshot-backed open."
        )

        let snapshot = try LiveWorkspaceEnumerator().makeSnapshot(
            rootURL: workspaceURL,
            displayName: "Workspace"
        )
        let enumeratedFileURL = try XCTUnwrap(
            snapshot.fileURL(forRelativePath: "Projects/Downward/README.md")
        )
        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())

        let document = try await manager.openDocument(
            at: enumeratedFileURL,
            in: aliasedWorkspaceURL
        )

        XCTAssertEqual(document.relativePath, "Projects/Downward/README.md")
        XCTAssertEqual(document.url.lastPathComponent, "README.md")
    }

    @MainActor
    func testOpenDocumentRejectsSymbolicLinkPointingOutsideWorkspace() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        let externalURL = try makeTemporaryDirectory(named: "External")
        defer { removeItemIfPresent(at: workspaceURL) }
        defer { removeItemIfPresent(at: externalURL) }

        let externalFileURL = try makeTemporaryFile(
            in: externalURL,
            named: "Escaped.md",
            contents: "# Escaped\n\nOutside the workspace."
        )
        let symbolicLinkURL = workspaceURL.appending(path: "Escaped.md")
        try FileManager.default.createSymbolicLink(
            at: symbolicLinkURL,
            withDestinationURL: externalFileURL
        )

        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())

        do {
            _ = try await manager.openDocument(at: symbolicLinkURL, in: workspaceURL)
            XCTFail("Expected escaped symbolic link open to throw.")
        } catch let error as AppError {
            guard case let .documentUnavailable(name) = error else {
                return XCTFail("Expected documentUnavailable for escaped symbolic link.")
            }

            XCTAssertEqual(name, "Escaped.md")
        }
    }

    @MainActor
    func testOpenDocumentAtRelativePathRejectsSymbolicLinkPointingOutsideWorkspace() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        let externalURL = try makeTemporaryDirectory(named: "External")
        defer { removeItemIfPresent(at: workspaceURL) }
        defer { removeItemIfPresent(at: externalURL) }

        let externalFileURL = try makeTemporaryFile(
            in: externalURL,
            named: "Escaped.md",
            contents: "# Escaped\n\nOutside the workspace."
        )
        let symbolicLinkURL = workspaceURL.appending(path: "Escaped.md")
        try FileManager.default.createSymbolicLink(
            at: symbolicLinkURL,
            withDestinationURL: externalFileURL
        )

        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())

        do {
            _ = try await manager.openDocument(atRelativePath: "Escaped.md", in: workspaceURL)
            XCTFail("Expected escaped symbolic link open to throw.")
        } catch let error as AppError {
            guard case let .documentUnavailable(name) = error else {
                return XCTFail("Expected documentUnavailable for escaped symbolic link.")
            }

            XCTAssertEqual(name, "Escaped.md")
        }
    }

    @MainActor
    func testOpenDocumentAtRelativePathRejectsEscapingDescendantComponents() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())

        do {
            _ = try await manager.openDocument(
                atRelativePath: "../Escaped.md",
                in: workspaceURL
            )
            XCTFail("Expected escaping relative path open to throw.")
        } catch let error as AppError {
            guard case let .documentUnavailable(name) = error else {
                return XCTFail("Expected documentUnavailable for escaped relative path.")
            }

            XCTAssertEqual(name, "Escaped.md")
        }
    }

    @MainActor
    func testCancelledOpenDocumentPropagatesCancellationIntoStructuredRead() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let fileURL = try makeTemporaryFile(
            in: workspaceURL,
            named: "Entry.md",
            contents: "# Entry\n\nCancellable open."
        )
        let accessHandler = ScriptedDocumentSecurityAccessHandler(
            behaviors: [.delayedUntilCancellation]
        )
        let manager = LiveDocumentManager(securityScopedAccess: accessHandler)

        let openTask = Task {
            try await manager.openDocument(at: fileURL, in: workspaceURL)
        }

        try await Task.sleep(for: .milliseconds(30))
        openTask.cancel()

        do {
            _ = try await openTask.value
            XCTFail("Expected cancelled open to throw CancellationError.")
        } catch is CancellationError {
            XCTAssertEqual(accessHandler.cancelledAccessCount, 1)
            XCTAssertEqual(accessHandler.performedOperationCount, 0)
        }
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
    func testCancelledRevalidatePropagatesCancellationIntoStructuredRead() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let fileURL = try makeTemporaryFile(
            in: workspaceURL,
            named: "Entry.md",
            contents: "# Entry\n\nOriginal text."
        )
        let accessHandler = ScriptedDocumentSecurityAccessHandler(
            behaviors: [.immediate, .delayedUntilCancellation]
        )
        let manager = LiveDocumentManager(securityScopedAccess: accessHandler)
        let document = try await manager.openDocument(at: fileURL, in: workspaceURL)

        let revalidationTask = Task {
            try await manager.revalidateDocument(document)
        }

        try await Task.sleep(for: .milliseconds(30))
        revalidationTask.cancel()

        do {
            _ = try await revalidationTask.value
            XCTFail("Expected cancelled revalidation to throw CancellationError.")
        } catch is CancellationError {
            XCTAssertEqual(accessHandler.cancelledAccessCount, 1)
            XCTAssertEqual(accessHandler.performedOperationCount, 1)
        }
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
    func testSuccessfulSaveLoadedVersionMatchesWrittenUTF8Bytes() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let fileURL = try makeTemporaryFile(
            in: workspaceURL,
            named: "Saved.md",
            contents: "# Entry\n\nOriginal text."
        )

        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())
        var document = try await manager.openDocument(at: fileURL, in: workspaceURL)
        document.text = "# Entry\n\nCafe 😀\nLine two."
        document.isDirty = true
        document.saveState = .unsaved

        let savedDocument = try await manager.saveDocument(document, overwriteConflict: false)
        let writtenData = try Data(contentsOf: fileURL)

        XCTAssertEqual(savedDocument.loadedVersion.fileSize, writtenData.count)
        XCTAssertEqual(savedDocument.loadedVersion.contentDigest, expectedDigest(for: writtenData))
        XCTAssertEqual(savedDocument.text, String(decoding: writtenData, as: UTF8.self))
    }

    @MainActor
    func testLargeFileOpenAndSaveLoadedVersionMatchesBytes() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        let originalContents = String(repeating: "Alpha beta gamma delta.\n", count: 12_000)
        let updatedContents = String(repeating: "Updated line with unicode 😀.\n", count: 12_000)
        let fileURL = try makeTemporaryFile(
            in: workspaceURL,
            named: "Large.md",
            contents: originalContents
        )
        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())

        let openedDocument = try await manager.openDocument(at: fileURL, in: workspaceURL)
        XCTAssertEqual(openedDocument.loadedVersion.fileSize, Data(originalContents.utf8).count)
        XCTAssertEqual(
            openedDocument.loadedVersion.contentDigest,
            expectedDigest(for: Data(originalContents.utf8))
        )

        var documentToSave = openedDocument
        documentToSave.text = updatedContents
        documentToSave.isDirty = true
        documentToSave.saveState = .unsaved

        let savedDocument = try await manager.saveDocument(documentToSave, overwriteConflict: false)
        let writtenData = try Data(contentsOf: fileURL)

        XCTAssertEqual(savedDocument.loadedVersion.fileSize, writtenData.count)
        XCTAssertEqual(savedDocument.loadedVersion.contentDigest, expectedDigest(for: writtenData))
        XCTAssertEqual(writtenData.count, Data(updatedContents.utf8).count)
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
    func testSaveRejectsSymbolicLinkPointingOutsideWorkspace() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        let externalURL = try makeTemporaryDirectory(named: "External")
        defer { removeItemIfPresent(at: workspaceURL) }
        defer { removeItemIfPresent(at: externalURL) }

        let externalFileURL = try makeTemporaryFile(
            in: externalURL,
            named: "Escaped.md",
            contents: "# Entry\n\nOutside the workspace."
        )
        let symbolicLinkURL = workspaceURL.appending(path: "Escaped.md")
        try FileManager.default.createSymbolicLink(
            at: symbolicLinkURL,
            withDestinationURL: externalFileURL
        )

        let manager = LiveDocumentManager(securityScopedAccess: FakeDocumentSecurityAccessHandler())
        let document = OpenDocument(
            url: symbolicLinkURL,
            workspaceRootURL: workspaceURL,
            relativePath: "Escaped.md",
            displayName: "Escaped.md",
            text: "# Entry\n\nUnsafe save attempt.",
            loadedVersion: DocumentVersion(
                contentModificationDate: nil,
                fileSize: 0,
                contentDigest: "stale"
            ),
            isDirty: true,
            saveState: .unsaved,
            conflictState: .none
        )

        do {
            _ = try await manager.saveDocument(document, overwriteConflict: false)
            XCTFail("Expected escaped symbolic link save to throw.")
        } catch let error as AppError {
            guard case let .documentUnavailable(name) = error else {
                return XCTFail("Expected documentUnavailable for escaped symbolic link save.")
            }

            XCTAssertEqual(name, "Escaped.md")
        }

        XCTAssertEqual(
            try String(contentsOf: externalFileURL, encoding: .utf8),
            "# Entry\n\nOutside the workspace."
        )
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

    @MainActor
    func testPrimaryObservationDoesNotStartFallbackPollingWhenPresenterObservationIsEnabled() async throws {
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
            filePresenterEnabled: true,
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
            for await _ in stream {}
        }

        try await Task.sleep(for: .milliseconds(140))

        let pollCount = await recorder.pollCount
        XCTAssertEqual(pollCount, 0)

        observationTask.cancel()
        withExtendedLifetime(stream) {}
    }

    @MainActor
    func testObservationModeDiagnosticsReportPrimaryPresenterForOrdinaryLocalFile() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        _ = try makeTemporaryFile(
            in: workspaceURL,
            named: "Observed.md",
            contents: "# Entry\n\nStable text."
        )
        let recorder = ObservationModeRecorder()
        let session = PlainTextDocumentSession(
            relativePath: "Observed.md",
            workspaceRootURL: workspaceURL,
            securityScopedAccess: FakeDocumentSecurityAccessHandler(),
            filePresenterEnabled: true,
            onObservationModeActivated: { mode in
                Task {
                    await recorder.record(mode)
                }
            }
        )

        let stream = try await session.observeChanges()
        let observationTask = Task {
            for await _ in stream {}
        }

        try await waitUntil(timeout: .milliseconds(120)) {
            await recorder.mode == .filePresenterOnly
        }

        observationTask.cancel()
        withExtendedLifetime(stream) {}
    }

    @MainActor
    func testFallbackObservationStartsWhenPolicyMarksPrimaryObservationInsufficient() async throws {
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
            filePresenterEnabled: true,
            observationFallbackPolicy: .always,
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
            for await _ in stream {}
        }

        try await waitUntil(timeout: .milliseconds(120)) {
            await recorder.pollCount > 0
        }

        observationTask.cancel()
        withExtendedLifetime(stream) {}
    }

    @MainActor
    func testObservationModeDiagnosticsReportDegradedFallbackWhenPrimaryObservationIsUnavailable() async throws {
        let workspaceURL = try makeTemporaryDirectory(named: "Workspace")
        defer { removeItemIfPresent(at: workspaceURL) }

        _ = try makeTemporaryFile(
            in: workspaceURL,
            named: "Observed.md",
            contents: "# Entry\n\nStable text."
        )
        let recorder = ObservationModeRecorder()
        let session = PlainTextDocumentSession(
            relativePath: "Observed.md",
            workspaceRootURL: workspaceURL,
            securityScopedAccess: FakeDocumentSecurityAccessHandler(),
            filePresenterEnabled: false,
            observationFallbackSchedule: .init(
                intervals: [.milliseconds(20), .milliseconds(40), .milliseconds(80)]
            ),
            onObservationModeActivated: { mode in
                Task {
                    await recorder.record(mode)
                }
            }
        )

        let stream = try await session.observeChanges()
        let observationTask = Task {
            for await _ in stream {}
        }

        try await waitUntil(timeout: .milliseconds(120)) {
            await recorder.mode == .fallbackPollingOnly
        }

        observationTask.cancel()
        withExtendedLifetime(stream) {}
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

    private func expectedDigest(for data: Data) -> String {
        SHA256.hash(data: data).compactMap { byte in
            String(format: "%02x", byte)
        }.joined()
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

private actor ObservationModeRecorder {
    private(set) var mode: PlainTextDocumentSession.ObservationMode?

    func record(_ mode: PlainTextDocumentSession.ObservationMode) {
        self.mode = mode
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
        guard let descendantURL = WorkspaceRelativePath.resolveCandidate(
            relativePath,
            within: workspaceRootURL
        ) else {
            throw AppError.documentUnavailable(
                name: relativePath.split(separator: "/").last.map(String.init) ?? "Document"
            )
        }

        return try operation(descendantURL)
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
        guard let descendantURL = WorkspaceRelativePath.resolveCandidate(
            relativePath,
            within: workspaceRootURL
        ) else {
            throw AppError.documentUnavailable(
                name: relativePath.split(separator: "/").last.map(String.init) ?? "Document"
            )
        }

        return try operation(descendantURL)
    }
}

private final class ScriptedDocumentSecurityAccessHandler: @unchecked Sendable, SecurityScopedAccessHandling {
    enum Behavior {
        case immediate
        case delayedUntilCancellation
    }

    private let lock = NSLock()
    private var behaviors: [Behavior]
    private var performedOperations = 0
    private var cancelledAccesses = 0

    init(behaviors: [Behavior]) {
        self.behaviors = behaviors
    }

    var performedOperationCount: Int {
        lock.withLock { performedOperations }
    }

    var cancelledAccessCount: Int {
        lock.withLock { cancelledAccesses }
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
        try operation(url)
    }

    func withAccess<Value>(
        toDescendantAt relativePath: String,
        within workspaceRootURL: URL,
        operation: (URL) throws -> Value
    ) throws -> Value {
        let behavior = lock.withLock {
            behaviors.isEmpty ? Behavior.immediate : behaviors.removeFirst()
        }

        switch behavior {
        case .immediate:
            break
        case .delayedUntilCancellation:
            for _ in 0..<200 {
                if Task.isCancelled {
                    lock.withLock {
                        cancelledAccesses += 1
                    }
                    throw CancellationError()
                }

                Thread.sleep(forTimeInterval: 0.005)
            }
        }

        guard let descendantURL = WorkspaceRelativePath.resolveCandidate(
            relativePath,
            within: workspaceRootURL
        ) else {
            throw AppError.documentUnavailable(
                name: relativePath.split(separator: "/").last.map(String.init) ?? "Document"
            )
        }

        lock.withLock {
            performedOperations += 1
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

private func makeAliasedWorkspace(
    named name: String
) throws -> (workspaceURL: URL, aliasedWorkspaceURL: URL, cleanupRootURL: URL) {
    let fileManager = FileManager.default
    let cleanupRootURL = fileManager.temporaryDirectory
        .appending(path: "DocumentManagerTests")
        .appending(path: UUID().uuidString)
    let realParentURL = cleanupRootURL.appending(path: "RealParent")
    let aliasParentURL = cleanupRootURL.appending(path: "AliasParent")
    let workspaceURL = realParentURL.appending(path: name)

    try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    try fileManager.createSymbolicLink(at: aliasParentURL, withDestinationURL: realParentURL)

    return (
        workspaceURL: workspaceURL,
        aliasedWorkspaceURL: aliasParentURL.appending(path: name),
        cleanupRootURL: cleanupRootURL
    )
}
