import SwiftUI

struct WorkspacePlaceholderDetailView: View {
    var body: some View {
        ContentUnavailableView(
            "Select a File",
            systemImage: "sidebar.leading",
            description: Text("Browse the workspace in the sidebar and choose a document to start editing.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    WorkspacePlaceholderDetailView()
}
