import Foundation
import XCTest
@testable import Downward

final class WorkspaceDeleteConfirmationPresentationTests: XCTestCase {
    func testFileDeleteCopyDescribesPermanentFilesDeletion() {
        let node = file(named: "Draft.md")

        let presentation = WorkspaceDeleteConfirmationPresentation(node: node)

        XCTAssertEqual(presentation.title, "Permanently Delete File?")
        XCTAssertEqual(presentation.destructiveButtonTitle, "Permanently Delete File")
        XCTAssertFalse(presentation.requiresStrongerConfirmation)
        XCTAssertTrue(presentation.message.contains("Draft.md"))
        XCTAssertTrue(presentation.message.contains("permanently deleted from Files and the underlying workspace"))
        XCTAssertTrue(presentation.message.contains("cannot be undone"))
        XCTAssertTrue(presentation.deleteActionAccessibilityHint.contains("Permanently deletes this file"))
    }

    func testEmptyFolderDeleteCopyDescribesPermanentFolderDeletion() {
        let node = folder(named: "Empty", children: [])

        let presentation = WorkspaceDeleteConfirmationPresentation(node: node)

        XCTAssertEqual(presentation.title, "Permanently Delete Folder?")
        XCTAssertEqual(presentation.destructiveButtonTitle, "Permanently Delete Folder")
        XCTAssertFalse(presentation.requiresStrongerConfirmation)
        XCTAssertTrue(presentation.message.contains("Empty"))
        XCTAssertTrue(presentation.message.contains("permanently deleted from Files and the underlying workspace"))
        XCTAssertTrue(presentation.deleteActionAccessibilityHint.contains("Permanently deletes this folder"))
    }

    func testNonEmptyFolderDeleteCopyHasStrongerContentsProtection() {
        let node = folder(
            named: "Archive",
            children: [
                file(named: "Old.md")
            ]
        )

        let presentation = WorkspaceDeleteConfirmationPresentation(node: node)

        XCTAssertEqual(presentation.title, "Permanently Delete Folder and Contents?")
        XCTAssertEqual(presentation.destructiveButtonTitle, "Permanently Delete Folder and Contents")
        XCTAssertTrue(presentation.requiresStrongerConfirmation)
        XCTAssertTrue(presentation.message.contains("Archive and all of its contents"))
        XCTAssertTrue(presentation.message.contains("permanently deleted from Files and the underlying workspace"))
        XCTAssertTrue(presentation.deleteActionAccessibilityHint.contains("all of its contents"))
    }

    func testFolderWithOnlyFilteredFilesystemItemsUsesStrongerContentsProtection() {
        let node = folder(
            named: "Assets",
            children: [],
            containsAnyFilesystemItems: true
        )

        let presentation = WorkspaceDeleteConfirmationPresentation(node: node)

        XCTAssertEqual(presentation.title, "Permanently Delete Folder and Contents?")
        XCTAssertEqual(presentation.destructiveButtonTitle, "Permanently Delete Folder and Contents")
        XCTAssertTrue(presentation.requiresStrongerConfirmation)
        XCTAssertTrue(presentation.message.contains("Assets and all of its contents"))
    }

    private func file(named name: String) -> WorkspaceNode {
        .file(
            .init(
                url: URL(filePath: "/Workspace/\(name)"),
                displayName: name,
                subtitle: nil
            )
        )
    }

    private func folder(
        named name: String,
        children: [WorkspaceNode],
        containsAnyFilesystemItems: Bool? = nil
    ) -> WorkspaceNode {
        .folder(
            .init(
                url: URL(filePath: "/Workspace/\(name)"),
                displayName: name,
                children: children,
                containsAnyFilesystemItems: containsAnyFilesystemItems
            )
        )
    }
}
