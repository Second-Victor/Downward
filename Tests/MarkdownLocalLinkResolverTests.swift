import XCTest
@testable import Downward

@MainActor
final class MarkdownLocalLinkResolverTests: XCTestCase {
    func testResolvesWorkspaceRelativeMarkdownLinkFromRootDocument() {
        XCTAssertEqual(
            MarkdownLocalLinkResolver.resolve(
                destination: "References/README.md",
                from: "Inbox.md",
                in: PreviewSampleData.nestedWorkspace
            ),
            .target(
                relativePath: "References/README.md",
                url: PreviewSampleData.readmeDocumentURL
            )
        )
    }

    func testResolvesSiblingMarkdownLinkFromNestedDocument() {
        XCTAssertEqual(
            MarkdownLocalLinkResolver.resolve(
                destination: "./Ideas.markdown",
                from: "Journal/2026/2026-04-13.md",
                in: PreviewSampleData.nestedWorkspace
            ),
            .target(
                relativePath: "Journal/2026/Ideas.markdown",
                url: PreviewSampleData.ideasDocumentURL
            )
        )
    }

    func testResolvesParentDirectoryMarkdownLinkFromNestedDocument() {
        XCTAssertEqual(
            MarkdownLocalLinkResolver.resolve(
                destination: "../../Inbox.md",
                from: "Journal/2026/2026-04-13.md",
                in: PreviewSampleData.nestedWorkspace
            ),
            .target(
                relativePath: "Inbox.md",
                url: PreviewSampleData.inboxDocumentURL
            )
        )
    }

    func testResolvesURLDecodedMarkdownLinkWithAnchor() {
        let rootURL = URL(filePath: "/preview/Workspace With Spaces")
        let noteURL = rootURL.appending(path: "Notes/Today Plan.md")
        let snapshot = WorkspaceSnapshot(
            rootURL: rootURL,
            displayName: "Workspace With Spaces",
            rootNodes: [
                .folder(
                    .init(
                        url: rootURL.appending(path: "Notes"),
                        displayName: "Notes",
                        children: [
                            .file(
                                .init(
                                    url: noteURL,
                                    displayName: "Today Plan.md",
                                    subtitle: nil
                                )
                            ),
                        ]
                    )
                ),
                .file(
                    .init(
                        url: rootURL.appending(path: "Inbox.md"),
                        displayName: "Inbox.md",
                        subtitle: nil
                    )
                ),
            ],
            lastUpdated: PreviewSampleData.previewDate
        )

        XCTAssertEqual(
            MarkdownLocalLinkResolver.resolve(
                destination: "Notes/Today%20Plan.md#tasks",
                from: "Inbox.md",
                in: snapshot
            ),
            .target(relativePath: "Notes/Today Plan.md", url: noteURL)
        )
    }

    func testAnchorOnlyLinkDoesNotRequireFileResolution() {
        XCTAssertEqual(
            MarkdownLocalLinkResolver.resolve(
                destination: "#overview",
                from: "Inbox.md",
                in: PreviewSampleData.nestedWorkspace
            ),
            .anchorOnly
        )
    }

    func testMissingSupportedMarkdownLinkReportsMissingPath() {
        XCTAssertEqual(
            MarkdownLocalLinkResolver.resolve(
                destination: "References/Missing.md",
                from: "Inbox.md",
                in: PreviewSampleData.nestedWorkspace
            ),
            .missing(displayPath: "References/Missing.md")
        )
    }

    func testRejectsLinksThatEscapeWorkspaceRoot() {
        XCTAssertEqual(
            MarkdownLocalLinkResolver.resolve(
                destination: "../Outside.md",
                from: "Inbox.md",
                in: PreviewSampleData.nestedWorkspace
            ),
            .unsupported(displayPath: "../Outside.md")
        )
    }

    func testRejectsAbsoluteFileAndWebLinksForLocalResolution() {
        XCTAssertEqual(
            MarkdownLocalLinkResolver.resolve(
                destination: "/absolute.md",
                from: "Inbox.md",
                in: PreviewSampleData.nestedWorkspace
            ),
            .unsupported(displayPath: "/absolute.md")
        )
        XCTAssertEqual(
            MarkdownLocalLinkResolver.resolve(
                destination: "file:///tmp/absolute.md",
                from: "Inbox.md",
                in: PreviewSampleData.nestedWorkspace
            ),
            .unsupported(displayPath: "file:///tmp/absolute.md")
        )
        XCTAssertEqual(
            MarkdownLocalLinkResolver.resolve(
                destination: "https://example.com/readme.md",
                from: "Inbox.md",
                in: PreviewSampleData.nestedWorkspace
            ),
            .unsupported(displayPath: "https://example.com/readme.md")
        )
    }

    func testRejectsUnsupportedLocalFileTypesAndQueryStrings() {
        XCTAssertEqual(
            MarkdownLocalLinkResolver.resolve(
                destination: "References/image.png",
                from: "Inbox.md",
                in: PreviewSampleData.nestedWorkspace
            ),
            .unsupported(displayPath: "References/image.png")
        )
        XCTAssertEqual(
            MarkdownLocalLinkResolver.resolve(
                destination: "References/README.md?download=1",
                from: "Inbox.md",
                in: PreviewSampleData.nestedWorkspace
            ),
            .unsupported(displayPath: "References/README.md?download=1")
        )
    }
}
