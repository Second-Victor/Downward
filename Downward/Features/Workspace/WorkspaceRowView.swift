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
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
    }

    private var accessibilityLabel: String {
        if let subtitle = node.subtitle {
            "\(node.displayName), \(subtitle)"
        } else {
            node.displayName
        }
    }

    private var accessibilityValue: String {
        var values: [String] = [node.isFolder ? "Folder" : "File"]
        if isSelected {
            values.append("Open")
        }
        return values.joined(separator: ", ")
    }

    private var accessibilityHint: String {
        node.isFolder ? "Opens this folder." : "Opens this document."
    }
}

#Preview {
    List {
        WorkspaceRowView(node: PreviewSampleData.nestedWorkspace.rootNodes[0], isSelected: false)
        WorkspaceRowView(node: PreviewSampleData.nestedWorkspace.rootNodes[3], isSelected: true)
    }
}
