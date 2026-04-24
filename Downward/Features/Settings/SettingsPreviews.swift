import SwiftUI

#Preview("Settings Home - Workspace Loaded") {
    SettingsScreen(
        workspaceName: PreviewSampleData.nestedWorkspace.displayName,
        accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
        editorAppearanceStore: EditorAppearanceStore(
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .systemMonospaced,
                fontSize: 15,
                markdownSyntaxMode: .visible
            )
        ),
        themeStore: makePreviewThemeStore(),
        reconnectWorkspaceAction: {},
        clearWorkspaceAction: {}
    )
}

#Preview("Settings Home - No Workspace") {
    SettingsScreen(
        workspaceName: nil,
        accessState: .noneSelected,
        editorAppearanceStore: EditorAppearanceStore(),
        themeStore: makePreviewThemeStore(),
        reconnectWorkspaceAction: {},
        clearWorkspaceAction: {}
    )
}

#Preview("Settings Large Type") {
    SettingsScreen(
        workspaceName: PreviewSampleData.nestedWorkspace.displayName,
        accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
        editorAppearanceStore: EditorAppearanceStore(
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .systemMonospaced,
                fontSize: 20,
                markdownSyntaxMode: .hiddenOutsideCurrentLine
            )
        ),
        themeStore: makePreviewThemeStore(),
        reconnectWorkspaceAction: {},
        clearWorkspaceAction: {}
    )
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Editor Settings") {
    EditorSettingsPage(
        editorAppearanceStore: EditorAppearanceStore(
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .systemMonospaced,
                fontSize: 15
            )
        ),
        backAction: {}
    )
}

#Preview("Theme Settings") {
    ThemeSettingsPage(
        editorAppearanceStore: EditorAppearanceStore(),
        themeStore: makePreviewThemeStore(),
        push: { _ in },
        backAction: {}
    )
}

#Preview("New Theme") {
    ThemeEditorSettingsPage(
        editorAppearanceStore: EditorAppearanceStore(),
        themeStore: makePreviewThemeStore(),
        editing: nil,
        backAction: {}
    )
}

#Preview("Markdown Settings") {
    MarkdownSettingsPage(
        editorAppearanceStore: EditorAppearanceStore(
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .systemMonospaced,
                fontSize: 15
            )
        ),
        backAction: {}
    )
}

#Preview("Tips Settings") {
    TipsSettingsPage(backAction: {})
}

#Preview("Information Settings") {
    InformationSettingsPage(push: { _ in }, backAction: {})
}

#Preview("About Settings") {
    AboutSettingsPage(backAction: {})
}

#Preview("iPad Settings Sheet") {
    SettingsScreen(
        workspaceName: PreviewSampleData.nestedWorkspace.displayName,
        accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
        editorAppearanceStore: EditorAppearanceStore(),
        themeStore: makePreviewThemeStore(),
        reconnectWorkspaceAction: {},
        clearWorkspaceAction: {},
        dismissAction: {}
    )
    .frame(width: 720, height: 920)
}
