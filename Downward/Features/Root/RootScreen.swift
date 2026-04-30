import SwiftUI

struct RootScreen: View {
    let viewModel: RootViewModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ZStack {
            if shouldMountLaunchContentBehindRestoreShell || viewModel.shouldShowInitialRestoreShell == false {
                launchContent
            }

            if viewModel.shouldShowInitialRestoreShell {
                WorkspaceRestoreLoadingView(
                    showsSpinner: viewModel.shouldShowRestoreSpinner,
                    showsSlowMessage: viewModel.shouldShowSlowRestoreMessage
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await viewModel.handleFirstAppear()
        }
        .task(id: horizontalSizeClass == .regular) {
            viewModel.updateNavigationLayout(
                horizontalSizeClass == .regular ? .regular : .compact
            )
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

    @ViewBuilder
    private var launchContent: some View {
        switch viewModel.launchState {
        case .noWorkspaceSelected:
            LaunchStateView(
                title: "Choose a Workspace",
                message: "Choose one folder from Files to browse and edit Markdown and text files inside it.",
                symbolName: "folder.badge.plus",
                isLoading: false,
                primaryActionTitle: "Open Folder",
                primaryAction: viewModel.presentFolderPicker,
                secondaryActionTitle: nil,
                secondaryAction: nil
            )
        case .restoringWorkspace:
            WorkspaceRestoreLoadingView(
                showsSpinner: true,
                showsSlowMessage: false
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

    private var shouldMountLaunchContentBehindRestoreShell: Bool {
        guard viewModel.shouldShowInitialRestoreShell else {
            return false
        }

        // Keep the real workspace/navigation shell alive underneath the opaque restore shell once
        // the workspace is ready. Otherwise a restored editor can be the NavigationStack's first
        // visible layout, and the browser performs its first title/list layout during the initial
        // back-pop transition.
        if case .workspaceReady = viewModel.launchState {
            return true
        }

        return false
    }
}

private struct WorkspaceRestoreLoadingView: View {
    let showsSpinner: Bool
    let showsSlowMessage: Bool

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            if showsSpinner {
                VStack(spacing: 10) {
                    ProgressView()

                    Text(showsSlowMessage ? "Still restoring workspace…" : "Restoring workspace…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showsSpinner)
        .animation(.easeInOut(duration: 0.18), value: showsSlowMessage)
    }
}

private struct CompactWorkspaceShell: View {
    let viewModel: RootViewModel

    var body: some View {
        @Bindable var session = viewModel.session

        NavigationStack(path: $session.path) {
            WorkspaceScreen(
                viewModel: viewModel.workspaceViewModel,
                navigationMode: .stackPath
            )
                .roundedNavigationBarTitles()
                .navigationDestination(for: AppRoute.self) { route in
                    WorkspaceRouteDestination(route: route, viewModel: viewModel)
                }
        }
        .sheet(isPresented: settingsPresentationBinding) {
            SettingsScreen(
                workspaceName: viewModel.workspaceName,
                accessState: viewModel.workspaceAccessState,
                editorAppearanceStore: viewModel.editorAppearanceStore,
                themeStore: viewModel.themeStore,
                importedFontManager: viewModel.importedFontManager,
                reconnectWorkspaceAction: viewModel.presentFolderPicker,
                clearWorkspaceAction: viewModel.clearWorkspace,
                dismissAction: {
                    session.dismissSettingsSurface()
                }
            )
        }
        .onChange(of: session.path) { _, newPath in
            viewModel.didChange(path: newPath)
        }
    }

    private var settingsPresentationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.session.isSettingsPresented },
            set: { isPresented in
                if isPresented == false {
                    viewModel.session.dismissSettingsSurface()
                }
            }
        )
    }
}

private struct RegularWorkspaceShell: View {
    let viewModel: RootViewModel

    var body: some View {
        @Bindable var session = viewModel.session

        NavigationSplitView {
            WorkspaceScreen(
                viewModel: viewModel.workspaceViewModel,
                navigationMode: .splitSidebar
            )
                .roundedNavigationBarTitles()
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 360)
        } detail: {
            RegularWorkspaceDetailView(viewModel: viewModel)
        }
        .navigationSplitViewStyle(.balanced)
        // Settings are a dedicated sheet over the split view rather than a detail replacement.
        .sheet(isPresented: settingsPresentationBinding) {
            SettingsScreen(
                workspaceName: viewModel.workspaceName,
                accessState: viewModel.workspaceAccessState,
                editorAppearanceStore: viewModel.editorAppearanceStore,
                themeStore: viewModel.themeStore,
                importedFontManager: viewModel.importedFontManager,
                reconnectWorkspaceAction: viewModel.presentFolderPicker,
                clearWorkspaceAction: viewModel.clearWorkspace,
                dismissAction: {
                    session.dismissSettingsSurface()
                }
            )
        }
    }

    private var settingsPresentationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.session.isSettingsPresented },
            set: { isPresented in
                if isPresented == false {
                    viewModel.session.dismissSettingsSurface()
                }
            }
        )
    }
}

private struct RegularWorkspaceDetailView: View {
    let viewModel: RootViewModel

    var body: some View {
        NavigationStack {
            switch viewModel.session.regularWorkspaceDisplayDetail {
            case .placeholder:
                WorkspacePlaceholderDetailView()
            case .settings:
                WorkspacePlaceholderDetailView()
            case let .editor(documentURL):
                EditorScreen(
                    viewModel: viewModel.editorViewModel,
                    documentURL: documentURL
                )
            }
        }
        .roundedNavigationBarTitles()
    }
}

private struct WorkspaceRouteDestination: View {
    let route: AppRoute
    let viewModel: RootViewModel

    var body: some View {
        switch route {
        case let .editor(documentURL), let .trustedEditor(documentURL, _):
            EditorScreen(
                viewModel: viewModel.editorViewModel,
                documentURL: documentURL
            )
        case .settings:
            SettingsScreen(
                workspaceName: viewModel.workspaceName,
                accessState: viewModel.workspaceAccessState,
                editorAppearanceStore: viewModel.editorAppearanceStore,
                themeStore: viewModel.themeStore,
                importedFontManager: viewModel.importedFontManager,
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
