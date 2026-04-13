import SwiftUI

struct WorkspacePlaceholderDetailView: View {
    var body: some View {
        ContentUnavailableView(
            "Select a Folder or File",
            systemImage: "sidebar.leading",
            description: Text("Choose a folder to browse deeper or a file to trigger the document stub.")
        )
    }
}

#Preview {
    WorkspacePlaceholderDetailView()
}
