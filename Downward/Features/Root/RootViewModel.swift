import Foundation
import Observation
import UniformTypeIdentifiers
import SwiftUI

@MainActor
@Observable
final class RootViewModel {
    let session: AppSession
    let workspaceViewModel: WorkspaceViewModel
    let editorViewModel: EditorViewModel
    let editorAppearanceStore: EditorAppearanceStore
    var isShowingFolderPicker = false

    private let coordinator: AppCoordinator

    init(
        session: AppSession,
        coordinator: AppCoordinator,
        workspaceViewModel: WorkspaceViewModel,
        editorViewModel: EditorViewModel,
        editorAppearanceStore: EditorAppearanceStore
    ) {
        self.session = session
        self.coordinator = coordinator
        self.workspaceViewModel = workspaceViewModel
        self.editorViewModel = editorViewModel
        self.editorAppearanceStore = editorAppearanceStore
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

        return session.workspaceAlertError
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

    func updateNavigationLayout(_ layout: WorkspaceNavigationLayout) {
        coordinator.updateNavigationLayout(layout)
    }

    func didChange(path: [AppRoute]) {
        coordinator.didChangeNavigationPath(path)
    }

    func handleFolderSelection(_ result: Result<[URL], Error>) {
        Task {
            await coordinator.handleFolderPickerResult(result)
        }
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            Task {
                await coordinator.handleSceneDidBecomeActive()
            }
        case .inactive, .background:
            editorViewModel.handleScenePhaseChange(phase)
        @unknown default:
            break
        }
    }

    func dismissAlert() {
        session.workspaceAlertError = nil
    }
}
