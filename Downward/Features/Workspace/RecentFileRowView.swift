import SwiftUI

struct RecentFileRowView: View {
    let item: RecentFileItem

    private let verticalPadding: CGFloat = 2
    private let iconColumnWidth: CGFloat = 28
    private let iconToTitleSpacing: CGFloat = 10
    private let trailingSpacing: CGFloat = 12

    var body: some View {
        HStack(spacing: 0) {
            HStack(alignment: .center, spacing: iconToTitleSpacing) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.title3)
                    .symbolGradient(.secondary)
                    .frame(width: iconColumnWidth, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(.body)
                        .lineLimit(1)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: item.pathContextSymbolName)
                            .font(.caption.weight(.semibold))
                            .symbolGradient(Color(uiColor: .tertiaryLabel))
                            .accessibilityHidden(true)

                        Text(item.pathContextText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer(minLength: trailingSpacing)

            VStack(alignment: .trailing, spacing: 1) {
                Text(Self.lastOpenedDateFormatter.string(from: item.lastOpenedAt))
                Text(Self.lastOpenedTimeFormatter.string(from: item.lastOpenedAt))
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, verticalPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.displayName), \(item.fullRelativePathText)")
        .accessibilityValue("Last opened \(Self.accessibilityDateTimeFormatter.string(from: item.lastOpenedAt))")
        .accessibilityHint("Opens this recent file.")
    }

    private static let lastOpenedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let lastOpenedTimeFormatter: DateFormatter = {
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

#Preview("Workspace Root") {
    List {
        RecentFileRowView(
            item: RecentFileItem(
                workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                relativePath: "Inbox.md",
                displayName: "Inbox.md",
                lastOpenedAt: PreviewSampleData.previewDate
            )
        )
    }
}

#Preview("Duplicate Filenames") {
    List {
        RecentFileRowView(
            item: RecentFileItem(
                workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                relativePath: "References/README.md",
                displayName: "README.md",
                lastOpenedAt: PreviewSampleData.previewDate
            )
        )
        RecentFileRowView(
            item: RecentFileItem(
                workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                relativePath: "Archive/README.md",
                displayName: "README.md",
                lastOpenedAt: PreviewSampleData.previewDate.addingTimeInterval(-3_600)
            )
        )
    }
}

#Preview("Long Path") {
    List {
        RecentFileRowView(
            item: RecentFileItem(
                workspaceRootPath: PreviewSampleData.workspaceRootURL.path,
                relativePath: "Projects/Client A/2026/Q2/Launch Prep/Meeting Notes/README.md",
                displayName: "README.md",
                lastOpenedAt: PreviewSampleData.previewDate.addingTimeInterval(-7_200)
            )
        )
    }
}
