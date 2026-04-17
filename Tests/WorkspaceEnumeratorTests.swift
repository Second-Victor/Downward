import Foundation
import XCTest
@testable import Downward

final class WorkspaceEnumeratorTests: XCTestCase {
    func testEnumeratorIncludesOnlySupportedFiles() throws {
        let rootURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: rootURL) }

        try createFile(named: "Notes.md", in: rootURL)
        try createFile(named: "Ideas.markdown", in: rootURL)
        try createFile(named: "Scratch.txt", in: rootURL)
        try createFile(named: "Image.png", in: rootURL)

        let snapshot = try LiveWorkspaceEnumerator().makeSnapshot(
            rootURL: rootURL,
            displayName: "Workspace"
        )

        XCTAssertEqual(snapshot.rootNodes.map(\.displayName), ["Ideas.markdown", "Notes.md", "Scratch.txt"])
    }

    func testEnumeratorSortsFoldersBeforeFilesAlphabetically() throws {
        let rootURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: rootURL) }

        let zetaURL = try createDirectory(named: "Zeta", in: rootURL)
        let alphaURL = try createDirectory(named: "Alpha", in: rootURL)
        try createFile(named: "inside.md", in: zetaURL)
        try createFile(named: "inside.md", in: alphaURL)
        try createFile(named: "z-file.md", in: rootURL)
        try createFile(named: "a-file.md", in: rootURL)

        let snapshot = try LiveWorkspaceEnumerator().makeSnapshot(
            rootURL: rootURL,
            displayName: "Workspace"
        )

        XCTAssertEqual(snapshot.rootNodes.map(\.displayName), ["Alpha", "Zeta", "a-file.md", "z-file.md"])
    }

    func testEnumeratorBuildsNestedWorkspaceTree() throws {
        let rootURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: rootURL) }

        let journalURL = try createDirectory(named: "Journal", in: rootURL)
        let yearURL = try createDirectory(named: "2026", in: journalURL)
        try createFile(named: "2026-04-13.md", in: yearURL)
        try createFile(named: "Inbox.md", in: rootURL)

        let snapshot = try LiveWorkspaceEnumerator().makeSnapshot(
            rootURL: rootURL,
            displayName: "Workspace"
        )

        guard case let .folder(journalFolder) = snapshot.rootNodes.first else {
            return XCTFail("Expected the first root node to be the Journal folder.")
        }

        XCTAssertEqual(snapshot.rootNodes.map(\.displayName), ["Journal", "Inbox.md"])
        XCTAssertEqual(journalFolder.children.count, 1)

        guard case let .folder(yearFolder) = journalFolder.children.first else {
            return XCTFail("Expected the Journal folder to contain the 2026 folder.")
        }

        XCTAssertEqual(yearFolder.displayName, "2026")
        XCTAssertEqual(yearFolder.children.map(\.displayName), ["2026-04-13.md"])
    }

    func testWorkspaceRelativePathAcceptsEnumeratedDescendantAgainstEquivalentWorkspaceRootNormalization() throws {
        let (rootURL, aliasedRootURL, cleanupRootURL) = try makeAliasedWorkspace(named: "Workspace")
        defer { removeItemIfPresent(at: cleanupRootURL) }

        let journalURL = try createDirectory(named: "Journal", in: rootURL)
        let yearURL = try createDirectory(named: "2026", in: journalURL)
        try createFile(named: "2026-04-13.md", in: yearURL)

        let snapshot = try LiveWorkspaceEnumerator().makeSnapshot(
            rootURL: rootURL,
            displayName: "Workspace"
        )
        let fileURL = try XCTUnwrap(
            snapshot.fileURL(forRelativePath: "Journal/2026/2026-04-13.md")
        )

        XCTAssertEqual(
            WorkspaceRelativePath.make(for: fileURL, within: aliasedRootURL),
            "Journal/2026/2026-04-13.md"
        )
    }

    func testEnumeratorIncludesEmptyFoldersAndFoldersWithoutSupportedFiles() throws {
        let rootURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: rootURL) }

        let supportedFolderURL = try createDirectory(named: "Supported", in: rootURL)
        try createFile(named: "Keep.md", in: supportedFolderURL)

        let deepFolderURL = try createDirectory(named: "Deep", in: rootURL)
        let nestedFolderURL = try createDirectory(named: "Nested", in: deepFolderURL)
        try createFile(named: "Retained.markdown", in: nestedFolderURL)

        let unsupportedFolderURL = try createDirectory(named: "Unsupported", in: rootURL)
        try createFile(named: "Ignore.png", in: unsupportedFolderURL)

        let emptyFolderURL = try createDirectory(named: "Empty", in: rootURL)
        let onlyDirectoriesURL = try createDirectory(named: "OnlyDirectories", in: emptyFolderURL)
        try createDirectory(named: "NestedEmpty", in: onlyDirectoriesURL)

        let snapshot = try LiveWorkspaceEnumerator().makeSnapshot(
            rootURL: rootURL,
            displayName: "Workspace"
        )

        XCTAssertEqual(snapshot.rootNodes.map(\.displayName), ["Deep", "Empty", "Supported", "Unsupported"])

        guard case let .folder(emptyFolder) = snapshot.rootNodes[1] else {
            return XCTFail("Expected Empty to be represented as a folder.")
        }

        XCTAssertEqual(emptyFolder.children.map(\.displayName), ["OnlyDirectories"])

        guard case let .folder(onlyDirectoriesFolder) = emptyFolder.children.first else {
            return XCTFail("Expected OnlyDirectories to be represented as a nested empty folder.")
        }

        XCTAssertEqual(onlyDirectoriesFolder.children.map(\.displayName), ["NestedEmpty"])

        guard case let .folder(unsupportedFolder) = snapshot.rootNodes[3] else {
            return XCTFail("Expected Unsupported to be represented as a folder.")
        }

        XCTAssertTrue(unsupportedFolder.children.isEmpty)
    }

    func testEnumeratorSkipsUnreadableChildFolderAndKeepsReadableSiblings() throws {
        let rootURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: rootURL) }

        let readableFolderURL = try createDirectory(named: "Readable", in: rootURL)
        try createFile(named: "Keep.md", in: readableFolderURL)

        let unreadableFolderURL = try createDirectory(named: "Unreadable", in: rootURL)
        try createFile(named: "Hidden.md", in: unreadableFolderURL)
        defer { restoreReadablePermissions(at: unreadableFolderURL) }
        try makeUnreadable(at: unreadableFolderURL)

        let snapshot = try LiveWorkspaceEnumerator().makeSnapshot(
            rootURL: rootURL,
            displayName: "Workspace"
        )

        XCTAssertEqual(snapshot.rootNodes.map(\.displayName), ["Readable"])

        guard case let .folder(readableFolder) = snapshot.rootNodes.first else {
            return XCTFail("Expected Readable to remain in the partial snapshot.")
        }

        XCTAssertEqual(readableFolder.children.map(\.displayName), ["Keep.md"])
    }

    func testEnumeratorReportsPartialSkipDiagnosticsForUnreadableDescendants() throws {
        let rootURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: rootURL) }

        _ = try createDirectory(named: "Readable", in: rootURL)
        let unreadableFolderURL = try createDirectory(named: "Unreadable", in: rootURL)
        try createFile(named: "Hidden.md", in: unreadableFolderURL)
        defer { restoreReadablePermissions(at: unreadableFolderURL) }
        try makeUnreadable(at: unreadableFolderURL)

        let diagnosticsBox = WorkspaceEnumerationDiagnosticsBox()
        _ = try LiveWorkspaceEnumerator(
            onDiagnostics: { diagnostics in
                diagnosticsBox.set(diagnostics)
            }
        ).makeSnapshot(
            rootURL: rootURL,
            displayName: "Workspace"
        )

        XCTAssertEqual(diagnosticsBox.value?.skippedDescendantPaths, ["Unreadable"])
    }

    func testEnumeratorSkipsHiddenSubtrees() throws {
        let rootURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: rootURL) }

        let visibleFolderURL = try createDirectory(named: "Visible", in: rootURL)
        try createFile(named: "Keep.md", in: visibleFolderURL)

        let hiddenFolderURL = try createDirectory(named: ".ProviderMetadata", in: rootURL)
        try createFile(named: "Ignored.md", in: hiddenFolderURL)
        try createFile(named: ".Secrets.md", in: rootURL)

        let snapshot = try LiveWorkspaceEnumerator().makeSnapshot(
            rootURL: rootURL,
            displayName: "Workspace"
        )

        XCTAssertEqual(snapshot.rootNodes.map(\.displayName), ["Visible"])

        guard case let .folder(visibleFolder) = snapshot.rootNodes.first else {
            return XCTFail("Expected Visible to remain in the snapshot.")
        }

        XCTAssertEqual(visibleFolder.children.map(\.displayName), ["Keep.md"])
    }

    func testEnumeratorSkipsSymbolicLinkFilePointingOutsideWorkspace() throws {
        let rootURL = try makeTemporaryWorkspace()
        let externalURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: rootURL) }
        defer { removeItemIfPresent(at: externalURL) }

        try createFile(named: "Keep.md", in: rootURL)
        let externalFileURL = try createFile(named: "Escaped.md", in: externalURL)
        try createSymbolicLink(
            named: "Escaped.md",
            in: rootURL,
            destinationURL: externalFileURL
        )

        let snapshot = try LiveWorkspaceEnumerator().makeSnapshot(
            rootURL: rootURL,
            displayName: "Workspace"
        )

        XCTAssertEqual(snapshot.rootNodes.map(\.displayName), ["Keep.md"])
    }

    func testEnumeratorSkipsSymbolicLinkFolderPointingOutsideWorkspace() throws {
        let rootURL = try makeTemporaryWorkspace()
        let externalURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: rootURL) }
        defer { removeItemIfPresent(at: externalURL) }

        let readableFolderURL = try createDirectory(named: "Readable", in: rootURL)
        try createFile(named: "Keep.md", in: readableFolderURL)

        let externalFolderURL = try createDirectory(named: "EscapedFolder", in: externalURL)
        try createFile(named: "Outside.md", in: externalFolderURL)
        try createSymbolicLink(
            named: "EscapedFolder",
            in: rootURL,
            destinationURL: externalFolderURL
        )

        let snapshot = try LiveWorkspaceEnumerator().makeSnapshot(
            rootURL: rootURL,
            displayName: "Workspace"
        )

        XCTAssertEqual(snapshot.rootNodes.map(\.displayName), ["Readable"])
    }

    func testEnumeratorFailsWhenWorkspaceRootIsUnreadable() throws {
        let rootURL = try makeTemporaryWorkspace()
        defer { restoreReadablePermissions(at: rootURL) }
        defer { removeItemIfPresent(at: rootURL) }

        try createFile(named: "Keep.md", in: rootURL)
        try makeUnreadable(at: rootURL)

        XCTAssertThrowsError(
            try LiveWorkspaceEnumerator().makeSnapshot(
                rootURL: rootURL,
                displayName: "Workspace"
            )
        )
    }

    private func makeTemporaryWorkspace() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "WorkspaceEnumeratorTests")
            .appending(path: UUID().uuidString)

        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return rootURL
    }

    private func makeAliasedWorkspace(
        named name: String
    ) throws -> (workspaceURL: URL, aliasedWorkspaceURL: URL, cleanupRootURL: URL) {
        let fileManager = FileManager.default
        let cleanupRootURL = fileManager.temporaryDirectory
            .appending(path: "WorkspaceEnumeratorTests")
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

    @discardableResult
    private func createDirectory(named name: String, in parentURL: URL) throws -> URL {
        let directoryURL = parentURL.appending(path: name)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directoryURL
    }

    @discardableResult
    private func createFile(named name: String, in parentURL: URL) throws -> URL {
        let fileURL = parentURL.appending(path: name)
        try Data("sample".utf8).write(to: fileURL)
        return fileURL
    }

    private func removeItemIfPresent(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func createSymbolicLink(
        named name: String,
        in parentURL: URL,
        destinationURL: URL
    ) throws {
        try FileManager.default.createSymbolicLink(
            at: parentURL.appending(path: name),
            withDestinationURL: destinationURL
        )
    }

    private func makeUnreadable(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: url.path
        )
    }

    private func restoreReadablePermissions(at url: URL) {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
    }
}

private final class WorkspaceEnumerationDiagnosticsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var diagnostics: WorkspaceEnumerationDiagnostics?

    var value: WorkspaceEnumerationDiagnostics? {
        lock.withLock { diagnostics }
    }

    func set(_ diagnostics: WorkspaceEnumerationDiagnostics) {
        lock.withLock {
            self.diagnostics = diagnostics
        }
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
