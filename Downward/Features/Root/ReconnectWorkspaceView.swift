import SwiftUI

struct ReconnectWorkspaceView: View {
    let workspaceName: String
    let error: UserFacingError
    let reconnectAction: () -> Void
    let clearAction: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text(error.title)
                    .font(.title2.weight(.semibold))
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
                Button("Clear Selection", action: clearAction)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: 420)
        .padding(24)
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
