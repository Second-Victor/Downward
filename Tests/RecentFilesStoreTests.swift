import XCTest
@testable import Downward

final class RecentFilesStoreTests: XCTestCase {
    @MainActor
    func testRecentFilesStoreInsertsMostRecentFirstAndDeduplicates() {
        let store = RecentFilesStore(initialItems: [])
        let openedAt = Date(timeIntervalSince1970: 10)
        let reopenedAt = Date(timeIntervalSince1970: 20)

        store.record(document: PreviewSampleData.cleanDocument, in: PreviewSampleData.nestedWorkspace, openedAt: openedAt)
        store.record(document: PreviewSampleData.dirtyDocument, in: PreviewSampleData.nestedWorkspace, openedAt: reopenedAt)
        store.record(document: PreviewSampleData.cleanDocument, in: PreviewSampleData.nestedWorkspace, openedAt: reopenedAt.addingTimeInterval(10))

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
        store.record(document: PreviewSampleData.cleanDocument, in: PreviewSampleData.nestedWorkspace, openedAt: .init(timeIntervalSince1970: 100))
        store.record(document: PreviewSampleData.dirtyDocument, in: PreviewSampleData.nestedWorkspace, openedAt: .init(timeIntervalSince1970: 200))

        let reloadedStore = RecentFilesStore(userDefaults: userDefaults)

        XCTAssertEqual(reloadedStore.items.map(\.displayName), ["2026-04-13.md", "Inbox.md"])
        XCTAssertEqual(reloadedStore.items.map(\.relativePath), [
            PreviewSampleData.dirtyDocument.relativePath,
            PreviewSampleData.cleanDocument.relativePath,
        ])
        XCTAssertEqual(reloadedStore.items.map(\.workspaceID), [
            PreviewSampleData.nestedWorkspace.workspaceID,
            PreviewSampleData.nestedWorkspace.workspaceID,
        ])
    }

    @MainActor
    func testRecentFilesStoreReadsLegacyStoredItemsWithoutWorkspaceID() throws {
        let suiteName = "RecentFilesStoreTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let legacyPayload = try JSONEncoder().encode(
            [
                LegacyRecentFileItemPayload(
                    workspaceRootPath: "/preview/LegacyWorkspace",
                    relativePath: "Inbox.md",
                    displayName: "Inbox.md",
                    lastOpenedAt: PreviewSampleData.previewDate
                ),
            ]
        )
        userDefaults.set(legacyPayload, forKey: "recentFiles.items")

        let store = RecentFilesStore(userDefaults: userDefaults)

