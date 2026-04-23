import SwiftUI

struct SettingsScreen: View {
    let workspaceName: String?
    let accessState: WorkspaceAccessState
    let editorAppearanceStore: EditorAppearanceStore
    let reconnectWorkspaceAction: () -> Void
    let clearWorkspaceAction: () -> Void
    var dismissAction: (() -> Void)? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isShowingClearConfirmation = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsWorkspaceSummaryCard(
                        workspaceName: workspaceName,
                        accessDescription: accessDescription,
                        helperText: accessibilityAccessHint,
                        isWorkspaceReady: isWorkspaceReady
                    )

                    SettingsSectionBlock(
                        title: "Editor",
                        detail: "Live editor preferences that apply immediately to the current document."
                    ) {
                        SettingsCard {
                            VStack(spacing: 0) {
                                SettingsCardRow {
                                    LabeledContent {
                                        Picker("Font Family", selection: fontChoiceBinding) {
                                            ForEach(editorAppearanceStore.availableFontChoices, id: \.self) { choice in
                                                Text(choice.displayName).tag(choice)
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                    } label: {
                                        SettingsRowLabel(
                                            title: "Font Family",
                                            caption: "Used for the live editor and placeholder preview."
                                        )
                                    }
                                }

                                SettingsCardDivider()

                                SettingsCardRow {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                                            SettingsRowLabel(
                                                title: "Font Size",
                                                caption: "Applies immediately without reopening the document."
                                            )
                                            Spacer(minLength: 16)
                                            Text(fontSizeText)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                                .monospacedDigit()
                                        }

                                        Stepper(value: fontSizeBinding, in: 12...24, step: 1) {
                                            Text("Font Size")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        .labelsHidden()
                                    }
                                }
                            }
                        }

                        SettingsEditorPreviewCard(editorAppearanceStore: editorAppearanceStore)
                    }

                    SettingsSectionBlock(
                        title: "Markdown",
                        detail: "Controls how markdown syntax appears while you edit."
                    ) {
                        SettingsCard {
                            VStack(spacing: 0) {
                                SettingsCardRow {
                                    LabeledContent {
                                        Picker("Markdown Display", selection: markdownSyntaxModeBinding) {
                                            ForEach(MarkdownSyntaxMode.allCases, id: \.self) { mode in
                                                Text(mode.displayName).tag(mode)
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                    } label: {
                                        SettingsRowLabel(
                                            title: "Markdown Display",
                                            caption: editorAppearanceStore.markdownSyntaxMode.previewDescription
                                        )
                                    }
                                }
                            }
                        }
                    }

                    SettingsSectionBlock(
                        title: "Workspace",
                        detail: "Connection status and workspace maintenance for the currently selected folder."
                    ) {
                        SettingsCard {
                            VStack(spacing: 0) {
                                SettingsCardRow {
                                    LabeledContent("Name", value: workspaceName ?? "None")
                                        .foregroundStyle(workspaceName == nil ? .secondary : .primary)
                                }

                                SettingsCardDivider()

                                SettingsCardRow {
                                    LabeledContent("Access", value: accessDescription)
                                        .accessibilityHint(accessibilityAccessHint)
                                }
                            }
                        }

                        SettingsCard {
                            VStack(spacing: 0) {
                                Button(action: reconnectWorkspaceAction) {
                                    SettingsActionRow(
                                        title: reconnectButtonTitle,
                                        caption: reconnectHint,
                                        systemImage: accessState == .noneSelected ? "folder.badge.plus" : "arrow.clockwise"
                                    )
                                }
                                .buttonStyle(.plain)

                                SettingsCardDivider()

                                Button(role: .destructive) {
                                    isShowingClearConfirmation = true
                                } label: {
                                    SettingsActionRow(
                                        title: "Clear Workspace",
                                        caption: "Removes the saved workspace and closes any open document.",
                                        systemImage: "trash"
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(canClearWorkspace == false)
                            }
                        }
                    }

                    SettingsSectionBlock(
                        title: "Coming Next",
                        detail: "Future settings are shown here intentionally so the current surface stays truthful."
                    ) {
                        SettingsCard {
                            VStack(spacing: 0) {
                                SettingsPlaceholderRow(
                                    title: "Theme Management",
                                    caption: "Custom editor themes and live color editing will land here later.",
                                    systemImage: "paintpalette"
                                )

                                SettingsCardDivider()

                                SettingsPlaceholderRow(
                                    title: "Theme Import / Export",
                                    caption: "JSON theme sharing is planned, but not shipping yet.",
                                    systemImage: "square.and.arrow.down"
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: contentWidth, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(dismissAction == nil ? .large : .inline)
        .toolbar {
            if let dismissAction {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: dismissAction)
                }
            }
        }
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

    private var contentWidth: CGFloat? {
        horizontalSizeClass == .regular ? 720 : nil
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 28 : 20
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

    private var markdownSyntaxModeBinding: Binding<MarkdownSyntaxMode> {
        Binding(
            get: { editorAppearanceStore.markdownSyntaxMode },
            set: { editorAppearanceStore.setMarkdownSyntaxMode($0) }
        )
    }

    private var fontSizeText: String {
        "\(Int(editorAppearanceStore.fontSize)) pt"
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

    private var isWorkspaceReady: Bool {
        if case .ready = accessState {
            return true
        }

        return false
    }
}

private struct SettingsSectionBlock<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            content
        }
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
        )
    }
}

private struct SettingsCardRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsCardDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 18)
    }
}

private struct SettingsRowLabel: View {
    let title: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body.weight(.medium))

            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsActionRow: View {
    let title: String
    let caption: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)

            SettingsRowLabel(title: title, caption: caption)

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsPlaceholderRow: View {
    let title: String
    let caption: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            SettingsRowLabel(title: title, caption: caption)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsWorkspaceSummaryCard: View {
    let workspaceName: String?
    let accessDescription: String
    let helperText: String
    let isWorkspaceReady: Bool

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.14))
                            .frame(width: 44, height: 44)

                        Image(systemName: workspaceName == nil ? "gearshape" : "folder")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Downward Settings")
                            .font(.headline)

                        Text(workspaceName ?? "No workspace selected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 12)

                    Text(accessDescription)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(isWorkspaceReady ? .green : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill((isWorkspaceReady ? Color.green : Color.secondary).opacity(0.12))
                        )
                }

                Text(helperText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
    }
}

private struct SettingsEditorPreviewCard: View {
    let editorAppearanceStore: EditorAppearanceStore

