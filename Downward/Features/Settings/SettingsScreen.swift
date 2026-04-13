import SwiftUI

struct SettingsScreen: View {
    let workspaceName: String?
    let accessState: WorkspaceAccessState
    let reconnectWorkspaceAction: () -> Void
    let clearWorkspaceAction: () -> Void

    var body: some View {
        Form {
            Section("Workspace") {
                LabeledContent("Name", value: workspaceName ?? "None")
                LabeledContent("Access", value: accessDescription)
            }

            Section("Actions") {
                Button("Choose Different Folder", action: reconnectWorkspaceAction)
                Button("Clear Workspace", role: .destructive, action: clearWorkspaceAction)
            }
        }
        .navigationTitle("Settings")
    }

    private var accessDescription: String {
        switch accessState {
        case .noneSelected:
            "None Selected"
        case .restorable:
            "Restorable"
        case .ready:
            "Ready"
        case .invalid:
            "Needs Reconnect"
        }
    }
}

#Preview {
    NavigationStack {
        SettingsScreen(
            workspaceName: PreviewSampleData.nestedWorkspace.displayName,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            reconnectWorkspaceAction: {},
            clearWorkspaceAction: {}
        )
    }
}
