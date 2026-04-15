import SwiftUI

struct EditorOverlayChrome: View {
    let viewModel: EditorViewModel

    var body: some View {
        Label(viewModel.saveStateText, systemImage: viewModel.saveStateSymbolName)
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(viewModel.saveStateText)
            .accessibilityValue(viewModel.saveFailureMessage ?? "")
            .accessibilityHint("The latest save did not complete.")
    }
}

#Preview("Save Failed") {
    EditorOverlayChrome(
        viewModel: {
            let container = AppContainer.preview(
                launchState: .workspaceReady,
                accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
                snapshot: PreviewSampleData.nestedWorkspace,
                document: PreviewSampleData.failedSaveDocument
            )
            return container.editorViewModel
        }()
    )
}