        XCTAssertEqual(store.items.map(\.displayName), ["Inbox.md"])
        XCTAssertEqual(
            store.items.first?.workspaceID,
            WorkspaceIdentity.legacyPathID(forPath: "/preview/LegacyWorkspace")
        )
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
                    workspaceID: PreviewSampleData.nestedWorkspace.workspaceID,
                    workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                    relativePath: PreviewSampleData.cleanDocument.relativePath,
                    displayName: PreviewSampleData.cleanDocument.displayName,
                    lastOpenedAt: PreviewSampleData.previewDate
                ),
            ]
        )

        store.renameItem(
            using: PreviewSampleData.nestedWorkspace,
            oldRelativePath: PreviewSampleData.cleanDocument.relativePath,
            newRelativePath: "Inbox Renamed.md",
            displayName: "Inbox Renamed.md"
        )

        XCTAssertEqual(store.items.first?.displayName, "Inbox Renamed.md")
        XCTAssertEqual(store.items.first?.relativePath, "Inbox Renamed.md")

        store.removeItem(
            using: PreviewSampleData.nestedWorkspace,
            relativePath: "Inbox Renamed.md"
        )

        XCTAssertTrue(store.items.isEmpty)
    }

    @MainActor
    func testRecentFilesStoreAdoptsLegacyWorkspacePathItemsIntoStableWorkspaceID() {
        let store = RecentFilesStore(
            initialItems: [
                RecentFileItem(
                    workspaceRootPath: "/preview/OldWorkspacePath",
                    relativePath: PreviewSampleData.cleanDocument.relativePath,
                    displayName: PreviewSampleData.cleanDocument.displayName,
                    lastOpenedAt: PreviewSampleData.previewDate
                ),
            ]
        )
        let movedWorkspaceSnapshot = WorkspaceSnapshot(
            workspaceID: "workspace-stable-id",
            recentFileLookupPaths: [
                "/preview/OldWorkspacePath",
                "/preview/NewWorkspacePath",
            ],
            rootURL: URL(filePath: "/preview/NewWorkspacePath"),
            displayName: "Moved Workspace",
            rootNodes: PreviewSampleData.nestedWorkspace.rootNodes,
            lastUpdated: PreviewSampleData.previewDate
        )

        store.adoptWorkspaceIdentity(using: movedWorkspaceSnapshot)

        XCTAssertEqual(store.items.first?.workspaceID, "workspace-stable-id")
        XCTAssertEqual(store.items.first?.workspaceRootPath, "/preview/NewWorkspacePath")
        XCTAssertEqual(store.recentItems(for: movedWorkspaceSnapshot).map(\.displayName), ["Inbox.md"])
    }

    @MainActor
    func testRecentFilesStoreShowsStableWorkspaceItemsAfterResolvedPathChanges() {
        let movedWorkspaceSnapshot = WorkspaceSnapshot(
            workspaceID: "workspace-stable-id",
            recentFileLookupPaths: ["/preview/OldWorkspacePath", "/preview/NewWorkspacePath"],
            rootURL: URL(filePath: "/preview/NewWorkspacePath"),
            displayName: "Moved Workspace",
            rootNodes: PreviewSampleData.nestedWorkspace.rootNodes,
            lastUpdated: PreviewSampleData.previewDate
        )
        let store = RecentFilesStore(
            initialItems: [
                RecentFileItem(
                    workspaceID: "workspace-stable-id",
                    workspaceRootPath: "/preview/OldWorkspacePath",
                    relativePath: PreviewSampleData.cleanDocument.relativePath,
                    displayName: PreviewSampleData.cleanDocument.displayName,
                    lastOpenedAt: PreviewSampleData.previewDate
                ),
            ]
        )

        XCTAssertEqual(store.recentItems(for: movedWorkspaceSnapshot).map(\.displayName), ["Inbox.md"])
    }

    @MainActor
    func testRecentFileItemProvidesParentPathContextForDuplicateFilenames() {
        let referencesItem = RecentFileItem(
            workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
            relativePath: "References/README.md",
            displayName: "README.md",
            lastOpenedAt: PreviewSampleData.previewDate
        )
        let archiveItem = RecentFileItem(
            workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
            relativePath: "Archive/README.md",
            displayName: "README.md",
            lastOpenedAt: PreviewSampleData.previewDate.addingTimeInterval(-60)
        )
        let rootItem = RecentFileItem(
            workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
            relativePath: "Inbox.md",
            displayName: "Inbox.md",
            lastOpenedAt: PreviewSampleData.previewDate.addingTimeInterval(-120)
        )

        XCTAssertEqual(referencesItem.pathContextText, "References")
        XCTAssertEqual(archiveItem.pathContextText, "Archive")
        XCTAssertNotEqual(referencesItem.pathContextText, archiveItem.pathContextText)
        XCTAssertEqual(rootItem.pathContextText, "Workspace root")
    }

    @MainActor
    func testRecentFilePreferredRouteURLFallsBackToRelativeResolutionWhenSnapshotNoLongerContainsFile() {
        let item = RecentFileItem(
            workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
            relativePath: "Archive/Missing.md",
            displayName: "Missing.md",
            lastOpenedAt: PreviewSampleData.previewDate
        )

        let preferredRouteURL = item.preferredRouteURL(in: PreviewSampleData.nestedWorkspace)

        XCTAssertEqual(
            preferredRouteURL,
            PreviewSampleData.workspaceRootURL.appending(path: "Archive/Missing.md")
        )
    }
}

private struct LegacyRecentFileItemPayload: Codable {
    let workspaceRootPath: String
    let relativePath: String
    let displayName: String
    let lastOpenedAt: Date
}
