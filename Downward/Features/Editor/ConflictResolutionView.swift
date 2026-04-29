import SwiftUI

struct ConflictResolutionView: View {
    let viewModel: EditorViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = viewModel.conflictError {
                        VStack(alignment: .leading, spacing: 12) {
                            Label {
                                Text(error.title)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .symbolGradient(.red)
                            }
                                .font(.headline)

                            Text(error.message)
                                .foregroundStyle(.primary)

                            if let recoverySuggestion = error.recoverySuggestion {
                                Text(recoverySuggestion)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    VStack(spacing: 12) {
                        Button("Reload From Disk") {
                            viewModel.reloadFromDisk()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isResolvingConflict)
                        .accessibilityHint("Discard in-memory text and reopen the latest disk version.")

                        Button("Overwrite Disk") {
                            viewModel.overwriteDisk()
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isResolvingConflict)
                        .accessibilityHint("Replace the disk file with the current in-memory text.")

                        Button("Keep My Edits") {
                            viewModel.preserveConflictEdits()
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isResolvingConflict)
                        .accessibilityHint("Keep your edits in memory without writing them to disk yet.")
                    }

                    if viewModel.isResolvingConflict {
                        ProgressView("Resolving Conflict")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer(minLength: 0)
                }
                .padding(24)
            }
            .navigationTitle("Resolve Conflict")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(viewModel.activeConflict != nil)
    }
}

#Preview("Modified On Disk") {
    ConflictResolutionView(
        viewModel: {
            let container = AppContainer.preview(
                launchState: .workspaceReady,
                accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
                snapshot: PreviewSampleData.nestedWorkspace,
                document: PreviewSampleData.conflictDocument
            )
            let viewModel = container.editorViewModel
            viewModel.isShowingConflictResolution = true
            return viewModel
        }()
    )
}

#Preview("Large Type") {
    ConflictResolutionView(
        viewModel: {
            let container = AppContainer.preview(
                launchState: .workspaceReady,
                accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
                snapshot: PreviewSampleData.nestedWorkspace,
                document: PreviewSampleData.conflictDocument
            )
            let viewModel = container.editorViewModel
            viewModel.isShowingConflictResolution = true
            return viewModel
        }()
    )
    .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("Missing On Disk") {
    ConflictResolutionView(
        viewModel: {
            let container = AppContainer.preview(
                launchState: .workspaceReady,
                accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
                snapshot: PreviewSampleData.nestedWorkspace,
                document: PreviewSampleData.missingDocument
            )
            let viewModel = container.editorViewModel
            viewModel.isShowingConflictResolution = true
            return viewModel
        }()
    )
}
