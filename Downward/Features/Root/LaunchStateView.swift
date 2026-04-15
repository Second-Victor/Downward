import SwiftUI

struct LaunchStateView: View {
    let title: String
    let message: String
    let symbolName: String
    let isLoading: Bool
    let primaryActionTitle: String?
    let primaryAction: () -> Void
    let secondaryActionTitle: String?
    let secondaryAction: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: symbolName)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if isLoading {
                    ProgressView("Loading")
                        .padding(.top, 4)
                }

                VStack(spacing: 12) {
                    if let primaryActionTitle {
                        Button(primaryActionTitle, action: primaryAction)
                            .buttonStyle(.borderedProminent)
                    }

                    if let secondaryActionTitle, let secondaryAction {
                        Button(secondaryActionTitle, action: secondaryAction)
                            .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: 420)
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 0)
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview("No Workspace") {
    LaunchStateView(
        title: "Choose a Workspace",
        message: "Pick one folder to browse and edit Markdown and text files.",
        symbolName: "folder.badge.plus",
        isLoading: false,
        primaryActionTitle: "Open Folder",
        primaryAction: {},
        secondaryActionTitle: nil,
        secondaryAction: nil
    )
}

#Preview("Large Type") {
    LaunchStateView(
        title: "Choose a Workspace",
        message: "Pick one folder to browse and edit Markdown and text files.",
        symbolName: "folder.badge.plus",
        isLoading: false,
        primaryActionTitle: "Open Folder",
        primaryAction: {},
        secondaryActionTitle: "Retry",
        secondaryAction: {}
    )
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Failed") {
    LaunchStateView(
        title: PreviewSampleData.failedLaunchError.title,
        message: PreviewSampleData.failedLaunchError.message,
        symbolName: "exclamationmark.triangle",
        isLoading: false,
        primaryActionTitle: "Retry Restore",
        primaryAction: {},
        secondaryActionTitle: PreviewSampleData.failedLaunchError.recoverySuggestion,
        secondaryAction: {}
    )
}
