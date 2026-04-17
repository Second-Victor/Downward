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
                if navigationMode.usesValueNavigationLinks {
                    NavigationLink(value: AppRoute.trustedEditor(result.url, result.relativePath)) {
                        WorkspaceSearchRowView(result: result)
                    }
                } else {
                    Button {
                        viewModel.openSearchResult(result)
                    } label: {
                        WorkspaceSearchRowView(result: result)
                    }
                    .buttonStyle(.plain)
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

#Preview("Duplicate Filenames") {
    NavigationStack {
        WorkspaceSearchResultsView(
            viewModel: {
                let duplicateSnapshot = WorkspaceSnapshot(
                    rootURL: PreviewSampleData.workspaceRootURL,
                    displayName: "Duplicate Workspace",
                    rootNodes: [
                        .folder(
                            .init(
                                url: PreviewSampleData.referencesURL,
                                displayName: "References",
                                children: [
                                    .file(
                                        .init(
                                            url: PreviewSampleData.readmeDocumentURL,
                                            displayName: "README.md",
                                            subtitle: "References/README.md",
                                            modifiedAt: PreviewSampleData.previewDate
                                        )
                                    ),
                                ]
                            )
                        ),
                        .folder(
                            .init(
                                url: PreviewSampleData.archiveURL,
                                displayName: "Archive",
                                children: [
                                    .file(
                                        .init(
                                            url: PreviewSampleData.archiveURL.appending(path: "README.md"),
                                            displayName: "README.md",
                                            subtitle: "Archive/README.md",
                                            modifiedAt: PreviewSampleData.previewDate.addingTimeInterval(-3_600)
                                        )
                                    ),
                                ]
                            )
                        ),
                    ],
                    lastUpdated: PreviewSampleData.previewDate
                )
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: duplicateSnapshot.displayName),
                    snapshot: duplicateSnapshot
                )
                let viewModel = container.workspaceViewModel
                viewModel.searchQuery = "readme"
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
