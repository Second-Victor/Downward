import SwiftUI

struct WorkspaceRowView: View {
    enum FolderDisclosureState {
        case expanded
        case collapsed
    }

    let node: WorkspaceNode
    let isSelected: Bool
    var hierarchyDepth: Int = 0
    var folderDisclosureState: FolderDisclosureState? = nil

    var body: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: CGFloat(hierarchyDepth) * 18)

            if let folderDisclosureState {
                Image(systemName: folderDisclosureState == .expanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            } else if hierarchyDepth > 0 {
                Color.clear
                    .frame(width: 12)
            }

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
        if let folderDisclosureState {
            values.append(folderDisclosureState == .expanded ? "Expanded" : "Collapsed")
        }
        if isSelected {
            values.append("Open")
        }
        return values.joined(separator: ", ")
    }

    private var accessibilityHint: String {
        if folderDisclosureState != nil {
            return "Expands or collapses this folder."
        }

        return node.isFolder ? "Opens this folder." : "Opens this document."
    }
}

#Preview {
    List {
        WorkspaceRowView(
            node: PreviewSampleData.nestedWorkspace.rootNodes[0],
            isSelected: false,
            hierarchyDepth: 0,
            folderDisclosureState: .expanded
        )
        WorkspaceRowView(
            node: .file(
                .init(
                    url: PreviewSampleData.cleanDocument.url,
                    displayName: PreviewSampleData.cleanDocument.displayName,
                    subtitle: PreviewSampleData.cleanDocument.relativePath
                )
            ),
            isSelected: true,
            hierarchyDepth: 2
        )
    }
}
