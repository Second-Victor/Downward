import SwiftUI

struct WorkspaceSettingsPresentation: Equatable {
    let currentFolderName: String
    let canClearWorkspace: Bool

    init(workspaceName: String?, accessState: WorkspaceAccessState) {
        self.currentFolderName = workspaceName ?? "None"
        switch accessState {
        case .noneSelected:
            canClearWorkspace = false
        case .restorable, .ready, .invalid:
            canClearWorkspace = true
        }
    }
}

struct WorkspaceSettingsPage: View {
    let workspaceName: String?
    let accessState: WorkspaceAccessState
    let changeWorkspaceAction: () -> Void
    let clearWorkspaceAction: () -> Void

    @State private var isShowingClearConfirmation = false

    private var presentation: WorkspaceSettingsPresentation {
        WorkspaceSettingsPresentation(
            workspaceName: workspaceName,
            accessState: accessState
        )
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(presentation.currentFolderName)
                        .foregroundStyle(.secondary)
                } label: {
                    SettingsHomeLabel(
                        title: "Current Folder",
                        systemName: "folder",
                        colors: [.blue]
                    )
                }

                Button(action: changeWorkspaceAction) {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.badge.plus")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.red, .blue)
                            .frame(width: 22)
                            .accessibilityHidden(true)

                        Text("Change Folder…")
                    }
                }
            } footer: {
                Text("The workspace folder is the root directory shown in the file browser.")
                    .settingsFooterStyle()
            }

            if presentation.canClearWorkspace {
                Section {
                    Button(role: .destructive) {
                        isShowingClearConfirmation = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "xmark.circle")
                                .frame(width: 22)
                                .accessibilityHidden(true)

                            Text("Clear Workspace")
                        }
                    }
                } footer: {
                    Text("This removes the saved folder selection and closes the current workspace.")
                        .settingsFooterStyle()
                }
            }
        }
        .navigationTitle("Workspace")
        .fontDesign(.rounded)
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
}
