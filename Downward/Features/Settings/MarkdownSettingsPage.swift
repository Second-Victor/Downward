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

    private var createMarkdownTitleBinding: Binding<Bool> {
        Binding(
            get: { editorAppearanceStore.createMarkdownTitleFromFilename },
            set: { editorAppearanceStore.setCreateMarkdownTitleFromFilename($0) }
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
        Form {
            Section {
                Toggle(
                    "Colour Formatted Text",
                    isOn: colorFormattedTextBinding
                )
            } footer: {
                Text("Apply the markdown syntax marker colour to heading, bold, and italic text.")
                    .settingsFooterStyle()
            }

            Section {
                Toggle(
                    "Hide Markdown Formatting",
                    isOn: hideMarkdownFormattingBinding
                )
            } footer: {
                Text("Hide markdown syntax until the cursor moves into the formatted content.")
                    .settingsFooterStyle()
            }

            Section {
                Toggle(
                    "Tap to Toggle Tasks",
                    isOn: tapToToggleTasksBinding
                )
            } footer: {
                Text("Tap a task checkbox to mark it as done or undone.")
                    .settingsFooterStyle()
            }

            Section {
                Toggle(
                    "Create Title from Filename",
                    isOn: createMarkdownTitleBinding
                )
            } footer: {
                Text("Start new markdown files with a heading based on the file name.")
                    .settingsFooterStyle()
            }
        }
        .navigationTitle("Markdown")
    }
}
