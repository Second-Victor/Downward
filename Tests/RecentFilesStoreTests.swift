import XCTest
@testable import Downward

final class RecentFilesStoreTests: XCTestCase {
    @MainActor
    func testRecentFilesStoreInsertsMostRecentFirstAndDeduplicates() {
        let store = RecentFilesStore(initialItems: [])
        let openedAt = Date(timeIntervalSince1970: 10)
        let reopenedAt = Date(timeIntervalSince1970: 20)

        store.record(document: PreviewSampleData.cleanDocument, openedAt: openedAt)
        store.record(document: PreviewSampleData.dirtyDocument, openedAt: reopenedAt)
        store.record(document: PreviewSampleData.cleanDocument, openedAt: reopenedAt.addingTimeInterval(10))

        XCTAssertEqual(store.items.map(\.displayName), ["Inbox.md", "2026-04-13.md"])
        XCTAssertEqual(store.items.first?.relativePath, PreviewSampleData.cleanDocument.relativePath)
    }

    @MainActor
    func testRecentFilesStorePersistsAndReloadsItems() {
        let suiteName = "RecentFilesStoreTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let store = RecentFilesStore(userDefaults: userDefaults)
        store.record(document: PreviewSampleData.cleanDocument, openedAt: .init(timeIntervalSince1970: 100))
        store.record(document: PreviewSampleData.dirtyDocument, openedAt: .init(timeIntervalSince1970: 200))

        let reloadedStore = RecentFilesStore(userDefaults: userDefaults)

        XCTAssertEqual(reloadedStore.items.map(\.displayName), ["2026-04-13.md", "Inbox.md"])
        XCTAssertEqual(reloadedStore.items.map(\.relativePath), [
            PreviewSampleData.dirtyDocument.relativePath,
            PreviewSampleData.cleanDocument.relativePath,
        ])
    }

    @MainActor
    func testRecentFilesStorePrunesMissingItemsForCurrentWorkspace() {
        let store = RecentFilesStore(
            initialItems: [
                RecentFileItem(
                    workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                    relativePath: PreviewSampleData.cleanDocument.relativePath,
                    displayName: PreviewSampleData.cleanDocument.displayName,
                    lastOpenedAt: PreviewSampleData.previewDate
                ),
                RecentFileItem(
                    workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                    relativePath: "Missing.md",
                    displayName: "Missing.md",
                    lastOpenedAt: PreviewSampleData.previewDate.addingTimeInterval(-60)
                ),
                RecentFileItem(
                    workspaceRootPath: "/preview/OtherWorkspace",
                    relativePath: "Elsewhere.md",
                    displayName: "Elsewhere.md",
                    lastOpenedAt: PreviewSampleData.previewDate.addingTimeInterval(-120)
                ),
            ]
        )

        store.pruneInvalidItems(using: PreviewSampleData.nestedWorkspace)

        XCTAssertEqual(
            store.items.map(\.displayName),
            ["Inbox.md", "Elsewhere.md"]
        )
    }

    @MainActor
    func testRecentFilesStorePrunesUsingCanonicalRelativePathsInsteadOfDisplayNames() {
        let store = RecentFilesStore(
            initialItems: [
                RecentFileItem(
                    workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                    relativePath: "References/README.md",
                    displayName: "Localized README.md",
                    lastOpenedAt: PreviewSampleData.previewDate
                ),
                RecentFileItem(
                    workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                    relativePath: "Missing.md",
                    displayName: "Localized Missing.md",
                    lastOpenedAt: PreviewSampleData.previewDate.addingTimeInterval(-60)
                ),
            ]
        )

        let snapshot = WorkspaceSnapshot(
            rootURL: PreviewSampleData.workspaceRootURL,
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            rootNodes: [
                .folder(
                    .init(
                        url: PreviewSampleData.referencesURL,
                        displayName: "Localized References",
                        children: [
                            .file(
                                .init(
                                    url: PreviewSampleData.readmeDocumentURL,
                                    displayName: "Localized README.md",
                                    subtitle: "Project overview"
                                )
                            ),
                        ]
                    )
                ),
            ],
            lastUpdated: PreviewSampleData.previewDate
        )

        store.pruneInvalidItems(using: snapshot)

        XCTAssertEqual(store.items.map(\.relativePath), ["References/README.md"])
        XCTAssertEqual(store.items.map(\.displayName), ["Localized README.md"])
    }

    @MainActor
    func testRecentFilesStoreRenamesAndRemovesItemsSafely() {
        let store = RecentFilesStore(
            initialItems: [
                RecentFileItem(
                    workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                    relativePath: PreviewSampleData.cleanDocument.relativePath,
                    displayName: PreviewSampleData.cleanDocument.displayName,
                    lastOpenedAt: PreviewSampleData.previewDate
                ),
            ]
        )

        store.renameItem(
            workspaceRootURL: PreviewSampleData.workspaceRootURL,
            oldRelativePath: PreviewSampleData.cleanDocument.relativePath,
            newRelativePath: "Inbox Renamed.md",
            displayName: "Inbox Renamed.md"
        )

        XCTAssertEqual(store.items.first?.displayName, "Inbox Renamed.md")
        XCTAssertEqual(store.items.first?.relativePath, "Inbox Renamed.md")

        store.removeItem(
            workspaceRootURL: PreviewSampleData.workspaceRootURL,
            relativePath: "Inbox Renamed.md"
        )

        XCTAssertTrue(store.items.isEmpty)
    }
}
