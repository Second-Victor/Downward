import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsHomeSummary: Equatable {
    let fontName: String
    let themeName: String
    let workspaceName: String
    let appearanceName: String

    @MainActor
    init(
        workspaceName: String?,
        editorAppearanceStore: EditorAppearanceStore,
        selectedTheme: EditorTheme = .adaptive,
        appearanceName: String = "System"
    ) {
        self.fontName = SettingsFontOption.displayName(for: editorAppearanceStore.selectedFontChoice)
        self.themeName = selectedTheme.label
        self.workspaceName = workspaceName ?? "None"
        self.appearanceName = appearanceName
    }
}

enum SettingsPlaceholderFeature: Equatable {
    case lineNumbers
    case largerHeadingText
    case colorFormattedTextToggle
    case tapToToggleTasks
    case tipsPurchases
    case rateTheApp
    case legalLinks

    nonisolated var isImplemented: Bool {
        false
    }
}

struct SettingsScreen: View {
    let workspaceName: String?
    let accessState: WorkspaceAccessState
    let editorAppearanceStore: EditorAppearanceStore
    let themeStore: ThemeStore
    let reconnectWorkspaceAction: () -> Void
    let clearWorkspaceAction: () -> Void
    var dismissAction: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppColorScheme.storageKey) private var appColorSchemeRaw = AppColorScheme.system.rawValue
    @State private var navigationPath: [SettingsPage] = []
    @State private var isShowingWorkspaceActions = false
    @State private var isShowingClearConfirmation = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            SettingsHomePage(
                summary: summary,
                appColorScheme: appColorSchemeBinding,
                accessState: accessState,
                doneAction: done,
                workspaceAction: { isShowingWorkspaceActions = true }
            )
            .navigationDestination(for: SettingsPage.self) { page in
                destination(for: page)
            }
        }
        .confirmationDialog(
            "Workspace",
            isPresented: $isShowingWorkspaceActions,
            titleVisibility: .visible
        ) {
            Button(reconnectButtonTitle, action: reconnectWorkspaceAction)

            Button("Clear Workspace", role: .destructive) {
                isShowingClearConfirmation = true
            }
            .disabled(canClearWorkspace == false)

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(workspaceActionMessage)
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

    @ViewBuilder
    private func destination(for page: SettingsPage) -> some View {
        switch page {
        case .home:
            EmptyView()
        case .editor:
            EditorSettingsPage(
                editorAppearanceStore: editorAppearanceStore,
                backAction: pop
            )
        case .theme:
            ThemeSettingsPage(
                editorAppearanceStore: editorAppearanceStore,
                themeStore: themeStore,
                push: push,
                backAction: pop
            )
        case .newTheme:
            ThemeEditorSettingsPage(
                editorAppearanceStore: editorAppearanceStore,
                themeStore: themeStore,
                editing: nil,
                backAction: pop
            )
        case let .editTheme(id):
            if let theme = themeStore.theme(withID: id) {
                ThemeEditorSettingsPage(
                    editorAppearanceStore: editorAppearanceStore,
                    themeStore: themeStore,
                    editing: theme,
                    backAction: pop
                )
            } else {
                ContentUnavailableView("Theme Missing", systemImage: "paintpalette", description: Text("The selected custom theme could not be found."))
            }
        case .markdown:
            MarkdownSettingsPage(
                editorAppearanceStore: editorAppearanceStore,
                backAction: pop
            )
        case .tips:
            TipsSettingsPage(backAction: pop)
        case .information:
            InformationSettingsPage(
                push: push,
                backAction: pop
            )
        case .about:
            AboutSettingsPage(backAction: pop)
        }
    }

    private var summary: SettingsHomeSummary {
        SettingsHomeSummary(
            workspaceName: workspaceName,
            editorAppearanceStore: editorAppearanceStore,
            selectedTheme: themeStore.resolve(editorAppearanceStore.selectedThemeID),
            appearanceName: appColorSchemeBinding.wrappedValue.label
        )
    }

    private var appColorSchemeBinding: Binding<AppColorScheme> {
        Binding(
            get: { AppColorScheme(rawValue: appColorSchemeRaw) ?? .system },
            set: { appColorSchemeRaw = $0.rawValue }
        )
    }

    private var reconnectButtonTitle: String {
        switch accessState {
        case .noneSelected:
            "Choose Workspace"
        case .restorable, .ready, .invalid:
            "Reconnect Workspace"
        }
    }

    private var workspaceActionMessage: String {
        switch accessState {
        case .noneSelected:
            "Choose a folder from Files."
        case .restorable, .ready, .invalid:
            "Reconnect or clear the current workspace."
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

    private func push(_ page: SettingsPage) {
        navigationPath.append(page)
    }

    private func pop() {
        guard navigationPath.isEmpty == false else {
            return
        }

        navigationPath.removeLast()
    }

    private func done() {
        if let dismissAction {
            dismissAction()
        } else {
            dismiss()
        }
    }
}

private enum SettingsPage: Hashable {
    case home
    case editor
    case theme
    case newTheme
    case editTheme(UUID)
    case markdown
    case tips
    case information
    case about
}

private enum SettingsFontCategory: String, CaseIterable {
    case monospaced = "Monospaced"
    case proportional = "Proportional"
}

private struct SettingsFontOption: Identifiable, Equatable {
    let choice: EditorFontChoice
    let displayName: String

    var id: EditorFontChoice {
        choice
    }

    static let monospacedOptions = [
        SettingsFontOption(choice: .systemMonospaced, displayName: "SF Mono"),
        SettingsFontOption(choice: .menlo, displayName: "Menlo"),
        SettingsFontOption(choice: .courierNew, displayName: "Courier New")
    ]

    static let proportionalOptions = [
        SettingsFontOption(choice: .default, displayName: "SF Pro"),
        SettingsFontOption(choice: .newYork, displayName: "New York"),
        SettingsFontOption(choice: .georgia, displayName: "Georgia")
    ]

    var category: SettingsFontCategory {
        switch choice {
        case .systemMonospaced, .menlo, .courier, .courierNew:
            .monospaced
        case .default, .newYork, .georgia:
            .proportional
        }
    }

    var previewFont: Font {
        let size = UIFont.preferredFont(forTextStyle: .body).pointSize

        switch choice {
        case .default:
            return .system(.body, design: .default)
        case .systemMonospaced:
            return .system(.body, design: .monospaced)
        case .menlo:
            return .custom("Menlo", size: size)
        case .courier, .courierNew:
            return .custom("Courier New", size: size)
        case .newYork:
            return .system(.body, design: .serif)
        case .georgia:
            return .custom("Georgia", size: size)
        }
    }

    static func displayName(for choice: EditorFontChoice) -> String {
        switch choice {
        case .default:
            "SF Pro"
        case .systemMonospaced:
            "SF Mono"
        case .menlo:
            "Menlo"
        case .courier:
            "Courier"
        case .courierNew:
            "Courier New"
        case .newYork:
            "New York"
        case .georgia:
            "Georgia"
        }
    }
}

private struct SettingsHomePage: View {
    let summary: SettingsHomeSummary
    @Binding var appColorScheme: AppColorScheme
    let accessState: WorkspaceAccessState
    let doneAction: () -> Void
    let workspaceAction: () -> Void

    var body: some View {
        List {
            Section {
                NavigationLink(value: SettingsPage.editor) {
                    SettingsHomeRow(
                        systemName: "textformat.size",
                        colors: [.blue],
                        title: "Editor",
                        detail: summary.fontName
                    )
                }

                NavigationLink(value: SettingsPage.theme) {
                    SettingsHomeRow(
                        systemName: "paintpalette.fill",
                        colors: [.pink, .orange],
                        title: "Theme",
                        detail: summary.themeName,
                        usesMulticolor: true
                    )
                }

                NavigationLink(value: SettingsPage.markdown) {
                    SettingsHomeRow(
                        systemName: "checklist",
                        colors: [.purple],
                        title: "Markdown",
                        detail: nil
                    )
                }

                Picker(selection: $appColorScheme) {
                    ForEach(AppColorScheme.allCases, id: \.self) { scheme in
                        Text(scheme.label).tag(scheme)
                    }
                } label: {
                    SettingsHomeLabel(
                        title: "Appearance",
                        systemName: appColorScheme.systemImage,
                        colors: [appColorScheme.accentColor]
                    )
                }
                .pickerStyle(.menu)
                .tint(.primary)
                .accessibilityLabel("Appearance mode")
            }

            Section {
                Button(action: workspaceAction) {
                    SettingsHomeRow(
                        systemName: "folder",
                        colors: [.blue],
                        title: "Workspace",
                        detail: summary.workspaceName
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint(workspaceHint)
            }

            Section {
                NavigationLink(value: SettingsPage.tips) {
                    SettingsHomeRow(
                        systemName: "banknote.fill",
                        colors: [.green],
                        title: "Tips",
                        detail: nil
                    )
                }

                NavigationLink(value: SettingsPage.information) {
                    SettingsHomeRow(
                        systemName: "info.circle",
                        colors: [.blue],
                        title: "Information",
                        detail: nil
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: doneAction)
            }
        }
        .fontDesign(.rounded)
    }

    private var workspaceHint: String {
        switch accessState {
        case .noneSelected:
            "Choose a workspace folder."
        case .restorable:
            "A saved workspace can be restored."
        case .ready:
            "The current workspace is ready."
        case .invalid:
            "The saved workspace needs to be reconnected."
        }
    }
}

private struct SettingsHomeRow: View {
    let systemName: String
    let colors: [Color]
    let title: String
    let detail: String?
    var usesMulticolor = false

    var body: some View {
        HStack {
            SettingsHomeLabel(
                title: title,
                systemName: systemName,
                colors: colors,
                usesMulticolor: usesMulticolor
            )

            Spacer()

            if let detail, detail.isEmpty == false {
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsHomeLabel: View {
    let title: String
    let systemName: String
    let colors: [Color]
    var usesMulticolor = false

    var body: some View {
        HStack(spacing: 10) {
            SettingsHomeSymbol(
                systemName: systemName,
                colors: colors,
                usesMulticolor: usesMulticolor
            )
            Text(title)
        }
    }
}

private struct SettingsHomeSymbol: View {
    let systemName: String
    let colors: [Color]
    var usesMulticolor = false

    var body: some View {
        Image(systemName: systemName)
            .symbolRenderingMode(usesMulticolor ? .multicolor : .hierarchical)
            .foregroundStyle(gradient)
            .frame(width: 22)
            .accessibilityHidden(true)
    }

    private var gradient: LinearGradient {
        let resolvedColors: [Color]

        if colors.isEmpty {
            resolvedColors = [.primary, .primary.opacity(0.7)]
        } else if colors.count == 1, let color = colors.first {
            resolvedColors = [color, color.opacity(0.7)]
        } else {
            resolvedColors = colors
        }

        return LinearGradient(
            colors: resolvedColors,
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

private extension View {
    func settingsFooterStyle() -> some View {
        font(.system(.footnote, design: .rounded))
    }
}

private struct EditorSettingsPage: View {
    let editorAppearanceStore: EditorAppearanceStore
    let backAction: () -> Void

    @State private var selectedCategory: SettingsFontCategory = .monospaced
    @State private var lineNumbers = false
    @State private var largerHeadingText = false

    var body: some View {
        Form {
            Section {
                Picker("Font Type", selection: $selectedCategory) {
                    ForEach(SettingsFontCategory.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedCategory) { _, category in
                    selectFirstAvailableFont(in: category)
                }

                ForEach(availableFontOptions) { option in
                    SettingsFontRow(
                        option: option,
                        isSelected: editorAppearanceStore.selectedFontChoice == option.choice
                    ) {
                        editorAppearanceStore.setFontChoice(option.choice)
                    }
                }
            } footer: {
                Text("Choose your favourite font.")
                    .settingsFooterStyle()
            }

            Section {
                Stepper(value: fontSizeBinding, in: 12...24, step: 1) {
                    LabeledContent {
                        Text("\(Int(editorAppearanceStore.fontSize)) pt")
                            .foregroundStyle(.secondary)
                    } label: {
                        SettingsHomeLabel(
                            title: "Font Size",
                            systemName: "textformat.size",
                            colors: [.blue]
                        )
                    }
                }
            } footer: {
                Text("Adjust the editor font size relative to the system default.")
                    .settingsFooterStyle()
            }

            if selectedCategory == .monospaced {
                Section {
                    Toggle("Line Numbers", isOn: $lineNumbers)
                        .disabled(true)
                        .accessibilityHint("Line numbers are not implemented yet.")
                } footer: {
                    Text("Show line numbers along the left edge of the editor.")
                        .settingsFooterStyle()
                }
            }

            Section {
                Toggle("Larger Heading Text", isOn: $largerHeadingText)
                    .disabled(true)
                    .accessibilityHint("Larger heading text is not implemented as a user setting yet.")
            } footer: {
                Text(largerHeadingHelperText)
                    .settingsFooterStyle()
            }
        }
        .navigationTitle("Editor")
        .fontDesign(.rounded)
        .onAppear {
            selectedCategory = category(for: editorAppearanceStore.selectedFontChoice)
        }
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { editorAppearanceStore.fontSize },
            set: { editorAppearanceStore.setFontSize($0) }
        )
    }

    private var availableFontOptions: [SettingsFontOption] {
        options(for: selectedCategory).filter { option in
            editorAppearanceStore.availableFontChoices.contains(option.choice)
        }
    }

    private func options(for category: SettingsFontCategory) -> [SettingsFontOption] {
        switch category {
        case .monospaced:
            SettingsFontOption.monospacedOptions
        case .proportional:
            SettingsFontOption.proportionalOptions
        }
    }

    private func category(for choice: EditorFontChoice) -> SettingsFontCategory {
        if let option = (SettingsFontOption.monospacedOptions + SettingsFontOption.proportionalOptions)
            .first(where: { $0.choice == choice }) {
            return option.category
        }

        return .proportional
    }

    private func selectFirstAvailableFont(in category: SettingsFontCategory) {
        guard let first = options(for: category).first(where: { option in
            editorAppearanceStore.availableFontChoices.contains(option.choice)
        }) else {
            return
        }

        editorAppearanceStore.setFontChoice(first.choice)
    }

    private var largerHeadingHelperText: String {
        if lineNumbers {
            return "Larger heading text is unavailable while line numbers are enabled."
        }

        return "Larger heading text will be wired after heading-size preferences are implemented."
    }
}

private struct SettingsFontRow: View {
    let option: SettingsFontOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(option.displayName)
                    .font(option.previewFont)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .bold()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct ThemeSettingsPage: View {
    let editorAppearanceStore: EditorAppearanceStore
    let themeStore: ThemeStore
    let push: (SettingsPage) -> Void
    let backAction: () -> Void

    @State private var isImportingTheme = false

    var body: some View {
        Form {
            Section {
                ForEach(EditorTheme.builtIn) { theme in
                    ThemeSelectionRow(
                        theme: theme,
                        isSelected: editorAppearanceStore.selectedThemeID == theme.id
                    ) {
                        editorAppearanceStore.setSelectedThemeID(theme.id)
                    }
                }
            } footer: {
                Text("Follows the system appearance automatically.")
                    .settingsFooterStyle()
            }

            Section {
                ForEach(themeStore.themes) { customTheme in
                    ThemeSelectionRow(
                        theme: EditorTheme(from: customTheme),
                        isSelected: editorAppearanceStore.selectedThemeID == customTheme.id.uuidString,
                        onEdit: { push(.editTheme(customTheme.id)) }
                    ) {
                        editorAppearanceStore.setSelectedThemeID(customTheme.id.uuidString)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task {
                                let wasSelected = editorAppearanceStore.selectedThemeID == customTheme.id.uuidString
                                let didDelete = await themeStore.delete(id: customTheme.id)
                                if didDelete, wasSelected {
                                    editorAppearanceStore.setSelectedThemeID(EditorTheme.adaptive.id)
                                }
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            push(.editTheme(customTheme.id))
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }

                Button {
                    push(.newTheme)
                } label: {
                    SettingsHomeLabel(title: "New Theme", systemName: "plus.circle.fill", colors: [.green])
                }

                Button {
                    isImportingTheme = true
                } label: {
                    SettingsHomeLabel(title: "Import Theme", systemName: "square.and.arrow.down.fill", colors: [.blue])
                }
            } header: {
                Text("Custom")
            } footer: {
                Text("Create custom palettes, import them from JSON, or export a theme to share it.")
                    .settingsFooterStyle()
            }

            Section {
                Toggle(
                    "Match Menus to Theme",
                    isOn: Binding(
                        get: { editorAppearanceStore.matchSystemChromeToTheme },
                        set: { editorAppearanceStore.setMatchSystemChromeToTheme($0) }
                    )
                )
            } footer: {
                Text("When enabled, editor menus and keyboard etc, will follow the current theme instead of the app appearance.")
                    .settingsFooterStyle()
            }
        }
        .navigationTitle("Theme")
        .fontDesign(.rounded)
        .fileImporter(
            isPresented: $isImportingTheme,
            allowedContentTypes: [.json]
        ) { result in
            Task {
                await handleImport(result: result)
            }
        }
        .alert("Theme Error", isPresented: themeErrorBinding) {
            Button("OK") { themeStore.lastError = nil }
        } message: {
            if let error = themeStore.lastError {
                Text(error)
            }
        }
    }

    private var themeErrorBinding: Binding<Bool> {
        Binding(
            get: { themeStore.lastError != nil },
            set: { isPresented in
                if isPresented == false {
                    themeStore.lastError = nil
                }
            }
        )
    }

    private func handleImport(result: Result<URL, Error>) async {
        do {
            let url = try result.get()
            let accessedSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if accessedSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let fileSize = try await Task.detached(priority: .userInitiated) {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                return attributes[.size] as? Int ?? 0
            }.value

            guard fileSize <= 5 * 1024 * 1024 else {
                themeStore.lastError = "The theme file is too large to import (maximum 5 MB)."
                return
            }

            let data = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: url)
            }.value
            let document = try ThemeExchangeDocument(data: data)
            _ = await themeStore.importThemes(document.themes)
        } catch {
            guard isUserCancelled(error) == false else {
                return
            }
            themeStore.lastError = "Could not import the theme JSON: \(error.localizedDescription)"
        }
    }

    private func isUserCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.userCancelled.rawValue
    }
}

private struct ThemeSelectionRow: View {
    let theme: EditorTheme
    let isSelected: Bool
    var onEdit: (() -> Void)?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack {
                    ThemePreviewSwatch(theme: theme)
                    Text(theme.label)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                            .bold()
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if let onEdit {
                Button("Edit", systemImage: "slider.horizontal.3", action: onEdit)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
                    .buttonStyle(.plain)
            }
        }
    }
}

private struct ThemePreviewSwatch: View {
    let theme: EditorTheme

    var body: some View {
        HStack(spacing: 0) {
            Color(uiColor: theme.background)
            Color(uiColor: theme.text)
            Color(uiColor: theme.tint)
            Color(uiColor: theme.boldItalicMarker)
            Color(uiColor: theme.horizontalRule)
        }
        .frame(width: 60, height: 28)
        .clipShape(.rect(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}

private struct ThemeEditorSettingsPage: View {
    let editorAppearanceStore: EditorAppearanceStore
    let themeStore: ThemeStore
    let editing: CustomTheme?
    let backAction: () -> Void

    @State private var name: String
    @State private var background: Color
    @State private var text: Color
    @State private var tint: Color
    @State private var boldItalicMarker: Color
    @State private var inlineCode: Color
    @State private var codeBackground: Color
    @State private var horizontalRule: Color
    @State private var checkboxUnchecked: Color
    @State private var checkboxChecked: Color
    @State private var editingColor: ThemeColorProperty?
    @State private var isSaving = false
    @State private var exportDocument: ThemeExchangeDocument?
    @State private var exportFilename = "Theme.json"

    init(
        editorAppearanceStore: EditorAppearanceStore,
        themeStore: ThemeStore,
        editing: CustomTheme? = nil,
        backAction: @escaping () -> Void
    ) {
        self.editorAppearanceStore = editorAppearanceStore
        self.themeStore = themeStore
        self.editing = editing
        self.backAction = backAction

        if let editing {
            _name = State(initialValue: editing.name)
            _background = State(initialValue: Color(uiColor: editing.background.uiColor))
            _text = State(initialValue: Color(uiColor: editing.text.uiColor))
            _tint = State(initialValue: Color(uiColor: editing.tint.uiColor))
            _boldItalicMarker = State(initialValue: Color(uiColor: editing.boldItalicMarker.uiColor))
            _inlineCode = State(initialValue: Color(uiColor: editing.inlineCode.uiColor))
            _codeBackground = State(initialValue: Color(uiColor: editing.codeBackground.uiColor))
            _horizontalRule = State(initialValue: Color(uiColor: editing.horizontalRule.uiColor))
            _checkboxUnchecked = State(initialValue: Color(uiColor: editing.checkboxUnchecked.uiColor))
            _checkboxChecked = State(initialValue: Color(uiColor: editing.checkboxChecked.uiColor))
        } else {
            _name = State(initialValue: "")
            _background = State(initialValue: Color(uiColor: UIColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1)))
            _text = State(initialValue: Color(uiColor: UIColor(red: 0.831, green: 0.831, blue: 0.831, alpha: 1)))
            _tint = State(initialValue: Color(uiColor: UIColor(red: 0.337, green: 0.612, blue: 0.839, alpha: 1)))
            _boldItalicMarker = State(initialValue: Color(uiColor: UIColor(red: 0.45, green: 0.45, blue: 0.50, alpha: 1)))
            _inlineCode = State(initialValue: Color(uiColor: UIColor(red: 0.808, green: 0.569, blue: 0.471, alpha: 1)))
            _codeBackground = State(initialValue: Color(uiColor: UIColor(red: 0.176, green: 0.176, blue: 0.176, alpha: 1)))
            _horizontalRule = State(initialValue: Color(uiColor: UIColor(red: 0.251, green: 0.251, blue: 0.251, alpha: 1)))
            _checkboxUnchecked = State(initialValue: Color(uiColor: UIColor(red: 0.957, green: 0.278, blue: 0.278, alpha: 1)))
            _checkboxChecked = State(initialValue: Color(uiColor: UIColor(red: 0.416, green: 0.600, blue: 0.333, alpha: 1)))
        }
    }

    var body: some View {
        List {
            Section("Name") {
                TextField("Theme Name", text: $name)
            }

            Section("Colours") {
                if hasLowContrast {
                    Label {
                        Text("Text and background contrast is \(textBackgroundContrastRatio, specifier: "%.1f"):1 - WCAG AA requires 4.5:1. The editor may be difficult to read.")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }
                    .listRowBackground(Color.yellow.opacity(0.12))
                }

                ForEach(ThemeColorProperty.allCases) { property in
                    Button {
                        editingColor = property
                    } label: {
                        HStack {
                            Text(property.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            Circle()
                                .fill(colorValue(for: property))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle().strokeBorder(
                                        Color(uiColor: UIColor(colorValue(for: property)).darkerShade()),
                                        lineWidth: 2
                                    )
                                )
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SettingsMarkdownPreview(
                background: background,
                text: text,
                accent: tint,
                marker: boldItalicMarker,
                strike: horizontalRule,
                code: inlineCode
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(.ultraThinMaterial)
        }
        .navigationTitle(editing == nil ? "New Theme" : "Edit Theme")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .toolbar {
            if editing != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Export", systemImage: "square.and.arrow.up") {
                        exportTheme()
                    }
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await saveTheme()
                    }
                }
                .disabled(isSaveDisabled)
            }
        }
        .sheet(item: $editingColor) { property in
            PaletteColorPicker(
                title: property.title,
                selection: colorBinding(for: property)
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .fileExporter(
            isPresented: exportPresentationBinding,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            if case let .failure(error) = result, isUserCancelled(error) == false {
                themeStore.lastError = "Could not export the theme JSON: \(error.localizedDescription)"
            }
            exportDocument = nil
        }
        .alert("Theme Error", isPresented: themeErrorBinding) {
            Button("OK") { themeStore.lastError = nil }
        } message: {
            if let error = themeStore.lastError {
                Text(error)
            }
        }
    }

    private var isSaveDisabled: Bool {
        isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var textBackgroundContrastRatio: Double {
        UIColor(text).wcagContrastRatio(against: UIColor(background))
    }

    private var hasLowContrast: Bool {
        textBackgroundContrastRatio < 4.5
    }

    private var exportPresentationBinding: Binding<Bool> {
        Binding(
            get: { exportDocument != nil },
            set: { isPresented in
                if isPresented == false {
                    exportDocument = nil
                }
            }
        )
    }

    private var themeErrorBinding: Binding<Bool> {
        Binding(
            get: { themeStore.lastError != nil },
            set: { isPresented in
                if isPresented == false {
                    themeStore.lastError = nil
                }
            }
        )
    }

    private func colorValue(for property: ThemeColorProperty) -> Color {
        switch property {
        case .background: background
        case .text: text
        case .tint: tint
        case .boldItalicMarker: boldItalicMarker
        case .inlineCode: inlineCode
        case .codeBackground: codeBackground
        case .horizontalRule: horizontalRule
        case .checkboxUnchecked: checkboxUnchecked
        case .checkboxChecked: checkboxChecked
        }
    }

    private func colorBinding(for property: ThemeColorProperty) -> Binding<Color> {
        switch property {
        case .background: $background
        case .text: $text
        case .tint: $tint
        case .boldItalicMarker: $boldItalicMarker
        case .inlineCode: $inlineCode
        case .codeBackground: $codeBackground
        case .horizontalRule: $horizontalRule
        case .checkboxUnchecked: $checkboxUnchecked
        case .checkboxChecked: $checkboxChecked
        }
    }

    private func saveTheme() async {
        guard isSaving == false else { return }
        isSaving = true
        defer { isSaving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let theme = makeTheme(id: editing?.id ?? UUID(), name: trimmedName)

        if editing != nil {
            guard await themeStore.update(theme) else { return }
        } else {
            guard await themeStore.add(theme) else { return }
            editorAppearanceStore.setSelectedThemeID(theme.id.uuidString)
        }

        backAction()
    }

    private func makeTheme(id: UUID, name: String? = nil) -> CustomTheme {
        CustomTheme(
            id: id,
            name: name ?? self.name.trimmingCharacters(in: .whitespacesAndNewlines),
            background: HexColor(UIColor(background)),
            text: HexColor(UIColor(text)),
            tint: HexColor(UIColor(tint)),
            boldItalicMarker: HexColor(UIColor(boldItalicMarker)),
            inlineCode: HexColor(UIColor(inlineCode)),
            codeBackground: HexColor(UIColor(codeBackground)),
            horizontalRule: HexColor(UIColor(horizontalRule)),
            checkboxUnchecked: HexColor(UIColor(checkboxUnchecked)),
            checkboxChecked: HexColor(UIColor(checkboxChecked))
        )
    }

    private func exportTheme() {
        let theme = makeTheme(id: editing?.id ?? UUID())
        exportDocument = ThemeExchangeDocument(theme: theme)
        exportFilename = sanitizedExportFilename(for: theme.name)
    }

    private func sanitizedExportFilename(for themeName: String) -> String {
        let trimmed = themeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = trimmed
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .replacing(" ", with: "-")
        let filename = cleaned.isEmpty ? "Theme" : cleaned
        return "\(filename).json"
    }

    private func isUserCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.userCancelled.rawValue
    }
}

private enum ThemeColorProperty: String, Identifiable, CaseIterable {
    case background
    case text
    case tint
    case boldItalicMarker
    case inlineCode
    case codeBackground
    case horizontalRule
    case checkboxUnchecked
    case checkboxChecked

    var id: Self { self }

    var title: String {
        switch self {
        case .background: "Background"
        case .text: "Text"
        case .tint: "Accent"
        case .boldItalicMarker: "Bold / Italic Markers"
        case .inlineCode: "Code"
        case .codeBackground: "Code Background"
        case .horizontalRule: "Horizontal Rule"
        case .checkboxUnchecked: "Unchecked Task"
        case .checkboxChecked: "Checked Task"
        }
    }
}

private struct MarkdownSettingsPage: View {
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

private struct TipsSettingsPage: View {
    let backAction: () -> Void

    private let tips = [
        TipRow(icon: "cup.and.saucer.fill", tint: Color.brown.opacity(0.65), title: "Small Coffee", caption: "Buy me a small coffee", price: "£0.99"),
        TipRow(icon: "mug.fill", tint: .orange.opacity(0.75), title: "Large Coffee", caption: "Buy me a large coffee", price: "£2.99"),
        TipRow(icon: "fork.knife", tint: .teal.opacity(0.65), title: "Lunch", caption: "Buy me Lunch", price: "£4.99"),
        TipRow(icon: "wineglass.fill", tint: .red.opacity(0.7), title: "Dinner", caption: "Buy me dinner", price: "£9.99")
    ]

    var body: some View {
        SettingsShell {
            SettingsPageHeader(title: "Tips", backAction: backAction)

            SettingsCard {
                ForEach(tips) { tip in
                    SettingsTipRow(tip: tip)

                    if tip != tips.last {
                        SettingsDivider(leadingInset: 86)
                    }
                }
            }

            SettingsHelperText("Tips help support the ongoing development of Downward.\nThank you.")
        }
    }
}

private struct InformationSettingsPage: View {
    let push: (SettingsPage) -> Void
    let backAction: () -> Void

    var body: some View {
        SettingsShell {
            SettingsPageHeader(title: "Information", backAction: backAction)

            SettingsCard {
                SettingsNavigationRow(
                    icon: .symbol("star.fill"),
                    iconTint: .yellow,
                    title: "Rate the App",
                    value: nil,
                    isEnabled: false,
                    action: {}
                )
                .accessibilityHint("App Store review routing is not implemented yet.")
            }

            SettingsHelperText("If Downward is working well for you, leaving a rating helps.")

            SettingsCard {
                SettingsNavigationRow(
                    icon: .symbol("info.circle"),
                    iconTint: .blue.opacity(0.55),
                    title: "About",
                    value: nil,
                    action: { push(.about) }
                )
            }

            SettingsHelperText("Version details, privacy policy, and terms are available in About.")
        }
    }
}

private struct AboutSettingsPage: View {
    let backAction: () -> Void

    var body: some View {
        SettingsShell {
            SettingsPageHeader(title: "", backAction: backAction)

            VStack(spacing: 14) {
                AppIconPlaceholder()

            Text("Downward")
                    .font(.title.weight(.bold))

                Text(versionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Second Victor Ltd.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .padding(.bottom, 12)

            SettingsCard {
                SettingsNavigationRow(
                    icon: .symbol("hand.raised.fill"),
                    iconTint: .blue,
                    title: "Privacy Policy",
                    value: nil,
                    isEnabled: false,
                    action: {}
                )
                .accessibilityHint("Privacy Policy URL is not configured yet.")
                SettingsDivider()
                SettingsNavigationRow(
                    icon: .symbol("doc.text.fill"),
                    iconTint: .blue,
                    title: "Terms & Conditions",
                    value: nil,
                    isEnabled: false,
                    action: {}
                )
                .accessibilityHint("Terms and Conditions URL is not configured yet.")
            }
        }
    }

    private var versionText: String {
        let infoDictionary = Bundle.main.infoDictionary
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }
}

private struct SettingsShell<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .frame(maxWidth: contentWidth, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 24)
                .padding(.bottom, 34)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var contentWidth: CGFloat? {
        horizontalSizeClass == .regular ? 720 : nil
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 32 : 20
    }
}

private enum SettingsHeaderTitlePlacement {
    case leading
    case center
}

private struct SettingsPageHeader<Trailing: View>: View {
    let title: String
    var titlePlacement: SettingsHeaderTitlePlacement = .leading
    var backAction: (() -> Void)?
    @ViewBuilder let trailing: Trailing

    init(
        title: String,
        titlePlacement: SettingsHeaderTitlePlacement = .leading,
        backAction: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.titlePlacement = titlePlacement
        self.backAction = backAction
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                if let backAction {
                    Button(action: backAction) {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                            .frame(width: 52, height: 52)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                if titlePlacement == .center {
                    Spacer(minLength: 12)
                    Text(title)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                    Spacer(minLength: 12)
                } else {
                    Spacer(minLength: 12)
                }

                trailing
            }
            .frame(minHeight: 52)

            if titlePlacement == .leading, title.isEmpty == false {
                Text(title)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            }
        }
    }
}

private extension SettingsPageHeader where Trailing == EmptyView {
    init(
        title: String,
        titlePlacement: SettingsHeaderTitlePlacement = .leading,
        backAction: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            titlePlacement: titlePlacement,
            backAction: backAction,
            trailing: { EmptyView() }
        )
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
    }
}

private struct SettingsDivider: View {
    var leadingInset: CGFloat = 74

    var body: some View {
        Divider()
            .padding(.leading, leadingInset)
            .padding(.trailing, 28)
    }
}

private enum SettingsIcon {
    case symbol(String)
    case text(String)
}

private struct SettingsNavigationRow: View {
    let icon: SettingsIcon
    let iconTint: Color
    let title: String
    let value: String?
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowContent(
                icon: icon,
                iconTint: iconTint,
                title: title,
                value: value,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

private struct SettingsMenuStyleRow: View {
    let icon: SettingsIcon
    let iconTint: Color
    let title: String
    let value: String

    var body: some View {
        SettingsRowContent(
            icon: icon,
            iconTint: iconTint,
            title: title,
            value: value,
            showsChevron: false,
            trailingSystemImage: "chevron.up.chevron.down"
        )
        .opacity(0.9)
        .accessibilityHint("App appearance selection is not implemented yet.")
    }
}

private struct SettingsRowContent: View {
    let icon: SettingsIcon
    let iconTint: Color
    let title: String
    let value: String?
    var showsChevron = false
    var trailingSystemImage: String?

    var body: some View {
        HStack(spacing: 18) {
            SettingsIconView(icon: icon, tint: iconTint)

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 12)

            if let value {
                Text(value)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }

            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SettingsIconView: View {
    let icon: SettingsIcon
    let tint: Color

    var body: some View {
        Group {
            switch icon {
            case let .symbol(systemName):
                Image(systemName: systemName)
                    .font(.body.weight(.semibold))
            case let .text(text):
                Text(text)
                    .font(.body.weight(.medium))
            }
        }
        .foregroundStyle(tint)
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

private struct SettingsSelectableRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsStepperRow: View {
    let icon: SettingsIcon
    let iconTint: Color
    let title: String
    let value: String
    let decrementAction: () -> Void
    let incrementAction: () -> Void
    let canDecrement: Bool
    let canIncrement: Bool

    var body: some View {
        HStack(spacing: 18) {
            SettingsIconView(icon: icon, tint: iconTint)

            Text(title)
                .font(.body)

            Spacer(minLength: 10)

            Text(value)
                .font(.body)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            HStack(spacing: 0) {
                Button(action: decrementAction) {
                    Image(systemName: "minus")
                        .frame(width: 46, height: 34)
                }
                .disabled(canDecrement == false)

                Divider()
                    .frame(height: 24)

                Button(action: incrementAction) {
                    Image(systemName: "plus")
                        .frame(width: 46, height: 34)
                }
                .disabled(canIncrement == false)
            }
            .font(.body.weight(.bold))
            .foregroundStyle(.primary)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule(style: .continuous))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var isEnabled = true
    var accessibilityHint: String?

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .disabled(isEnabled == false)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityHint(accessibilityHint ?? "")
    }
}

private struct SettingsHelperText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 28)
            .padding(.top, -12)
    }
}

private struct SettingsMarkdownPreview: View {
    let background: Color
    let text: Color
    let accent: Color
    let marker: Color
    let strike: Color
    let code: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Text("#")
                    .foregroundStyle(accent)
                Text("Heading")
                    .foregroundStyle(text)
            }
            .font(.system(.body, design: .monospaced).weight(.bold))

            HStack(spacing: 12) {
                Text("**Bold**")
                    .fontWeight(.bold)
                Text("and")
                Text("*italic*")
                    .italic()
            }
            .foregroundStyle(text)
            .font(.system(.body, design: .monospaced))

            Text("~~Strike Through~~")
                .foregroundStyle(strike)
                .strikethrough()
                .font(.system(.body, design: .monospaced))

            Text("`inline code`")
                .foregroundStyle(code)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text("---")
                .foregroundStyle(marker.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .center)
                .font(.system(.body, design: .monospaced))

            VStack(alignment: .leading, spacing: 8) {
                Text("- [ ] To do")
                Text("- [x] Done")
            }
            .foregroundStyle(text)
            .font(.system(.body, design: .monospaced))
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.top, 4)
    }
}

private struct TipRow: Identifiable, Equatable {
    let icon: String
    let tint: Color
    let title: String
    let caption: String
    let price: String

    var id: String {
        title
    }

    static func == (lhs: TipRow, rhs: TipRow) -> Bool {
        lhs.id == rhs.id
    }
}

private struct SettingsTipRow: View {
    let tip: TipRow

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: tip.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tip.tint)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(tip.title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(tip.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(tip.price)
                .font(.body.weight(.bold))
                .monospacedDigit()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .accessibilityHint("StoreKit purchases are not implemented yet.")
    }
}

private struct AppIconPlaceholder: View {
    var body: some View {
        Image("AppIcon")
            .resizable()
            .scaledToFit()
            .background(
                LinearGradient(
                    colors: [.blue, .teal],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .frame(width: 96, height: 96)
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 14)
        .accessibilityLabel("Downward app icon")
    }
}

@MainActor
private func makePreviewThemeStore() -> ThemeStore {
    ThemeStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "preview-themes-\(UUID().uuidString).json"))
}

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
