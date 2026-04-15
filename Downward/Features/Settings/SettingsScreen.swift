import SwiftUI

struct SettingsScreen: View {
    let workspaceName: String?
    let accessState: WorkspaceAccessState
    let editorAppearanceStore: EditorAppearanceStore
    let reconnectWorkspaceAction: () -> Void
    let clearWorkspaceAction: () -> Void

    @State private var isShowingClearConfirmation = false

    var body: some View {
        Form {
            Section("Workspace") {
                LabeledContent("Name", value: workspaceName ?? "None")
                LabeledContent("Access", value: accessDescription)
                    .accessibilityHint(accessibilityAccessHint)
            }

            Section("Editor Appearance") {
                Picker("Font Family", selection: fontChoiceBinding) {
                    ForEach(editorAppearanceStore.availableFontChoices, id: \.self) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }

                Stepper(value: fontSizeBinding, in: 12...24, step: 1) {
                    LabeledContent("Font Size", value: fontSizeText)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Example.md")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("# Sample\nA short line of text.")
                        .font(editorAppearanceStore.editorFont)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Editor font preview")
                .accessibilityValue("\(editorAppearanceStore.selectedFontChoice.displayName), \(fontSizeText) points")
            }

            Section("Actions") {
                Button(reconnectButtonTitle, action: reconnectWorkspaceAction)
                    .accessibilityHint(reconnectHint)
                Button("Clear Workspace", role: .destructive) {
                    isShowingClearConfirmation = true
                }
                .disabled(canClearWorkspace == false)
                .accessibilityHint("Removes the saved workspace and closes any open document.")
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

    private var fontChoiceBinding: Binding<EditorFontChoice> {
        Binding(
            get: { editorAppearanceStore.selectedFontChoice },
            set: { editorAppearanceStore.setFontChoice($0) }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { editorAppearanceStore.fontSize },
            set: { editorAppearanceStore.setFontSize($0) }
        )
    }

    private var fontSizeText: String {
        "\(Int(editorAppearanceStore.fontSize))"
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

    private var reconnectHint: String {
        switch accessState {
        case .noneSelected:
            "Choose a folder from Files."
        case .restorable, .ready, .invalid:
            "Choose the workspace folder again."
        }
    }

    private var accessibilityAccessHint: String {
        switch accessState {
        case .noneSelected:
            "No workspace is currently selected."
        case .restorable:
            "A saved workspace can be restored."
        case .ready:
            "The current workspace is available."
        case .invalid:
            "The saved workspace needs to be reconnected."
        }
    }
}

#Preview("Workspace Loaded") {
    NavigationStack {
        SettingsScreen(
            workspaceName: PreviewSampleData.nestedWorkspace.displayName,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            editorAppearanceStore: EditorAppearanceStore(),
            reconnectWorkspaceAction: {},
            clearWorkspaceAction: {}
        )
    }
}

#Preview("Large Type") {
    NavigationStack {
        SettingsScreen(
            workspaceName: PreviewSampleData.nestedWorkspace.displayName,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            editorAppearanceStore: EditorAppearanceStore(
                initialPreferences: EditorAppearancePreferences(
                    fontChoice: .systemMonospaced,
                    fontSize: 20
                )
            ),
            reconnectWorkspaceAction: {},
            clearWorkspaceAction: {}
        )
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("No Workspace") {
    NavigationStack {
        SettingsScreen(
            workspaceName: nil,
            accessState: .noneSelected,
            editorAppearanceStore: EditorAppearanceStore(),
            reconnectWorkspaceAction: {},
            clearWorkspaceAction: {}
        )
    }
}
