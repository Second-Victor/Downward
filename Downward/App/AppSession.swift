import Foundation
import Observation

enum RootLaunchState: Equatable {
    case noWorkspaceSelected
    case restoringWorkspace
    case workspaceReady
    case workspaceAccessInvalid
    case failed(UserFacingError)
}

@MainActor
@Observable
final class AppSession {
    var launchState: RootLaunchState = .noWorkspaceSelected
    var workspaceAccessState: WorkspaceAccessState = .noneSelected
    var workspaceSnapshot: WorkspaceSnapshot?
    var openDocument: OpenDocument?
    var editorLoadError: UserFacingError?
    var path: [AppRoute] = []
    var lastError: UserFacingError?
    var hasBootstrapped = false

    var currentWorkspaceName: String? {
        workspaceSnapshot?.displayName ?? workspaceAccessState.displayName
    }

    var regularWorkspaceDetail: RegularWorkspaceDetail {
        if let editorURL = path.last?.editorURL {
            return .editor(editorURL)
        }

        if path.last == .settings {
            return .settings
        }

        if let openDocument {
            return .editor(openDocument.url)
        }

        return .placeholder
    }
}

enum RegularWorkspaceDetail: Equatable {
    case placeholder
    case settings
    case editor(URL)
}
