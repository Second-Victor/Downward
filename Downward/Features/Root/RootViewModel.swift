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
    let themeStore: ThemeStore
    let importedFontManager: ImportedFontManager
    var isShowingFolderPicker = false
    private(set) var isRestoringWorkspace = false
    private(set) var shouldShowRestoreSpinner = false
    private(set) var shouldShowSlowRestoreMessage = false
    private(set) var restoreStartedAt: Date?

    private let coordinator: AppCoordinator
    @ObservationIgnored private var restorePresentationTask: Task<Void, Never>?
    private let restoreSpinnerDelay: Duration = .milliseconds(300)
    private let slowRestoreMessageDelay: Duration = .milliseconds(1_800)

    init(
        session: AppSession,
        coordinator: AppCoordinator,
        workspaceViewModel: WorkspaceViewModel,
        editorViewModel: EditorViewModel,
        editorAppearanceStore: EditorAppearanceStore,
        themeStore: ThemeStore,
        importedFontManager: ImportedFontManager
    ) {
        self.session = session
        self.coordinator = coordinator
        self.workspaceViewModel = workspaceViewModel
        self.editorViewModel = editorViewModel
        self.editorAppearanceStore = editorAppearanceStore
        self.themeStore = themeStore
        self.importedFontManager = importedFontManager
    }

    var launchState: RootLaunchState {
        session.launchState
    }

    var shouldShowInitialRestoreShell: Bool {
        session.hasBootstrapped == false || isRestoringWorkspace
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
        guard session.hasBootstrapped == false else {
            return
        }

        beginLaunchWorkspaceRestorePresentation()
        await coordinator.bootstrapIfNeeded()
        finishLaunchWorkspaceRestorePresentation()
    }

    func presentFolderPicker() {
        isShowingFolderPicker = true
    }

    func clearWorkspace() {
        // App-owned one-shot action: coordinator transition generations prevent stale workspace
        // results from applying if another restore/reconnect/clear flow wins first.
        Task {
            await coordinator.clearWorkspace()
        }
    }

    func retryRestore() {
        // App-owned one-shot action guarded by coordinator workspace transition generations.
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
        // Folder picker results are session-level work, not view-local state. The coordinator owns
        // stale-result suppression while workspace identity changes.
        Task {
            await coordinator.handleFolderPickerResult(result)
        }
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            // Foreground validation is intentionally app-owned fire-and-forget; refresh application
            // is generation-gated in the coordinator.
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

    private func beginLaunchWorkspaceRestorePresentation() {
        restorePresentationTask?.cancel()
        restoreStartedAt = Date()
        isRestoringWorkspace = true
        shouldShowRestoreSpinner = false
        shouldShowSlowRestoreMessage = false

        // The delay prevents one-frame or fractional-second restore flashes during normal launch.
        // Fast bookmark restores should move straight from a quiet shell to app content.
        restorePresentationTask = Task { @MainActor in
            try? await Task.sleep(for: restoreSpinnerDelay)
            guard Task.isCancelled == false, isRestoringWorkspace else {
                return
            }

            withAnimation(.easeInOut(duration: 0.18)) {
                shouldShowRestoreSpinner = true
            }

            try? await Task.sleep(for: slowRestoreMessageDelay)
            guard Task.isCancelled == false, isRestoringWorkspace else {
                return
            }

            withAnimation(.easeInOut(duration: 0.18)) {
                shouldShowSlowRestoreMessage = true
            }
        }
    }

    private func finishLaunchWorkspaceRestorePresentation() {
        restorePresentationTask?.cancel()
        restorePresentationTask = nil
        restoreStartedAt = nil
        isRestoringWorkspace = false

        withAnimation(.easeInOut(duration: 0.18)) {
            shouldShowRestoreSpinner = false
            shouldShowSlowRestoreMessage = false
        }
    }
}
