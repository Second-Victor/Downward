import SwiftUI

public enum WorkspaceNavigationMode: Equatable {
    case stackPath
    case splitSidebar

    public var usesValueNavigationLinks: Bool {
        self == .stackPath
    }
}

struct WorkspaceScreen: View {
    let viewModel: WorkspaceViewModel
    let navigationMode: WorkspaceNavigationMode

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
                    showsSettingsButton: true,
                    navigationMode: navigationMode
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
            }(),
            navigationMode: .stackPath
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
            }(),
            navigationMode: .stackPath
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
            }(),
            navigationMode: .stackPath
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
            }(),
            navigationMode: .stackPath
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
            }(),
            navigationMode: .stackPath
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
            }(),
            navigationMode: .stackPath
        )
    }
}
