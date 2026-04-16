import SwiftUI

struct RecentFilesSheet: View {
    let viewModel: WorkspaceViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if viewModel.recentFiles.isEmpty {
                ContentUnavailableView(
                    "No Recent Files",
                    systemImage: "clock",
                    description: Text("Files you open in this workspace will appear here for quick reopen.")
                )
            } else {
                List(viewModel.recentFiles) { item in
                    Button {
                        viewModel.openRecentFile(item)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName)
                                .foregroundStyle(.primary)
                            Text(item.relativePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
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
