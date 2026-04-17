import Foundation
import Observation

enum RootLaunchState: Equatable {
    case noWorkspaceSelected
    case restoringWorkspace
    case workspaceReady
    case workspaceAccessInvalid
    case failed(UserFacingError)
}

enum WorkspaceNavigationLayout: Equatable {
    case compact
    case regular
}

@MainActor
@Observable
final class AppSession {
    enum EditorPresentationSource: Equatable {
        case workspace
        case recentFile
    }

    struct PendingEditorPresentation: Equatable {
        let routeURL: URL
        let relativePath: String
        let source: EditorPresentationSource

        init(
            routeURL: URL,
            relativePath: String,
            source: EditorPresentationSource = .workspace
        ) {
            self.routeURL = routeURL
            self.relativePath = relativePath
            self.source = source
        }
    }

    var launchState: RootLaunchState = .noWorkspaceSelected
    var workspaceAccessState: WorkspaceAccessState = .noneSelected
    var workspaceSnapshot: WorkspaceSnapshot?
    /// The app currently owns one active editor document at a time. Navigation may point at
    /// different editor URLs over time, but the live editor model still reconciles through this
    /// single shared slot until a broader multi-document redesign exists.
    var openDocument: OpenDocument?
    /// Workspace/browser alerts presented from the root shell while a workspace is active.
    var workspaceAlertError: UserFacingError?
    /// Editor-only load failures shown in place of the editor when a routed file cannot open.
    var editorLoadError: UserFacingError?
    /// Editor-local alerts for operational failures that should not fight with workspace alerts.
    var editorAlertError: UserFacingError?
    /// Browser/search/recent-file opens seed trusted snapshot relative-path identity here before the
    /// editor route appears, so the load path does not need to re-derive identity from a raw URL.
    var pendingEditorPresentation: PendingEditorPresentation?
    var navigationLayout: WorkspaceNavigationLayout = .compact
    var path: [AppRoute] = []
    var regularDetailSelection: RegularWorkspaceDetailSelection = .placeholder
    var hasBootstrapped = false

    var navigationState: WorkspaceNavigationState {
        get {
            WorkspaceNavigationState(
                path: path,
                regularDetailSelection: regularDetailSelection
            )
        }
        set {
            path = newValue.path
            regularDetailSelection = newValue.regularDetailSelection
        }
    }

    var currentWorkspaceName: String? {
        workspaceSnapshot?.displayName ?? workspaceAccessState.displayName
    }

    /// Resolves the explicit regular-width detail selection into renderable detail content.
    var regularWorkspaceDetail: RegularWorkspaceDetail {
        regularDetailSelection.resolved(
            in: workspaceSnapshot,
            openDocument: openDocument,
            pendingEditorPresentation: pendingEditorPresentation
        )
    }

    var visibleDetailSelection: RegularWorkspaceDetailSelection {
        switch navigationLayout {
        case .compact:
            guard let lastRoute = path.last else {
                return .placeholder
            }

            if let relativePath = lastRoute.editorRelativePath {
                return .editor(relativePath)
            }

            switch lastRoute {
            case .settings:
                return .settings
            case let .editor(url):
                if let openDocument, openDocument.url == url {
                    return .editor(openDocument.relativePath)
                }

                guard let relativePath = workspaceSnapshot?.relativePath(for: url) else {
                    return .placeholder
                }

                return .editor(relativePath)
            case .trustedEditor:
                return .placeholder
            }
        case .regular:
            return regularDetailSelection
        }
    }

    var visibleEditorURL: URL? {
        switch navigationLayout {
        case .compact:
            path.last?.editorURL
        case .regular:
            regularWorkspaceDetail.editorURL
        }
    }

    var visibleEditorRelativePath: String? {
        switch visibleDetailSelection {
        case .placeholder, .settings:
            return nil
        case let .editor(relativePath):
            return relativePath
        }
    }

    func applyNavigationState(_ navigationState: WorkspaceNavigationState) {
        self.navigationState = navigationState
    }
}

enum RegularWorkspaceDetailSelection: Equatable {
    case placeholder
    case settings
    case editor(String)

    func resolved(
        in snapshot: WorkspaceSnapshot?,
        openDocument: OpenDocument?,
        pendingEditorPresentation: AppSession.PendingEditorPresentation?
    ) -> RegularWorkspaceDetail {
        switch self {
        case .placeholder:
            return .placeholder
        case .settings:
            return .settings
        case let .editor(relativePath):
            if let openDocument, openDocument.relativePath == relativePath {
                return .editor(openDocument.url)
            }

            if let pendingEditorPresentation,
               pendingEditorPresentation.relativePath == relativePath {
                return .editor(pendingEditorPresentation.routeURL)
            }

            guard let documentURL = snapshot?.fileURL(forRelativePath: relativePath) else {
                return .placeholder
            }

            return .editor(documentURL)
        }
    }
}

enum RegularWorkspaceDetail: Equatable {
    case placeholder
    case settings
    case editor(URL)

    var editorURL: URL? {
        if case let .editor(url) = self {
            return url
        }

        return nil
    }
}
