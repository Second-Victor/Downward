import SwiftUI

struct ReconnectWorkspaceView: View {
    let workspaceName: String
    let error: UserFacingError
    let reconnectAction: () -> Void
    let clearAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(error.title)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("\(workspaceName) is no longer accessible.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(error.message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    Button("Reconnect Folder", action: reconnectAction)
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Choose the workspace folder again to restore access.")
                    Button("Clear Selection", action: clearAction)
                        .buttonStyle(.bordered)
                        .accessibilityHint("Remove the saved workspace and return to the no-workspace screen.")
                }
            }
            .frame(maxWidth: 420)
            .padding(24)
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    ReconnectWorkspaceView(
        workspaceName: PreviewSampleData.nestedWorkspace.displayName,
        error: PreviewSampleData.invalidWorkspaceError,
        reconnectAction: {},
        clearAction: {}
    )
}

#Preview("Large Type") {
    ReconnectWorkspaceView(
        workspaceName: PreviewSampleData.nestedWorkspace.displayName,
        error: PreviewSampleData.invalidWorkspaceError,
        reconnectAction: {},
        clearAction: {}
    )
    .environment(\.dynamicTypeSize, .accessibility3)
}
