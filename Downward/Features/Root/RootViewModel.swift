import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class RootViewModel {
    let session: AppSession
    let workspaceViewModel: WorkspaceViewModel
    let editorViewModel: EditorViewModel
    var isShowingFolderPicker = false

    private let coordinator: AppCoordinator

    init(
        session: AppSession,
        coordinator: AppCoordinator,
        workspaceViewModel: WorkspaceViewModel,
        editorViewModel: EditorViewModel
    ) {
        self.session = session
        self.coordinator = coordinator
        self.workspaceViewModel = workspaceViewModel
        self.editorViewModel = editorViewModel
    }

    var launchState: RootLaunchState {
        session.launchState
    }

    var workspaceAccessState: WorkspaceAccessState {
        session.workspaceAccessState
    }

    var reconnectError: UserFacingError {
        session.workspaceAccessState.invalidationError ?? PreviewSampleData.invalidWorkspaceError
    }

    var workspaceName: String? {
        session.currentWorkspaceName
    }

    var allowedFolderContentTypes: [UTType] {
        coordinator.folderPickerContentTypes
    }

    var alertError: UserFacingError? {
        guard session.launchState == .workspaceReady else {
            return nil
        }

        return session.lastError
    }

    func handleFirstAppear() async {
        await coordinator.bootstrapIfNeeded()
    }

    func presentFolderPicker() {
        isShowingFolderPicker = true
    }

    func clearWorkspace() {
        Task {
            await coordinator.clearWorkspace()
        }
    }

    func retryRestore() {
        Task {
            await coordinator.retryRestore()
        }
    }

    func didChange(path: [AppRoute]) {
        coordinator.didChangeNavigationPath(path)
    }

    func handleFolderSelection(_ result: Result<[URL], Error>) {
        Task {
            await coordinator.handleFolderPickerResult(result)
        }
    }

    func dismissAlert() {
        session.lastError = nil
    }
}