    var body: some View {
        let resolvedTheme = editorAppearanceStore.resolvedTheme

        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Live Preview")
                        .font(.headline)

                    Spacer(minLength: 12)

                    Text(editorAppearanceStore.markdownSyntaxMode.displayName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Example.md")
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: resolvedTheme.secondaryText))

                    Text("# Heading")
                        .font(editorAppearanceStore.editorFont)
                        .foregroundStyle(Color(uiColor: resolvedTheme.headingText))

                    Text("A short line of text.")
                        .font(editorAppearanceStore.editorFont)
                        .foregroundStyle(Color(uiColor: resolvedTheme.primaryText))

                    Text("Syntax markers follow the selected markdown mode.")
                        .font(.footnote)
                        .foregroundStyle(Color(uiColor: resolvedTheme.secondaryText))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: resolvedTheme.editorBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
                )
            }
            .padding(18)
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
                    fontSize: 20,
                    markdownSyntaxMode: .hiddenOutsideCurrentLine
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

#Preview("iPad Sheet") {
    NavigationStack {
        SettingsScreen(
            workspaceName: PreviewSampleData.nestedWorkspace.displayName,
            accessState: .ready(displayName: PreviewSampleData.nestedWorkspace.displayName),
            editorAppearanceStore: EditorAppearanceStore(),
            reconnectWorkspaceAction: {},
            clearWorkspaceAction: {},
            dismissAction: {}
        )
    }
    .frame(width: 720, height: 900)
}
