import Foundation

struct WorkspaceSessionStateApplication {
    let workspaceSnapshot: WorkspaceSnapshot?
    let workspaceAccessState: WorkspaceAccessState?
    let launchState: RootLaunchState
    let navigationState: WorkspaceNavigationState
    let workspaceAlertError: UserFacingError?
    let shouldClearOpenDocument: Bool
    let shouldClearEditorLoadError: Bool
    let shouldClearEditorAlertError: Bool
    let snapshotToPruneRecentFiles: WorkspaceSnapshot?
}

struct WorkspaceSnapshotRefreshReconciliation {
    let navigationState: WorkspaceNavigationState
    let shouldClearOpenDocument: Bool
    let shouldClearEditorLoadError: Bool
    let shouldClearEditorAlertError: Bool
    let shouldClearRestorableDocumentSession: Bool
    let workspaceAlertError: UserFacingError?
}

enum WorkspaceSessionPolicy {
    static func restoreApplication(
        for restoreResult: WorkspaceRestoreResult
    ) -> WorkspaceSessionStateApplication {
        switch restoreResult {
        case .noWorkspaceSelected:
            return WorkspaceSessionStateApplication(
                workspaceSnapshot: nil,
                workspaceAccessState: .noneSelected,
                launchState: .noWorkspaceSelected,
                navigationState: .placeholder,
                workspaceAlertError: nil,
                shouldClearOpenDocument: true,
                shouldClearEditorLoadError: true,
                shouldClearEditorAlertError: true,
                snapshotToPruneRecentFiles: nil
            )
        case let .ready(snapshot):
            return WorkspaceSessionStateApplication(
                workspaceSnapshot: snapshot,
                workspaceAccessState: .ready(displayName: snapshot.displayName),
                launchState: .workspaceReady,
                navigationState: .placeholder,
                workspaceAlertError: nil,
                shouldClearOpenDocument: true,
                shouldClearEditorLoadError: true,
                shouldClearEditorAlertError: true,
                snapshotToPruneRecentFiles: snapshot
            )
        case let .accessInvalid(accessState):
            return WorkspaceSessionStateApplication(
                workspaceSnapshot: nil,
                workspaceAccessState: accessState,
                launchState: .workspaceAccessInvalid,
                navigationState: .placeholder,
                workspaceAlertError: nil,
                shouldClearOpenDocument: true,
                shouldClearEditorLoadError: true,
                shouldClearEditorAlertError: true,
                snapshotToPruneRecentFiles: nil
            )
        case let .failed(error):
            return WorkspaceSessionStateApplication(
                workspaceSnapshot: nil,
                workspaceAccessState: nil,
                launchState: .failed(error),
                navigationState: .placeholder,
                workspaceAlertError: nil,
                shouldClearOpenDocument: true,
                shouldClearEditorLoadError: true,
                shouldClearEditorAlertError: true,
                snapshotToPruneRecentFiles: nil
            )
        }
    }

    static func reconnectApplication(
        displayName: String,
        message: String
    ) -> WorkspaceSessionStateApplication {
        let reconnectError = UserFacingError(
            title: "Workspace Needs Reconnect",
            message: message,
            recoverySuggestion: "Reconnect the folder to continue."
        )

        return WorkspaceSessionStateApplication(
            workspaceSnapshot: nil,
            workspaceAccessState: .invalid(
                displayName: displayName,
                error: reconnectError
            ),
            launchState: .workspaceAccessInvalid,
            navigationState: .placeholder,
            workspaceAlertError: nil,
            shouldClearOpenDocument: true,
            shouldClearEditorLoadError: true,
            shouldClearEditorAlertError: true,
            snapshotToPruneRecentFiles: nil
        )
    }

