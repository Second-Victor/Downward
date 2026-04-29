import SwiftUI

struct RecentFilesSheet: View {
    let viewModel: WorkspaceViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if viewModel.recentFiles.isEmpty {
                GradientContentUnavailableView(
                    "No Recent Files",
                    systemName: "clock",
                    color: .secondary
                ) {
                    Text("Files you open in this workspace will appear here for quick reopen.")
                }
            } else {
                List {
                    Section {
                        ForEach(viewModel.recentFiles) { item in
                            Button {
                                viewModel.openRecentFile(item)
                                dismiss()
                            } label: {
                                RecentFileRowView(item: item)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    if let index = viewModel.recentFiles.firstIndex(of: item) {
                                        viewModel.removeRecentFiles(at: IndexSet(integer: index))
                                    }
                                }
                            }
                        }
                        .onDelete(perform: viewModel.removeRecentFiles)
                    } header: {
                        Text(viewModel.recentFiles.count == 1 ? "1 recent file" : "\(viewModel.recentFiles.count) recent files")
                            .textCase(nil)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Recent Files")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

#Preview("Populated") {
    NavigationStack {
        RecentFilesSheet(
            viewModel: {
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
                    snapshot: PreviewSampleData.nestedWorkspace,
                    recentFiles: [
                        RecentFileItem(
                            workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                            relativePath: "References/README.md",
                            displayName: "README.md",
                            lastOpenedAt: PreviewSampleData.previewDate
                        ),
                        RecentFileItem(
                            workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                            relativePath: "Inbox.md",
                            displayName: "Inbox.md",
                            lastOpenedAt: PreviewSampleData.previewDate.addingTimeInterval(-60)
                        ),
                    ]
                )
                return container.workspaceViewModel
            }()
        )
    }
}

#Preview("Duplicate Filenames") {
    NavigationStack {
        RecentFilesSheet(
            viewModel: {
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
                    snapshot: PreviewSampleData.nestedWorkspace,
                    recentFiles: [
                        RecentFileItem(
                            workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                            relativePath: "References/README.md",
                            displayName: "README.md",
                            lastOpenedAt: PreviewSampleData.previewDate
                        ),
                        RecentFileItem(
                            workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                            relativePath: "Archive/README.md",
                            displayName: "README.md",
                            lastOpenedAt: PreviewSampleData.previewDate.addingTimeInterval(-3_600)
                        ),
                    ]
                )
                return container.workspaceViewModel
            }()
        )
    }
}

#Preview("Long Paths") {
    NavigationStack {
        RecentFilesSheet(
            viewModel: {
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
                    snapshot: PreviewSampleData.nestedWorkspace,
                    recentFiles: [
                        RecentFileItem(
                            workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                            relativePath: "Projects/Client A/2026/Q2/Launch Prep/Meeting Notes/README.md",
                            displayName: "README.md",
                            lastOpenedAt: PreviewSampleData.previewDate
                        ),
                        RecentFileItem(
                            workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                            relativePath: "Inbox.md",
                            displayName: "Inbox.md",
                            lastOpenedAt: PreviewSampleData.previewDate.addingTimeInterval(-3_600)
                        ),
                    ]
                )
                return container.workspaceViewModel
            }()
        )
    }
}

#Preview("Empty") {
    NavigationStack {
        RecentFilesSheet(
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
