import Foundation

struct WorkspaceNavigationState: Equatable {
    var path: [AppRoute]
    var regularDetailSelection: RegularWorkspaceDetailSelection

    static let placeholder = WorkspaceNavigationState(
        path: [],
        regularDetailSelection: .placeholder
    )
}

struct StaleRecentFileOpenApplication: Equatable {
    let relativePath: String
    let error: UserFacingError
}

enum WorkspaceNavigationPolicy {
    static func editorRelativePath(
        for url: URL,
        snapshot: WorkspaceSnapshot?,
        openDocument: OpenDocument?
    ) -> String? {
        if let openDocument, openDocument.url == url {
            return openDocument.relativePath
        }

        return snapshot?.relativePath(for: url)
    }

    static func editorRouteURL(
        for relativePath: String,
        preferredURL: URL?,
        snapshot: WorkspaceSnapshot?,
        openDocument: OpenDocument?
    ) -> URL? {
        if let preferredURL {
            return preferredURL
        }

        if let openDocument, openDocument.relativePath == relativePath {
            return openDocument.url
        }

        if let snapshotURL = snapshot?.fileURL(forRelativePath: relativePath) {
            return snapshotURL
        }

        guard let workspaceRootURL = snapshot?.rootURL else {
            return nil
        }

        return WorkspaceRelativePath.resolve(relativePath, within: workspaceRootURL)
    }

    /// Browser/search/recent-file loads should resolve through the UI's trusted relative-path
    /// presentation state whenever that identity is available, regardless of route URL aliases.
    static func presentedEditorRelativePath(
        for documentURL: URL,
        navigationLayout: WorkspaceNavigationLayout,
        navigationState: WorkspaceNavigationState,
        regularWorkspaceDetailEditorURL: URL?,
        pendingEditorPresentation: AppSession.PendingEditorPresentation?
    ) -> String? {
        switch navigationLayout {
        case .compact:
            guard let route = navigationState.path.last, route.editorURL == documentURL else {
                return nil
            }

            return route.editorRelativePath
        case .regular:
            guard case let .editor(relativePath) = navigationState.regularDetailSelection else {
                return nil
            }

            if regularWorkspaceDetailEditorURL == documentURL {
                return relativePath
            }

            if pendingEditorPresentation?.relativePath == relativePath {
                return relativePath
            }

            return nil
        }
    }

    /// A stale recent-file tap should remove only the matching recent entry and show a recent-file
    /// specific error. Final file access still stays inside the document/workspace managers.
    static func staleRecentFileOpenApplication(
        from error: AppError,
        documentURL: URL,
        pendingEditorPresentation: AppSession.PendingEditorPresentation?,
        presentedRelativePath: String?,
        snapshot: WorkspaceSnapshot?
    ) -> StaleRecentFileOpenApplication? {
        guard case .documentUnavailable = error else {
            return nil
        }

        guard
            let pendingEditorPresentation,
            pendingEditorPresentation.source == .recentFile,
            pendingEditorPresentation.routeURL == documentURL
                || presentedRelativePath == pendingEditorPresentation.relativePath,
            snapshot != nil
        else {
            return nil
        }

        let documentName = documentURL.lastPathComponent
        return StaleRecentFileOpenApplication(
            relativePath: pendingEditorPresentation.relativePath,
            error: UserFacingError(
                title: "Recent File Unavailable",
                message: "\(documentName) is no longer available in this workspace.",
                recoverySuggestion: "It was removed from Recent Files. Choose another file from the browser."
            )
        )
    }

    static func rewrittenRelativePath(
        _ path: String,
        oldPrefix: String,
        newPrefix: String
    ) -> String? {
        guard matchesEditorRelativePath(
            path,
            targetRelativePath: oldPrefix,
            includingDescendants: true
        ) else {
            return nil
        }

        if path == oldPrefix {
            return newPrefix
        }

        let suffix = path.dropFirst(oldPrefix.count + 1)
        return "\(newPrefix)/\(suffix)"
    }

    static func isSameOrDescendantRelativePath(_ path: String, of prefix: String) -> Bool {
        matchesEditorRelativePath(
            path,
            targetRelativePath: prefix,
            includingDescendants: true
        )
    }

    /// Folder mutations rewrite descendant identities by relative path first so bookmark-scoped
    /// browser/search/restore state stays aligned even if route URLs were aliases.
    static func resolvedRenamedTrustedDescendantURL(
        existingURL: URL,
        updatedRelativePath: String,
        oldFolderURL: URL,
        newFolderURL: URL,
        snapshot: WorkspaceSnapshot
    ) -> URL {
        if let rewrittenURL = replacingDescendantURL(
            existingURL,
            oldPrefix: oldFolderURL,
            newPrefix: newFolderURL
        ) {
            return rewrittenURL
        }

        if let snapshotURL = snapshot.fileURL(forRelativePath: updatedRelativePath) {
            return snapshotURL
        }

        return WorkspaceRelativePath.resolve(
            updatedRelativePath,
            within: snapshot.rootURL
        )
    }

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
        matchingURL url: URL? = nil,
        includingDescendants: Bool = false
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

            if let url, includingDescendants, isSameOrDescendantURL(editorURL, of: url) {
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
            guard let routeRelativePath else {
                return true
            }

            return matchesEditorRelativePath(
                routeRelativePath,
                targetRelativePath: targetRelativePath,
                includingDescendants: includingDescendants
            ) == false
        }

