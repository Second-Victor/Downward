import SwiftUI

struct WorkspaceScreen: View {
    let viewModel: WorkspaceViewModel

    var body: some View {
        Group {
            if viewModel.isLoading {
                ContentUnavailableView(
                    "Loading Workspace",
                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                    description: Text("Reading the current folder structure.")
                )
            } else if viewModel.isShowingErrorState, let error = viewModel.loadError {
                ContentUnavailableView(
                    error.title,
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.message)
                )
            } else {
                WorkspaceFolderScreen(
                    viewModel: viewModel,
                    folderURL: nil,
                    showsSettingsButton: true
                )
            }
        }
        .task {
            viewModel.loadSnapshotIfNeeded()
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview("Empty") {
    NavigationStack {
        WorkspaceScreen(
            viewModel: {
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.emptyWorkspace.displayName),
                    snapshot: PreviewSampleData.emptyWorkspace
                )
                return container.workspaceViewModel
            }()
        )
    }
}

#Preview("Deep Nested") {
    NavigationStack {
        WorkspaceScreen(
            viewModel: {
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.deepWorkspace.displayName),
                    snapshot: PreviewSampleData.deepWorkspace
                )
                return container.workspaceViewModel
            }()
        )
    }
}

#Preview("Large Dataset") {
    NavigationStack {
        WorkspaceScreen(
            viewModel: {
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.largeWorkspace.displayName),
                    snapshot: PreviewSampleData.largeWorkspace
                )
                return container.workspaceViewModel
            }()
        )
    }
}

#Preview("Search Results") {
    NavigationStack {
        WorkspaceScreen(
            viewModel: {
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
                    snapshot: PreviewSampleData.nestedWorkspace
                )
                let viewModel = container.workspaceViewModel
                viewModel.searchQuery = "read"
                return viewModel
            }()
        )
    }
}

#Preview("Loading") {
    NavigationStack {
        WorkspaceScreen(
            viewModel: {
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
                    snapshot: nil
                )
                let viewModel = container.workspaceViewModel
                viewModel.isLoading = true
                return viewModel
            }()
        )
    }
}

#Preview("Error") {
    NavigationStack {
        WorkspaceScreen(
            viewModel: {
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
                    snapshot: nil
                )
                let viewModel = container.workspaceViewModel
                viewModel.loadError = UserFacingError(
                    title: "Workspace Unavailable",
                    message: "The folder could not be refreshed.",
                    recoverySuggestion: "Try refreshing again."
                )
                return viewModel
            }()
        )
    }
}
