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
                    description: Text("No supported text files match \"\(viewModel.searchQueryDescription)\". Try a file name or a folder path.")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
            }
            .refreshable {
                await viewModel.refreshFromPullToRefresh()
            }
        } else {
            List {
                Section {
                    ForEach(viewModel.searchResults) { result in
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
                } header: {
                    Text(viewModel.searchResultsSummaryText)
                        .textCase(nil)
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

#Preview("Long Paths") {
    NavigationStack {
        WorkspaceSearchResultsView(
            viewModel: {
                let snapshot = WorkspaceSnapshot(
                    rootURL: PreviewSampleData.workspaceRootURL,
                    displayName: "Long Path Workspace",
                    rootNodes: [
                        .folder(
                            .init(
                                url: PreviewSampleData.workspaceRootURL.appending(path: "Projects"),
                                displayName: "Projects",
                                children: [
                                    .folder(
                                        .init(
                                            url: PreviewSampleData.workspaceRootURL.appending(path: "Projects/Client A"),
                                            displayName: "Client A",
                                            children: [
                                                .folder(
                                                    .init(
                                                        url: PreviewSampleData.workspaceRootURL.appending(path: "Projects/Client A/2026"),
                                                        displayName: "2026",
                                                        children: [
                                                            .folder(
                                                                .init(
                                                                    url: PreviewSampleData.workspaceRootURL.appending(path: "Projects/Client A/2026/Q2"),
                                                                    displayName: "Q2",
                                                                    children: [
                                                                        .folder(
                                                                            .init(
                                                                                url: PreviewSampleData.workspaceRootURL.appending(path: "Projects/Client A/2026/Q2/Launch Prep"),
                                                                                displayName: "Launch Prep",
                                                                                children: [
                                                                                    .folder(
                                                                                        .init(
                                                                                            url: PreviewSampleData.workspaceRootURL.appending(path: "Projects/Client A/2026/Q2/Launch Prep/Meeting Notes"),
                                                                                            displayName: "Meeting Notes",
                                                                                            children: [
                                                                                                .file(
                                                                                                    .init(
                                                                                                        url: PreviewSampleData.workspaceRootURL.appending(path: "Projects/Client A/2026/Q2/Launch Prep/Meeting Notes/README.md"),
                                                                                                        displayName: "README.md",
                                                                                                        subtitle: "Long path example",
                                                                                                        modifiedAt: PreviewSampleData.previewDate
                                                                                                    )
                                                                                                ),
                                                                                            ]
                                                                                        )
                                                                                    ),
                                                                                ]
                                                                            )
                                                                        ),
                                                                    ]
                                                                )
                                                            ),
                                                        ]
                                                    )
                                                ),
                                            ]
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
                    accessState: .ready(displayName: snapshot.displayName),
                    snapshot: snapshot
                )
                let viewModel = container.workspaceViewModel
                viewModel.searchQuery = "read"
                return viewModel
            }(),
            navigationMode: .stackPath
        )
    }
}
