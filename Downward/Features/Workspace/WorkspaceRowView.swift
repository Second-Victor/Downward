import SwiftUI

struct WorkspaceRowView: View {
    let node: WorkspaceNode
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: node.isFolder ? "folder.fill" : "doc.text")
                .foregroundStyle(node.isFolder ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.displayName)
                    .font(.body)

                if let subtitle = node.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            } else if node.isFolder {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    List {
        WorkspaceRowView(node: PreviewSampleData.nestedWorkspace.rootNodes[0], isSelected: false)
        WorkspaceRowView(node: PreviewSampleData.nestedWorkspace.rootNodes[3], isSelected: true)
    }
}
