import SwiftUI

struct WorkspaceRowView: View {
    enum FolderDisclosureState {
        case expanded
        case collapsed
    }

    let node: WorkspaceNode
    var hierarchyDepth: Int = 0
    var folderDisclosureState: FolderDisclosureState? = nil
    private let indentUnit: CGFloat = 12
    private let verticalPadding: CGFloat = 2
    private let iconColumnWidth: CGFloat = 28
    private let iconToTitleSpacing: CGFloat = 10
    private let trailingSpacing: CGFloat = 12

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: indentationWidth)

            HStack(alignment: .center, spacing: iconToTitleSpacing) {
                Image(systemName: node.isFolder ? "folder" : "doc.text")
                    .font(.title2)
                    .foregroundStyle(node.isFolder ? Color.accentColor : .secondary)
                    .frame(width: iconColumnWidth, alignment: .center)

                VStack(alignment: .leading, spacing: node.subtitle == nil ? 0 : 3) {
                    Text(node.displayName)
                        .font(.body)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: trailingSpacing)

            trailingContent
        }
        .padding(.vertical, verticalPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
    }

    @ViewBuilder
    private var trailingContent: some View {
        if let folderDisclosureState {
            HStack(spacing: 10) {
                if let itemCountText {
                    Text(itemCountText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Image(systemName: folderDisclosureState == .expanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .frame(width: 12)
                    .accessibilityHidden(true)
            }
        } else if fileTrailingMetadataVisible {
            HStack(alignment: .center, spacing: 10) {
                if let modifiedAt = node.modifiedAt {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Self.fileDateFormatter.string(from: modifiedAt))
                        Text(Self.fileTimeFormatter.string(from: modifiedAt))
                    }
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                }
            }
        }
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
        if let itemCountText {
            values.append(itemCountText)
        }
        if let folderDisclosureState {
            values.append(folderDisclosureState == .expanded ? "Expanded" : "Collapsed")
        }
        if let modifiedAt = node.modifiedAt {
            values.append("Last edited \(Self.accessibilityDateTimeFormatter.string(from: modifiedAt))")
        }
        return values.joined(separator: ", ")
    }

    private var accessibilityHint: String {
        if folderDisclosureState != nil {
            return "Expands or collapses this folder."
        }

        return node.isFolder ? "Opens this folder." : "Opens this document."
    }

    private var indentationWidth: CGFloat {
        CGFloat(hierarchyDepth) * indentUnit
    }

    private var itemCountText: String? {
        guard let itemCount = node.itemCount else {
            return nil
        }

        return String(itemCount)
    }

    private var fileTrailingMetadataVisible: Bool {
        node.modifiedAt != nil
    }

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let fileTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private static let accessibilityDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview("Folder Row") {
    List {
        WorkspaceRowView(
            node: PreviewSampleData.nestedWorkspace.rootNodes[0],
            hierarchyDepth: 0,
            folderDisclosureState: .collapsed
        )
    }
}

#Preview("Nested Folder Row") {
    List {
        WorkspaceRowView(
            node: PreviewSampleData.nestedWorkspace.rootNodes[0],
            hierarchyDepth: 1,
            folderDisclosureState: .expanded
        )
    }
}

#Preview("File Row") {
    List {
        WorkspaceRowView(
            node: .file(
                .init(
                    url: PreviewSampleData.cleanDocument.url,
                    displayName: PreviewSampleData.cleanDocument.displayName,
                    subtitle: PreviewSampleData.cleanDocument.relativePath,
                    modifiedAt: PreviewSampleData.previewDate
                )
            ),
            hierarchyDepth: 0
        )
    }
}

#Preview("Nested File Row") {
    List {
        WorkspaceRowView(
            node: .file(
                .init(
                    url: PreviewSampleData.dirtyDocument.url,
                    displayName: PreviewSampleData.dirtyDocument.displayName,
                    subtitle: PreviewSampleData.dirtyDocument.relativePath,
                    modifiedAt: PreviewSampleData.previewDate.addingTimeInterval(-1_800)
                )
            ),
            hierarchyDepth: 1
        )
    }
}

#Preview("File Row Metadata") {
    List {
        WorkspaceRowView(
            node: .file(
                .init(
                    url: PreviewSampleData.readmeDocumentURL,
                    displayName: "README.md",
                    subtitle: "References/README.md",
                    modifiedAt: PreviewSampleData.previewDate.addingTimeInterval(-5_400)
                )
            ),
            hierarchyDepth: 0
        )
    }
}
