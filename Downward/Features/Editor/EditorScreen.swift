import SwiftUI

struct EditorScreen: View {
    let viewModel: EditorViewModel
    let documentURL: URL

    @State private var topOverlayClearance: CGFloat = 0

    var body: some View {
        editorContent
            .background(.background)
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .editorNavigationSubtitle(viewModel.documentLocationText)
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
                        .accessibilityHint("Review options for the current file conflict.")
                    }

                    if viewModel.showsSaveStatusIndicator {
                        EditorOverlayChrome(viewModel: viewModel)
                    }
                }
            }
            .sheet(isPresented: conflictSheetBinding) {
                ConflictResolutionView(viewModel: viewModel)
            }
            .alert(item: editorAlertBinding) { error in
                Alert(
                    title: Text(error.title),
                    message: Text([error.message, error.recoverySuggestion].compactMap { $0 }.joined(separator: "\n\n")),
                    dismissButton: .default(Text("OK")) {
                        viewModel.dismissAlert()
                    }
                )
            }
    }
    @ViewBuilder
    private var editorContent: some View {
        if viewModel.currentRouteDocument != nil {
            ZStack(alignment: .topLeading) {
                MarkdownEditorTextView(
                    text: viewModel.textBinding,
                    topOverlayClearance: $topOverlayClearance,
                    documentIdentity: documentURL,
                    font: viewModel.editorUIFont,
                    syntaxMode: viewModel.markdownSyntaxMode,
                    isEditable: viewModel.isResolvingConflict == false
                        && viewModel.isShowingConflictResolution == false,
                    undoCommandToken: viewModel.undoCommandToken,
                    redoCommandToken: viewModel.redoCommandToken,
                    dismissKeyboardCommandToken: viewModel.dismissKeyboardCommandToken,
                    onEditorFocusChange: viewModel.handleEditorFocusChange(_:),
                    onUndoRedoAvailabilityChange: viewModel.updateUndoRedoAvailability(canUndo:canRedo:)
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .disabled(viewModel.isResolvingConflict || viewModel.isShowingConflictResolution)

                if viewModel.showsEmptyDocumentPlaceholder {
                    Text("Start typing…")
                        .font(viewModel.editorFont)
                        .foregroundStyle(.secondary)
                        .padding(.top, topOverlayClearance + EditorTextViewLayout.contentTopInset)
                        .padding(.leading, EditorTextViewLayout.horizontalInset)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            .ignoresSafeArea(.keyboard, edges: .bottom)
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

    private var editorAlertBinding: Binding<UserFacingError?> {
        Binding(
            get: { viewModel.alertError },
            set: { _ in viewModel.dismissAlert() }
        )
    }
}

private extension View {
    @ViewBuilder
    func editorNavigationSubtitle(_ subtitle: String?) -> some View {
        if let subtitle {
            navigationSubtitle(subtitle)
        } else {
            self
        }
    }
}

#Preview("iPad Clean") {
    NavigationSplitView {
        WorkspaceScreen(
            viewModel: {
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
                    snapshot: PreviewSampleData.nestedWorkspace,
                    document: PreviewSampleData.cleanDocument,
                    path: [.editor(PreviewSampleData.cleanDocument.url)]
                )
                return container.workspaceViewModel
            }(),
            navigationMode: .splitSidebar
        )
    } detail: {
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

#Preview("Markdown Hidden Syntax") {
    NavigationStack {
        EditorScreen(
            viewModel: {
                var document = PreviewSampleData.cleanDocument
                document.text = """
                # Weekly Note

                This has **bold**, _italic_, `code`, and a [link](https://example.com).
                """
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
                    snapshot: PreviewSampleData.nestedWorkspace,
                    document: document,
                    path: [.editor(document.url)],
                    editorAppearancePreferences: EditorAppearancePreferences(
                        fontChoice: .default,
                        fontSize: 16,
                        markdownSyntaxMode: .hiddenOutsideCurrentLine
                    )
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

#Preview("Empty File") {
    NavigationStack {
        EditorScreen(
            viewModel: {
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
                    snapshot: PreviewSampleData.nestedWorkspace,
                    document: PreviewSampleData.emptyDocument,
                    path: [.editor(PreviewSampleData.emptyDocument.url)]
                )
                return container.editorViewModel
            }(),
            documentURL: PreviewSampleData.emptyDocument.url
        )
    }
}
