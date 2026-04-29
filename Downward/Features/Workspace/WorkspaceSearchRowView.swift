import SwiftUI

struct WorkspaceSearchRowView: View {
    let result: WorkspaceSearchResult

    private let verticalPadding: CGFloat = 2
    private let iconColumnWidth: CGFloat = 28
    private let iconToTitleSpacing: CGFloat = 10
    private let trailingSpacing: CGFloat = 12

    var body: some View {
        HStack(spacing: 0) {
            HStack(alignment: .center, spacing: iconToTitleSpacing) {
                Image(systemName: "doc.text")
                    .font(.title2)
                    .symbolGradient(.secondary)
                    .frame(width: iconColumnWidth, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    Text(result.displayName)
                        .font(.body)
                        .lineLimit(1)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: result.pathContextSymbolName)
                            .font(.caption.weight(.semibold))
                            .symbolGradient(Color(uiColor: .tertiaryLabel))
                            .accessibilityHidden(true)

                        Text(result.pathContextText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer(minLength: trailingSpacing)

            trailingMetadata
        }
        .padding(.vertical, verticalPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(result.displayName), \(result.fullRelativePathText)")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Opens this document from search results.")
    }

    @ViewBuilder
    private var trailingMetadata: some View {
        if let modifiedAt = result.modifiedAt {
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

    private var accessibilityValue: String {
        if let modifiedAt = result.modifiedAt {
            return "Last edited \(Self.accessibilityDateTimeFormatter.string(from: modifiedAt))"
        }

        return "Search result"
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

#Preview("Search Result") {
    List {
        WorkspaceSearchRowView(
            result: .init(
                url: PreviewSampleData.readmeDocumentURL,
                displayName: "README.md",
                relativePath: "References/README.md",
                modifiedAt: PreviewSampleData.previewDate
            )
        )
    }
}

#Preview("Duplicate Filenames") {
    List {
        WorkspaceSearchRowView(
            result: .init(
                url: PreviewSampleData.readmeDocumentURL,
                displayName: "README.md",
                relativePath: "References/README.md",
                modifiedAt: PreviewSampleData.previewDate
            )
        )
        WorkspaceSearchRowView(
            result: .init(
                url: PreviewSampleData.archiveURL.appending(path: "README.md"),
                displayName: "README.md",
                relativePath: "Archive/README.md",
                modifiedAt: PreviewSampleData.previewDate.addingTimeInterval(-3_600)
            )
        )
        WorkspaceSearchRowView(
            result: .init(
                url: PreviewSampleData.inboxDocumentURL,
                displayName: "Inbox.md",
                relativePath: "Inbox.md",
                modifiedAt: PreviewSampleData.previewDate.addingTimeInterval(-7_200)
            )
        )
    }
}

#Preview("Long Path Context") {
    List {
        WorkspaceSearchRowView(
            result: .init(
                url: PreviewSampleData.workspaceRootURL.appending(path: "Projects/Client A/2026/Q2/Launch Prep/Meeting Notes/README.md"),
                displayName: "README.md",
                relativePath: "Projects/Client A/2026/Q2/Launch Prep/Meeting Notes/README.md",
                modifiedAt: PreviewSampleData.previewDate.addingTimeInterval(-10_800)
            )
        )
        WorkspaceSearchRowView(
            result: .init(
                url: PreviewSampleData.inboxDocumentURL,
                displayName: "Inbox.md",
                relativePath: "Inbox.md",
                modifiedAt: PreviewSampleData.previewDate.addingTimeInterval(-14_400)
            )
        )
    }
}
