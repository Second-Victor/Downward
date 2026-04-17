import XCTest
@testable import Downward

@MainActor
final class WorkspaceCoordinatorPolicyTests: XCTestCase {
    func testLayoutChangePromotesVisibleEditorIntoRegularSelection() {
        let navigationState = WorkspaceNavigationPolicy.stateForLayoutChange(
            visibleSelection: .editor(PreviewSampleData.cleanDocument.relativePath),
            layout: .regular,
            resolveEditorURL: { _ in nil }
        )

        XCTAssertEqual(navigationState.path, [])
        XCTAssertEqual(
            navigationState.regularDetailSelection,
            .editor(PreviewSampleData.cleanDocument.relativePath)
        )
    }

    func testPresentedSettingsInCompactModeDoesNotDuplicateSettingsRoute() {
        let initialState = WorkspaceNavigationState(
            path: [.settings],
            regularDetailSelection: .placeholder
        )

        let updatedState = WorkspaceNavigationPolicy.stateForPresentedSettings(
            from: initialState,
            layout: .compact
        )

        XCTAssertEqual(updatedState.path, [.settings])
        XCTAssertEqual(updatedState.regularDetailSelection, .placeholder)
    }

    func testPresentedEditorInCompactModeCarriesTrustedRelativeIdentity() {
        let updatedState = WorkspaceNavigationPolicy.stateForPresentedEditor(
            relativePath: PreviewSampleData.cleanDocument.relativePath,
            routeURL: PreviewSampleData.cleanDocument.url,
            layout: .compact,
            existingNavigationState: .placeholder
        )

        XCTAssertEqual(
            updatedState.path,
            [.trustedEditor(
                PreviewSampleData.cleanDocument.url,
                PreviewSampleData.cleanDocument.relativePath
            )]
        )
        XCTAssertEqual(updatedState.regularDetailSelection, .placeholder)
    }

    func testReplacingEditorPresentationUpdatesMatchingRouteAndSelection() {
        let renamedURL = PreviewSampleData.workspaceRootURL.appending(path: "Inbox Renamed.md")
        let initialState = WorkspaceNavigationState(
            path: [.settings, .editor(PreviewSampleData.cleanDocument.url)],
            regularDetailSelection: .editor(PreviewSampleData.cleanDocument.relativePath)
        )

        let updatedState = WorkspaceNavigationPolicy.replacingEditorPresentation(
            from: initialState,
            oldURL: PreviewSampleData.cleanDocument.url,
            newURL: renamedURL,
            oldRelativePath: PreviewSampleData.cleanDocument.relativePath,
            newRelativePath: "Inbox Renamed.md",
            openDocument: PreviewSampleData.cleanDocument
        )

        XCTAssertEqual(updatedState.path, [.settings, .editor(renamedURL)])
        XCTAssertEqual(updatedState.regularDetailSelection, .editor("Inbox Renamed.md"))
    }

    func testRestoreApplicationForReadyWorkspaceResetsNavigationAndPrunesSnapshot() {
        let application = WorkspaceSessionPolicy.restoreApplication(
            for: .ready(PreviewSampleData.nestedWorkspace)
        )

        XCTAssertEqual(application.workspaceSnapshot, PreviewSampleData.nestedWorkspace)
        XCTAssertEqual(
            application.workspaceAccessState,
            .ready(displayName: PreviewSampleData.nestedWorkspace.displayName)
        )
        XCTAssertEqual(application.launchState, .workspaceReady)
        XCTAssertEqual(application.navigationState, .placeholder)
        XCTAssertTrue(application.shouldClearOpenDocument)
        XCTAssertTrue(application.shouldClearEditorLoadError)
        XCTAssertTrue(application.shouldClearEditorAlertError)
        XCTAssertEqual(application.snapshotToPruneRecentFiles, PreviewSampleData.nestedWorkspace)
    }

    func testReconnectApplicationBuildsInvalidWorkspaceState() {
        let application = WorkspaceSessionPolicy.reconnectApplication(
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            message: "The workspace can no longer be accessed."
        )

        XCTAssertEqual(
            application.workspaceAccessState,
            .invalid(
                displayName: PreviewSampleData.nestedWorkspace.displayName,
                error: UserFacingError(
                    title: "Workspace Needs Reconnect",
                    message: "The workspace can no longer be accessed.",
                    recoverySuggestion: "Reconnect the folder to continue."
                )
            )
        )
        XCTAssertEqual(application.launchState, .workspaceAccessInvalid)
        XCTAssertEqual(application.navigationState, .placeholder)
        XCTAssertTrue(application.shouldClearOpenDocument)
        XCTAssertTrue(application.shouldClearEditorLoadError)
        XCTAssertTrue(application.shouldClearEditorAlertError)
    }

    func testSnapshotReconciliationClearsMissingVisibleCleanEditor() {
        let snapshotWithoutOpenDocument = WorkspaceSnapshot(
            rootURL: PreviewSampleData.workspaceRootURL,
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            rootNodes: PreviewSampleData.nestedWorkspace.rootNodes.filter { $0.url != PreviewSampleData.cleanDocument.url },
            lastUpdated: PreviewSampleData.previewDate
        )

        let reconciliation = WorkspaceSessionPolicy.reconcileAfterApplyingSnapshot(
            snapshotWithoutOpenDocument,
            navigationState: WorkspaceNavigationState(
                path: [.editor(PreviewSampleData.cleanDocument.url)],
                regularDetailSelection: .placeholder
            ),
            navigationLayout: .compact,
            openDocument: PreviewSampleData.cleanDocument,
            visibleEditorRelativePath: PreviewSampleData.cleanDocument.relativePath
        )

        XCTAssertEqual(reconciliation.navigationState, .placeholder)
        XCTAssertTrue(reconciliation.shouldClearOpenDocument)
        XCTAssertTrue(reconciliation.shouldClearEditorLoadError)
        XCTAssertTrue(reconciliation.shouldClearEditorAlertError)
        XCTAssertTrue(reconciliation.shouldClearRestorableDocumentSession)
        XCTAssertEqual(reconciliation.workspaceAlertError?.title, "Document Unavailable")
    }

    func testSnapshotReconciliationPreservesDirtyMissingEditor() {
        let snapshotWithoutDirtyDocument = WorkspaceSnapshot(
            rootURL: PreviewSampleData.workspaceRootURL,
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            rootNodes: [
                .folder(
                    .init(
                        url: PreviewSampleData.referencesURL,
                        displayName: "References",
                        children: []
                    )
                )
            ],
            lastUpdated: PreviewSampleData.previewDate
        )

        let initialNavigationState = WorkspaceNavigationState(
            path: [.editor(PreviewSampleData.dirtyDocument.url)],
            regularDetailSelection: .placeholder
        )
        let reconciliation = WorkspaceSessionPolicy.reconcileAfterApplyingSnapshot(
            snapshotWithoutDirtyDocument,
            navigationState: initialNavigationState,
            navigationLayout: .compact,
            openDocument: PreviewSampleData.dirtyDocument,
            visibleEditorRelativePath: PreviewSampleData.dirtyDocument.relativePath
        )

        XCTAssertEqual(reconciliation.navigationState, initialNavigationState)
        XCTAssertFalse(reconciliation.shouldClearOpenDocument)
        XCTAssertFalse(reconciliation.shouldClearEditorLoadError)
        XCTAssertFalse(reconciliation.shouldClearEditorAlertError)
        XCTAssertFalse(reconciliation.shouldClearRestorableDocumentSession)
        XCTAssertNil(reconciliation.workspaceAlertError)
    }
}
