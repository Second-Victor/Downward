import SwiftUI

struct SettingsScreen: View {
    let workspaceName: String?
    let accessState: WorkspaceAccessState
    let reconnectWorkspaceAction: () -> Void
    let clearWorkspaceAction: () -> Void

    @State private var isShowingClearConfirmation = false

    var body: some View {
        Form {
            Section("Workspace") {
                LabeledContent("Name", value: workspaceName ?? "None")
                LabeledContent("Access", value: accessDescription)
            }

            Section("Actions") {
                Button(reconnectButtonTitle, action: reconnectWorkspaceAction)
                Button("Clear Workspace", role: .destructive) {
                    isShowingClearConfirmation = true
                }
                .disabled(canClearWorkspace == false)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Clear Workspace",
            isPresented: $isShowingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Workspace", role: .destructive, action: clearWorkspaceAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved folder selection and closes the current workspace.")
        }
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

    private var reconnectButtonTitle: String {
        switch accessState {
        case .noneSelected:
            "Choose Workspace"
        case .restorable, .ready, .invalid:
            "Reconnect Workspace"
        }
    }

    private var canClearWorkspace: Bool {
        switch accessState {
        case .noneSelected:
            false
        case .restorable, .ready, .invalid:
            true
        }
    }
}

#Preview("Workspace Loaded") {
    NavigationStack {
        SettingsScreen(
            workspaceName: PreviewSampleData.nestedWorkspace.displayName,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            reconnectWorkspaceAction: {},
            clearWorkspaceAction: {}
        )
    }
}

#Preview("No Workspace") {
    NavigationStack {
        SettingsScreen(
            workspaceName: nil,
            accessState: .noneSelected,
            reconnectWorkspaceAction: {},
            clearWorkspaceAction: {}
        )
    }
}
