import Foundation
import XCTest
@testable import Downward

final class WorkspaceRelativePathTests: XCTestCase {
    func testResolveExistingRejectsAbsolutePathRoutes() throws {
        let rootURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: rootURL) }

        let fileURL = try createFile(named: "Draft.md", in: rootURL)

        XCTAssertNil(
            WorkspaceRelativePath.resolveExisting(fileURL.path, within: rootURL)
        )
    }

    func testResolveCandidateRejectsParentTraversalComponents() throws {
        let rootURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: rootURL) }

        XCTAssertNil(
            WorkspaceRelativePath.resolveCandidate("../Escaped.md", within: rootURL)
        )
        XCTAssertNil(
            WorkspaceRelativePath.resolveCandidate("Notes/../../Escaped.md", within: rootURL)
        )
    }

    func testResolveCandidateRejectsPercentEncodedPathControlComponents() throws {
        let rootURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: rootURL) }

        _ = try createDirectory(named: "%2E%2E", in: rootURL)

        XCTAssertNil(
            WorkspaceRelativePath.resolveCandidate("%2E%2E/Escaped.md", within: rootURL)
        )
        XCTAssertNil(
            WorkspaceRelativePath.resolveCandidate("Folder%2FEscaped.md", within: rootURL)
        )
    }

    func testMakeRejectsSymlinkDescendantPointingOutsideWorkspace() throws {
        let rootURL = try makeTemporaryWorkspace()
        let externalURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: rootURL) }
        defer { removeItemIfPresent(at: externalURL) }

        let externalFileURL = try createFile(named: "Escaped.md", in: externalURL)
        let symlinkURL = rootURL.appending(path: "Escaped.md")
        try FileManager.default.createSymbolicLink(
            at: symlinkURL,
            withDestinationURL: externalFileURL
        )

        XCTAssertNil(
            WorkspaceRelativePath.make(for: symlinkURL, within: rootURL)
        )
        XCTAssertNil(
            WorkspaceRelativePath.resolveExisting("Escaped.md", within: rootURL)
        )
    }

    func testUnicodeNamesRemainWorkspaceRelativeWhenTheyAreRealDescendants() throws {
        let rootURL = try makeTemporaryWorkspace()
        defer { removeItemIfPresent(at: rootURL) }

        let fileURL = try createFile(named: "Cafe\u{301}.md", in: rootURL)

        XCTAssertEqual(
            WorkspaceRelativePath.make(for: fileURL, within: rootURL),
            "Cafe\u{301}.md"
        )
        XCTAssertEqual(
            WorkspaceRelativePath.resolveExisting("Cafe\u{301}.md", within: rootURL),
            fileURL
        )
    }

    private func makeTemporaryWorkspace() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "WorkspaceRelativePathTests")
            .appending(path: UUID().uuidString)

        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        return rootURL
    }

    @discardableResult
    private func createDirectory(named name: String, in parentURL: URL) throws -> URL {
        let directoryURL = parentURL.appending(path: name)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
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
}
