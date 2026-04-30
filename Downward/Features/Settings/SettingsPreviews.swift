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
        importedFontManager: makePreviewImportedFontManager(),
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
        importedFontManager: makePreviewImportedFontManager(),
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
        importedFontManager: makePreviewImportedFontManager(),
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
        themeStore: makePreviewThemeStore(),
        importedFontManager: makePreviewImportedFontManager(),
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

#Preview("Supporter Unlock Settings") {
    SupporterUnlockSettingsPage(
        editorAppearanceStore: EditorAppearanceStore(),
        themeStore: ThemeStore(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "preview-supporter-\(UUID().uuidString).json"),
            entitlements: ThemeEntitlementStore(hasUnlockedThemes: false)
        ),
        backAction: {}
    )
}

#Preview("Supporter Thanks Settings") {
    SupporterUnlockSettingsPage(
        editorAppearanceStore: EditorAppearanceStore(),
        themeStore: ThemeStore(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "preview-supporter-thanks-\(UUID().uuidString).json"),
            entitlements: ThemeEntitlementStore(hasUnlockedThemes: true)
        ),
        backAction: {}
    )
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
        importedFontManager: makePreviewImportedFontManager(),
        reconnectWorkspaceAction: {},
        clearWorkspaceAction: {},
        dismissAction: {}
    )
    .frame(width: 720, height: 920)
}
