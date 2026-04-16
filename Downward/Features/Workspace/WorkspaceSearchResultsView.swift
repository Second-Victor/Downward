import SwiftUI

struct WorkspaceSearchResultsView: View {
    let viewModel: WorkspaceViewModel
    let navigationMode: WorkspaceNavigationMode

    var body: some View {
        if viewModel.searchResults.isEmpty {
            ScrollView {
                ContentUnavailableView(
                    "No Matching Files",
                    systemImage: "magnifyingglass",
                    description: Text("No Markdown or text files in this workspace match \"\(viewModel.searchQueryDescription)\".")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
            }
            .refreshable {
                await viewModel.refreshFromPullToRefresh()
            }
        } else {
            List(viewModel.searchResults) { result in
                if navigationMode.usesValueNavigationLinks == false {
                    Button {
                        viewModel.openDocument(result.url)
                    } label: {
                        WorkspaceRowView(
                            node: result.node
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink(value: AppRoute.editor(result.url)) {
                        WorkspaceRowView(
                            node: result.node
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await viewModel.refreshFromPullToRefresh()
            }
        }
    }
}

#Preview("Matches") {
    NavigationStack {
        WorkspaceSearchResultsView(
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

#Preview("No Results") {
    NavigationStack {
        WorkspaceSearchResultsView(
            viewModel: {
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
                    snapshot: PreviewSampleData.nestedWorkspace
                )
                let viewModel = container.workspaceViewModel
                viewModel.searchQuery = "missing"
                return viewModel
            }(),
            navigationMode: .stackPath
        )
    }
}