        let updatedSelection: RegularWorkspaceDetailSelection
        switch navigationState.regularDetailSelection {
        case let .editor(selectedRelativePath)
            where targetRelativePath == nil || targetRelativePath.map {
                matchesEditorRelativePath(
                    selectedRelativePath,
                    targetRelativePath: $0,
                    includingDescendants: includingDescendants
                )
            } == true:
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
        openDocument: OpenDocument?,
        includingDescendants: Bool = false,
        workspaceRootURL: URL? = nil
    ) -> WorkspaceNavigationState {
        let updatedPath = navigationState.path.map { route in
            replacingRoute(
                route,
                oldURL: oldURL,
                newURL: newURL,
                oldRelativePath: oldRelativePath,
                newRelativePath: newRelativePath,
                includingDescendants: includingDescendants,
                workspaceRootURL: workspaceRootURL
            )
        }

        let updatedSelection: RegularWorkspaceDetailSelection
        switch navigationState.regularDetailSelection {
        case let .editor(selectedRelativePath):
            if let oldRelativePath,
               let rewrittenRelativePath = replacingRelativePath(
                selectedRelativePath,
                oldRelativePath: oldRelativePath,
                newRelativePath: newRelativePath,
                includingDescendants: includingDescendants
               ) {
                updatedSelection = .editor(rewrittenRelativePath)
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

    private static func replacingRoute(
        _ route: AppRoute,
        oldURL: URL,
        newURL: URL,
        oldRelativePath: String?,
        newRelativePath: String,
        includingDescendants: Bool,
        workspaceRootURL: URL?
    ) -> AppRoute {
        if includingDescendants == false {
            return route.replacingEditorURL(oldURL: oldURL, newURL: newURL)
        }

        guard let editorURL = route.editorURL else {
            return route
        }

        switch route {
        case .editor:
            if let rewrittenURL = replacingDescendantURL(editorURL, oldPrefix: oldURL, newPrefix: newURL) {
                return .editor(rewrittenURL)
            }

            guard
                let workspaceRootURL,
                let oldRelativePath,
                let routeRelativePath = WorkspaceRelativePath.make(for: editorURL, within: workspaceRootURL),
                let rewrittenRelativePath = replacingRelativePath(
                    routeRelativePath,
                    oldRelativePath: oldRelativePath,
                    newRelativePath: newRelativePath,
                    includingDescendants: includingDescendants
                )
            else {
                return route
            }

            let resolvedURL = WorkspaceRelativePath.resolve(
                rewrittenRelativePath,
                within: workspaceRootURL
            )
            return .editor(resolvedURL)
        case let .trustedEditor(_, existingRelativePath):
            guard
                let oldRelativePath,
                let rewrittenRelativePath = replacingRelativePath(
                    existingRelativePath,
                    oldRelativePath: oldRelativePath,
                    newRelativePath: newRelativePath,
                    includingDescendants: includingDescendants
                )
            else {
                return route
            }

            let rewrittenURL = resolvedTrustedEditorRouteURL(
                existingURL: editorURL,
                oldURL: oldURL,
                newURL: newURL,
                rewrittenRelativePath: rewrittenRelativePath,
                workspaceRootURL: workspaceRootURL
            )
            return .trustedEditor(rewrittenURL, rewrittenRelativePath)
        case .settings:
            return .settings
        }
    }

    private static func replacingRelativePath(
        _ path: String,
        oldRelativePath: String,
        newRelativePath: String,
        includingDescendants: Bool
    ) -> String? {
        if includingDescendants == false {
            guard path == oldRelativePath else {
                return nil
            }

            return newRelativePath
        }

        guard matchesEditorRelativePath(
            path,
            targetRelativePath: oldRelativePath,
            includingDescendants: true
        ) else {
            return nil
        }

        if path == oldRelativePath {
            return newRelativePath
        }

        let suffix = path.dropFirst(oldRelativePath.count + 1)
        return "\(newRelativePath)/\(suffix)"
    }

    private static func matchesEditorRelativePath(
        _ path: String,
        targetRelativePath: String,
        includingDescendants: Bool
    ) -> Bool {
        if includingDescendants == false {
            return path == targetRelativePath
        }

        return path == targetRelativePath || path.hasPrefix("\(targetRelativePath)/")
    }

    private static func replacingDescendantURL(
        _ url: URL,
        oldPrefix: URL,
        newPrefix: URL
    ) -> URL? {
        let urlComponents = url.standardizedFileURL.pathComponents
        let oldComponents = oldPrefix.standardizedFileURL.pathComponents
        guard urlComponents.starts(with: oldComponents) else {
            return nil
        }

        let suffixComponents = urlComponents.dropFirst(oldComponents.count)
        return suffixComponents.reduce(newPrefix.standardizedFileURL) { partialURL, component in
            partialURL.appending(path: component)
        }
    }

    private static func resolvedTrustedEditorRouteURL(
        existingURL: URL,
        oldURL: URL,
        newURL: URL,
        rewrittenRelativePath: String,
        workspaceRootURL: URL?
    ) -> URL {
        if let rewrittenURL = replacingDescendantURL(
            existingURL,
            oldPrefix: oldURL,
            newPrefix: newURL
        ) {
            return rewrittenURL
        }

        if let workspaceRootURL {
            return WorkspaceRelativePath.resolve(
                rewrittenRelativePath,
                within: workspaceRootURL
            )
        }

        return existingURL
    }

    private static func isSameOrDescendantURL(_ url: URL, of prefix: URL) -> Bool {
        let urlComponents = url.standardizedFileURL.pathComponents
        let prefixComponents = prefix.standardizedFileURL.pathComponents
        return urlComponents.starts(with: prefixComponents)
    }
}
