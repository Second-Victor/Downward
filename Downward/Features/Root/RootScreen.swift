import SwiftUI

struct RootScreen: View {
    let viewModel: RootViewModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            switch viewModel.launchState {
            case .noWorkspaceSelected:
                LaunchStateView(
                    title: "Choose a Workspace",
                    message: "Choose one folder from Files to browse and edit markdown files inside it.",
                    symbolName: "folder.badge.plus",
                    isLoading: false,
                    primaryActionTitle: "Open Folder",
                    primaryAction: viewModel.presentFolderPicker,
                    secondaryActionTitle: nil,
                    secondaryAction: nil
                )
            case .restoringWorkspace:
                LaunchStateView(
                    title: "Restoring Workspace",
                    message: "Checking whether a previous workspace can be restored.",
                    symbolName: "arrow.trianglehead.2.clockwise.rotate.90",
                    isLoading: true,
                    primaryActionTitle: nil,
                    primaryAction: {},
                    secondaryActionTitle: nil,
                    secondaryAction: nil
                )
            case .workspaceReady:
                if horizontalSizeClass == .regular {
                    RegularWorkspaceShell(viewModel: viewModel)
                } else {
                    CompactWorkspaceShell(viewModel: viewModel)
                }
            case .workspaceAccessInvalid:
                ReconnectWorkspaceView(
                    workspaceName: viewModel.workspaceName ?? PreviewSampleData.nestedWorkspace.displayName,
                    error: viewModel.reconnectError,
                    reconnectAction: viewModel.presentFolderPicker,
                    clearAction: viewModel.clearWorkspace
                )
            case let .failed(error):
                LaunchStateView(
                    title: error.title,
                    message: error.message,
                    symbolName: "exclamationmark.triangle",
                    isLoading: false,
                    primaryActionTitle: "Retry Restore",
                    primaryAction: viewModel.retryRestore,
                    secondaryActionTitle: "Open Folder",
                    secondaryAction: viewModel.presentFolderPicker
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await viewModel.handleFirstAppear()
        }
        .fileImporter(
            isPresented: bindablePickerVisibility,
            allowedContentTypes: viewModel.allowedFolderContentTypes,
            allowsMultipleSelection: false,
            onCompletion: viewModel.handleFolderSelection
        )
        .alert(item: bindableAlertError) { error in
            Alert(
                title: Text(error.title),
                message: Text([error.message, error.recoverySuggestion].compactMap { $0 }.joined(separator: "\n\n")),
                dismissButton: .default(Text("OK")) {
                    viewModel.dismissAlert()
                }
            )
        }
    }

    private var bindablePickerVisibility: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingFolderPicker },
            set: { viewModel.isShowingFolderPicker = $0 }
        )
    }

    private var bindableAlertError: Binding<UserFacingError?> {
        Binding(
            get: { viewModel.alertError },
            set: { _ in viewModel.dismissAlert() }
        )
    }
}

private struct CompactWorkspaceShell: View {
    let viewModel: RootViewModel

    var body: some View {
        @Bindable var session = viewModel.session

        NavigationStack(path: $session.path) {
            WorkspaceScreen(viewModel: viewModel.workspaceViewModel)
                .navigationDestination(for: AppRoute.self) { route in
                    WorkspaceRouteDestination(route: route, viewModel: viewModel)
                }
        }
        .onChange(of: session.path) { _, newPath in
            viewModel.didChange(path: newPath)
        }
    }
}

private struct RegularWorkspaceShell: View {
    let viewModel: RootViewModel

    var body: some View {
        @Bindable var session = viewModel.session

        NavigationSplitView {
            WorkspaceScreen(viewModel: viewModel.workspaceViewModel)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 360)
        } detail: {
            NavigationStack(path: $session.path) {
                WorkspacePlaceholderDetailView()
                    .navigationDestination(for: AppRoute.self) { route in
                        WorkspaceRouteDestination(route: route, viewModel: viewModel)
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: session.path) { _, newPath in
            viewModel.didChange(path: newPath)
        }
    }
}

private struct WorkspaceRouteDestination: View {
    let route: AppRoute
    let viewModel: RootViewModel

    var body: some View {
        switch route {
        case let .folder(folderURL):
            WorkspaceFolderScreen(
                viewModel: viewModel.workspaceViewModel,
                folderURL: folderURL,
                showsSettingsButton: false
            )
        case let .editor(documentURL):
            EditorScreen(
                viewModel: viewModel.editorViewModel,
                documentURL: documentURL
            )
        case .settings:
            SettingsScreen(
                workspaceName: viewModel.workspaceName,
                accessState: viewModel.workspaceAccessState,
                reconnectWorkspaceAction: viewModel.presentFolderPicker,
                clearWorkspaceAction: viewModel.clearWorkspace
            )
        }
    }
}

#Preview("No Workspace") {
    RootScreen(
        viewModel: AppContainer.preview(
            launchState: .noWorkspaceSelected,
            accessState: .noneSelected
        ).rootViewModel
    )
}

#Preview("Restoring") {
    RootScreen(
        viewModel: AppContainer.preview(
            launchState: .restoringWorkspace,
            accessState: .restorable(displayName: PreviewSampleData.nestedWorkspace.displayName)
        ).rootViewModel
    )
}

#Preview("Ready") {
    RootScreen(
        viewModel: AppContainer.preview(
            launchState: .workspaceReady,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            snapshot: PreviewSampleData.nestedWorkspace
        ).rootViewModel
    )
}

#Preview("Invalid") {
    RootScreen(
        viewModel: AppContainer.preview(
            launchState: .workspaceAccessInvalid,
            accessState: .invalid(
                displayName: PreviewSampleData.nestedWorkspace.displayName,
                error: PreviewSampleData.invalidWorkspaceError
            )
        ).rootViewModel
    )
}

#Preview("Failed") {
    RootScreen(
        viewModel: AppContainer.preview(
            launchState: .failed(PreviewSampleData.failedLaunchError),
            accessState: .noneSelected
        ).rootViewModel
    )
}
