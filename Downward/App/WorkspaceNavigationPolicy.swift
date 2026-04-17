import Foundation

struct WorkspaceNavigationState: Equatable {
    var path: [AppRoute]
    var regularDetailSelection: RegularWorkspaceDetailSelection

    static let placeholder = WorkspaceNavigationState(
        path: [],
        regularDetailSelection: .placeholder
    )
}

enum WorkspaceNavigationPolicy {
    static func stateForLayoutChange(
        visibleSelection: RegularWorkspaceDetailSelection,
        layout: WorkspaceNavigationLayout,
        resolveEditorURL: (String) -> URL?
    ) -> WorkspaceNavigationState {
        switch layout {
        case .compact:
            return WorkspaceNavigationState(
                path: compactPath(for: visibleSelection, resolveEditorURL: resolveEditorURL),
                regularDetailSelection: .placeholder
            )
        case .regular:
            return WorkspaceNavigationState(
                path: [],
                regularDetailSelection: visibleSelection
            )
        }
    }

    static func stateForPresentedSettings(
        from navigationState: WorkspaceNavigationState,
        layout: WorkspaceNavigationLayout
    ) -> WorkspaceNavigationState {
        switch layout {
        case .compact:
            guard navigationState.path.contains(.settings) == false else {
                return navigationState
            }

            var updatedState = navigationState
            updatedState.path.append(.settings)
            return updatedState
        case .regular:
            return WorkspaceNavigationState(
                path: navigationState.path,
                regularDetailSelection: .settings
            )
        }
    }

    static func stateForPresentedEditor(
        relativePath: String,
        routeURL: URL,
        layout: WorkspaceNavigationLayout,
        existingNavigationState: WorkspaceNavigationState
    ) -> WorkspaceNavigationState {
        switch layout {
        case .compact:
            var updatedPath = existingNavigationState.path
            if let editorIndex = updatedPath.lastIndex(where: \.isEditor) {
                updatedPath = Array(updatedPath.prefix(upTo: editorIndex))
            }
            updatedPath.append(.trustedEditor(routeURL, relativePath))

            return WorkspaceNavigationState(
                path: updatedPath,
                regularDetailSelection: existingNavigationState.regularDetailSelection
            )
        case .regular:
            return WorkspaceNavigationState(
                path: existingNavigationState.path,
                regularDetailSelection: .editor(relativePath)
            )
        }
    }

    static func stateForPresentedEditor(
        at url: URL,
        layout: WorkspaceNavigationLayout,
        snapshot: WorkspaceSnapshot?,
        openDocument: OpenDocument?,
        existingNavigationState: WorkspaceNavigationState
    ) -> WorkspaceNavigationState {
        switch layout {
        case .compact:
            var updatedPath = existingNavigationState.path
            if let editorIndex = updatedPath.lastIndex(where: \.isEditor) {
                updatedPath = Array(updatedPath.prefix(upTo: editorIndex))
            }
            updatedPath.append(.editor(url))

            return WorkspaceNavigationState(
                path: updatedPath,
                regularDetailSelection: existingNavigationState.regularDetailSelection
            )
        case .regular:
            guard let relativePath = relativePath(for: url, snapshot: snapshot, openDocument: openDocument) else {
                return WorkspaceNavigationState(
                    path: existingNavigationState.path,
                    regularDetailSelection: .placeholder
                )
            }

            return WorkspaceNavigationState(
                path: existingNavigationState.path,
                regularDetailSelection: .editor(relativePath)
            )
        }
    }

    static func stateForRestoredEditor(
        _ document: OpenDocument,
        layout: WorkspaceNavigationLayout
    ) -> WorkspaceNavigationState {
        switch layout {
        case .compact:
            return WorkspaceNavigationState(
                path: [.trustedEditor(document.url, document.relativePath)],
                regularDetailSelection: .placeholder
            )
        case .regular:
            return WorkspaceNavigationState(
                path: [],
                regularDetailSelection: .editor(document.relativePath)
            )
        }
    }

    static func removingEditorPresentation(
        from navigationState: WorkspaceNavigationState,
        workspaceRootURL: URL?,
        matchingRelativePath relativePath: String?,
        matchingURL url: URL? = nil
    ) -> WorkspaceNavigationState {
        let targetRelativePath = relativePath ?? {
            guard let url, let workspaceRootURL else {
                return nil
            }

            return WorkspaceRelativePath.make(for: url, within: workspaceRootURL)
        }()

        let updatedPath = navigationState.path.filter { route in
            guard let editorURL = route.editorURL else {
                return true
            }

            if let url, editorURL == url {
                return false
            }

            guard
                let targetRelativePath,
                let workspaceRootURL
            else {
                return true
            }

            let routeRelativePath = route.editorRelativePath
                ?? WorkspaceRelativePath.make(for: editorURL, within: workspaceRootURL)
            return routeRelativePath != targetRelativePath
        }

        let updatedSelection: RegularWorkspaceDetailSelection
        switch navigationState.regularDetailSelection {
        case let .editor(selectedRelativePath)
            where targetRelativePath == nil || selectedRelativePath == targetRelativePath:
            updatedSelection = .placeholder
        default:
            updatedSelection = navigationState.regularDetailSelection
        }

        return WorkspaceNavigationState(
            path: updatedPath,
            regularDetailSelection: updatedSelection
        )
    }

    static func replacingEditorPresentation(
        from navigationState: WorkspaceNavigationState,
        oldURL: URL,
        newURL: URL,
        oldRelativePath: String?,
        newRelativePath: String,
        openDocument: OpenDocument?
    ) -> WorkspaceNavigationState {
        let updatedPath = navigationState.path.map { route in
            route.replacingEditorURL(oldURL: oldURL, newURL: newURL)
        }

        let updatedSelection: RegularWorkspaceDetailSelection
        switch navigationState.regularDetailSelection {
        case let .editor(selectedRelativePath):
            if selectedRelativePath == newRelativePath || selectedRelativePath == oldRelativePath {
                updatedSelection = .editor(newRelativePath)
            } else {
                updatedSelection = navigationState.regularDetailSelection
            }
        default:
            if let openDocument, openDocument.url == oldURL {
                updatedSelection = .editor(newRelativePath)
            } else {
                updatedSelection = navigationState.regularDetailSelection
            }
        }

        return WorkspaceNavigationState(
            path: updatedPath,
            regularDetailSelection: updatedSelection
        )
    }

    static func isShowingEditor(
        in navigationState: WorkspaceNavigationState,
        layout: WorkspaceNavigationLayout
    ) -> Bool {
        switch layout {
        case .compact:
            return navigationState.path.last?.isEditor == true
        case .regular:
            if case .editor = navigationState.regularDetailSelection {
                return true
            }

            return false
        }
    }

    private static func compactPath(
        for selection: RegularWorkspaceDetailSelection,
        resolveEditorURL: (String) -> URL?
    ) -> [AppRoute] {
        switch selection {
        case .placeholder:
            return []
        case .settings:
            return [.settings]
        case let .editor(relativePath):
            guard let url = resolveEditorURL(relativePath) else {
                return []
            }

            return [.trustedEditor(url, relativePath)]
        }
    }

    private static func relativePath(
        for url: URL,
        snapshot: WorkspaceSnapshot?,
        openDocument: OpenDocument?
    ) -> String? {
        if let openDocument, openDocument.url == url {
            return openDocument.relativePath
        }

        return snapshot?.relativePath(for: url)
    }
}