    static func reconcileAfterApplyingSnapshot(
        _ snapshot: WorkspaceSnapshot,
        navigationState: WorkspaceNavigationState,
        navigationLayout: WorkspaceNavigationLayout,
        openDocument: OpenDocument?,
        visibleEditorRelativePath: String?
    ) -> WorkspaceSnapshotRefreshReconciliation {
        let shouldPreserveCurrentEditor = shouldPreserveCurrentEditor(openDocument)
        let reconciledNavigationState = if shouldPreserveCurrentEditor {
            navigationState
        } else {
            WorkspaceNavigationState(
                path: reconciledCompactNavigationPath(from: navigationState.path, within: snapshot),
                regularDetailSelection: reconciledRegularDetailSelection(
                    from: navigationState.regularDetailSelection,
                    within: snapshot
                )
            )
        }

        guard let openDocument else {
            return WorkspaceSnapshotRefreshReconciliation(
                navigationState: reconciledNavigationState,
                shouldClearOpenDocument: false,
                shouldClearEditorLoadError: WorkspaceNavigationPolicy.isShowingEditor(
                    in: reconciledNavigationState,
                    layout: navigationLayout
                ) == false,
                shouldClearEditorAlertError: WorkspaceNavigationPolicy.isShowingEditor(
                    in: reconciledNavigationState,
                    layout: navigationLayout
                ) == false,
                shouldClearRestorableDocumentSession: false,
                workspaceAlertError: nil
            )
        }

        guard containsFile(relativePath: openDocument.relativePath, in: snapshot) == false else {
            return WorkspaceSnapshotRefreshReconciliation(
                navigationState: reconciledNavigationState,
                shouldClearOpenDocument: false,
                shouldClearEditorLoadError: false,
                shouldClearEditorAlertError: false,
                shouldClearRestorableDocumentSession: false,
                workspaceAlertError: nil
            )
        }

        guard shouldPreserveCurrentEditor == false else {
            return WorkspaceSnapshotRefreshReconciliation(
                navigationState: reconciledNavigationState,
                shouldClearOpenDocument: false,
                shouldClearEditorLoadError: false,
                shouldClearEditorAlertError: false,
                shouldClearRestorableDocumentSession: false,
                workspaceAlertError: nil
            )
        }

        let hadVisibleEditor = visibleEditorRelativePath == openDocument.relativePath
        return WorkspaceSnapshotRefreshReconciliation(
            navigationState: WorkspaceNavigationPolicy.removingEditorPresentation(
                from: reconciledNavigationState,
                workspaceRootURL: snapshot.rootURL,
                matchingRelativePath: openDocument.relativePath
            ),
            shouldClearOpenDocument: true,
            shouldClearEditorLoadError: true,
            shouldClearEditorAlertError: true,
            shouldClearRestorableDocumentSession: true,
            workspaceAlertError: hadVisibleEditor
                ? UserFacingError(
                    title: "Document Unavailable",
                    message: "\(openDocument.displayName) is no longer available in the workspace.",
                    recoverySuggestion: "Choose another file from the browser."
                )
                : nil
        )
    }

    static func shouldPreserveCurrentEditor(_ openDocument: OpenDocument?) -> Bool {
        guard let openDocument else {
            return false
        }

        return openDocument.isDirty
            || openDocument.saveState == .saving
            || openDocument.conflictState.isConflicted
    }

    static func containsFile(relativePath: String, in snapshot: WorkspaceSnapshot) -> Bool {
        snapshot.containsFile(relativePath: relativePath)
    }

    private static func reconciledCompactNavigationPath(
        from path: [AppRoute],
        within snapshot: WorkspaceSnapshot
    ) -> [AppRoute] {
        var reconciledPath: [AppRoute] = []

        for route in path {
            switch route {
            case .settings:
                reconciledPath.append(route)
            case let .editor(documentURL):
                guard
                    let relativePath = snapshot.relativePath(for: documentURL),
                    containsFile(relativePath: relativePath, in: snapshot)
                else {
                    return reconciledPath
                }

                reconciledPath.append(route)
            }
        }

        return reconciledPath
    }

    private static func reconciledRegularDetailSelection(
        from selection: RegularWorkspaceDetailSelection,
        within snapshot: WorkspaceSnapshot
    ) -> RegularWorkspaceDetailSelection {
        switch selection {
        case .placeholder, .settings:
            return selection
        case let .editor(relativePath):
            guard containsFile(relativePath: relativePath, in: snapshot) else {
                return .placeholder
            }

            return .editor(relativePath)
        }
    }
}
