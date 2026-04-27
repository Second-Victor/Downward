import SwiftUI

struct MarkdownSettingsPage: View {
    let editorAppearanceStore: EditorAppearanceStore
    let backAction: () -> Void

    private var colorFormattedTextBinding: Binding<Bool> {
        Binding(
            get: { editorAppearanceStore.colorFormattedText },
            set: { editorAppearanceStore.setColorFormattedText($0) }
        )
    }

    private var tapToToggleTasksBinding: Binding<Bool> {
        Binding(
            get: { editorAppearanceStore.tapToToggleTasks },
            set: { editorAppearanceStore.setTapToToggleTasks($0) }
        )
    }

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
                    isOn: colorFormattedTextBinding
                )
            }
            SettingsHelperText(
                "Apply the markdown syntax marker colour to heading, bold, and italic text."
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
                    isOn: tapToToggleTasksBinding
                )
            }
            SettingsHelperText("Tap a task checkbox to mark it as done or undone.")
        }
    }
}
