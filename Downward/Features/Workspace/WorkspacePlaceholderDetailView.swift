import SwiftUI

struct WorkspacePlaceholderDetailView: View {
    var body: some View {
        GradientContentUnavailableView(
            "Select a File",
            systemName: "sidebar.leading",
            color: .secondary
        ) {
            Text("Browse the workspace in the sidebar and choose a document to start editing.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    WorkspacePlaceholderDetailView()
}
