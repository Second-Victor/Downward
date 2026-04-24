import SwiftUI

struct MarkdownSettingsPage: View {
    let editorAppearanceStore: EditorAppearanceStore
    let backAction: () -> Void

    @State private var colorFormattedText = true
    @State private var tapToToggleTasks = true

    private var hideMarkdownFormattingBinding: Binding<Bool> {
        Binding(
            get: { editorAppearanceStore.markdownSyntaxMode == .hiddenOutsideCurrentLine },
            set: { isHidden in
                editorAppearanceStore.setMarkdownSyntaxMode(
                    isHidden ? .hiddenOutsideCurrentLine : .visible
                )
            }
        )
    }

    var body: some View {
        SettingsShell {
            SettingsPageHeader(title: "Markdown", backAction: backAction)

            SettingsCard {
                SettingsToggleRow(
                    title: "Colour Formatted Text",
                    isOn: $colorFormattedText,
                    isEnabled: false,
                    accessibilityHint: "The current renderer always applies theme styling; a separate toggle is not implemented yet."
                )
            }
            SettingsHelperText(
                "Apply the theme's accent colour to heading, bold, and italic text, matching the syntax markers."
            )

            SettingsCard {
                SettingsToggleRow(
                    title: "Hide Markdown Formatting",
                    isOn: hideMarkdownFormattingBinding
                )
            }
            SettingsHelperText("Hide markdown syntax until the cursor moves into the formatted content.")

            SettingsCard {
                SettingsToggleRow(
                    title: "Tap to Toggle Tasks",
                    isOn: $tapToToggleTasks,
                    isEnabled: false,
                    accessibilityHint: "Task checkbox tapping is not implemented yet."
                )
            }
            SettingsHelperText("Tap a task checkbox to mark it as done or undone.")
        }
    }
}
