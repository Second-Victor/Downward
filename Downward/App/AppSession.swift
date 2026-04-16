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
    var launchState: RootLaunchState = .noWorkspaceSelected
    var workspaceAccessState: WorkspaceAccessState = .noneSelected
    var workspaceSnapshot: WorkspaceSnapshot?
    var openDocument: OpenDocument?
    var editorLoadError: UserFacingError?
    var navigationLayout: WorkspaceNavigationLayout = .compact
    var path: [AppRoute] = []
    var regularDetailSelection: RegularWorkspaceDetailSelection = .placeholder
    var lastError: UserFacingError?
    var hasBootstrapped = false

    var currentWorkspaceName: String? {
        workspaceSnapshot?.displayName ?? workspaceAccessState.displayName
    }

    /// Resolves the explicit regular-width detail selection into renderable detail content.
    var regularWorkspaceDetail: RegularWorkspaceDetail {
        regularDetailSelection.resolved(in: workspaceSnapshot, openDocument: openDocument)
    }

    var visibleDetailSelection: RegularWorkspaceDetailSelection {
        switch navigationLayout {
        case .compact:
            guard let lastRoute = path.last else {
                return .placeholder
            }

            switch lastRoute {
            case .settings:
                return .settings
            case let .editor(url):
                if let openDocument, openDocument.url == url {
                    return .editor(openDocument.relativePath)
                }

                guard
                    let workspaceRootURL = workspaceSnapshot?.rootURL,
                    let relativePath = WorkspaceRelativePath.make(for: url, within: workspaceRootURL)
                else {
                    return .placeholder
                }

                return .editor(relativePath)
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
}

enum RegularWorkspaceDetailSelection: Equatable {
    case placeholder
    case settings
    case editor(String)

    func resolved(
        in snapshot: WorkspaceSnapshot?,
        openDocument: OpenDocument?
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

            guard let rootURL = snapshot?.rootURL else {
                return .placeholder
            }

            guard let documentURL = WorkspaceRelativePath.resolveExisting(
                relativePath,
                within: rootURL
            ) else {
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
