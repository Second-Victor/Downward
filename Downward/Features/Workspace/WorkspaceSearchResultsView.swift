import SwiftUI

struct WorkspaceSearchResultsView: View {
    let viewModel: WorkspaceViewModel

    var body: some View {
        if viewModel.searchResults.isEmpty {
            ContentUnavailableView(
                "No Matching Files",
                systemImage: "magnifyingglass",
                description: Text("No Markdown or text files in this workspace match \"\(viewModel.searchQueryDescription)\".")
            )
        } else {
            List(viewModel.searchResults) { result in
                NavigationLink(value: AppRoute.editor(result.url)) {
                    WorkspaceRowView(
                        node: result.node,
                        isSelected: viewModel.isSelectedDocumentURL(result.url)
                    )
                }
            }
            .listStyle(.insetGrouped)
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
            }()
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
            }()
        )
    }
}
