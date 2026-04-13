import SwiftUI

struct EditorScreen: View {
    let viewModel: EditorViewModel
    let documentURL: URL

    var body: some View {
        editorContent
        .background(.background)
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: documentURL) {
            viewModel.handleAppear(for: documentURL)
        }
        .onDisappear {
            viewModel.handleDisappear(for: documentURL)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if viewModel.showsConflictResolveAction {
                    Button("Resolve") {
                        viewModel.presentConflictResolution()
                    }
                }

                if viewModel.showsSaveStatusIndicator {
                    EditorOverlayChrome(viewModel: viewModel)
                }
            }
        }
        .sheet(isPresented: conflictSheetBinding) {
            ConflictResolutionView(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        if viewModel.document != nil {
            TextEditor(text: viewModel.textBinding)
                .scrollContentBackground(.hidden)
                .disabled(viewModel.isResolvingConflict || viewModel.isShowingConflictResolution)
        } else if let error = viewModel.loadError {
            ContentUnavailableView(
                error.title,
                systemImage: "exclamationmark.triangle",
                description: Text(error.message)
            )
        } else {
            ContentUnavailableView(
                "Loading Document",
                systemImage: "doc.text",
                description: Text("Opening the selected file.")
            )
        }
    }

    private var conflictSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingConflictResolution },
            set: { viewModel.isShowingConflictResolution = $0 }
        )
    }
}

#Preview("Clean") {
    NavigationStack {
        EditorScreen(
            viewModel: {
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
                    snapshot: PreviewSampleData.nestedWorkspace,
                    document: PreviewSampleData.cleanDocument,
                    path: [.editor(PreviewSampleData.cleanDocument.url)]
                )
                return container.editorViewModel
            }(),
            documentURL: PreviewSampleData.cleanDocument.url
        )
    }
}

#Preview("Dirty") {
    NavigationStack {
        EditorScreen(
            viewModel: {
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
                    snapshot: PreviewSampleData.nestedWorkspace,
                    document: PreviewSampleData.dirtyDocument,
                    path: [.editor(PreviewSampleData.dirtyDocument.url)]
                )
                return container.editorViewModel
            }(),
            documentURL: PreviewSampleData.dirtyDocument.url
        )
    }
}

#Preview("Save Failed") {
    NavigationStack {
        EditorScreen(
            viewModel: {
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
                    snapshot: PreviewSampleData.nestedWorkspace,
                    document: PreviewSampleData.failedSaveDocument,
                    path: [.editor(PreviewSampleData.failedSaveDocument.url)]
                )
                return container.editorViewModel
            }(),
            documentURL: PreviewSampleData.failedSaveDocument.url
        )
    }
}

#Preview("Failed Load") {
    NavigationStack {
        EditorScreen(
            viewModel: {
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
                    snapshot: PreviewSampleData.nestedWorkspace,
                    document: nil,
                    path: [.editor(PreviewSampleData.failedLoadDocumentURL)]
                )
                container.session.editorLoadError = PreviewSampleData.failedLoadError
                return container.editorViewModel
            }(),
            documentURL: PreviewSampleData.failedLoadDocumentURL
        )
    }
}

#Preview("Conflict Preserved") {
    NavigationStack {
        EditorScreen(
            viewModel: {
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
                    snapshot: PreviewSampleData.nestedWorkspace,
                    document: PreviewSampleData.preservedConflictDocument,
                    path: [.editor(PreviewSampleData.preservedConflictDocument.url)]
                )
                return container.editorViewModel
            }(),
            documentURL: PreviewSampleData.preservedConflictDocument.url
        )
    }
}
