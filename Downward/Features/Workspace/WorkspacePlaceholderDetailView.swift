import SwiftUI

struct WorkspacePlaceholderDetailView: View {
    var body: some View {
        ContentUnavailableView(
            "Select a Folder or File",
            systemImage: "sidebar.leading",
            description: Text("Choose a folder to browse deeper or a document to start editing.")
        )
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    WorkspacePlaceholderDetailView()
}
