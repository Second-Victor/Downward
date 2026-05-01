import SwiftUI

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
        self.fontName = editorAppearanceStore.selectedImportedFontFamilyDisplayName
            ?? SettingsFontOption.displayName(for: editorAppearanceStore.selectedFontChoice)
        self.themeName = selectedTheme.label
        self.workspaceName = workspaceName ?? "None"
        self.appearanceName = appearanceName
    }
}

enum SettingsPlaceholderFeature: Equatable {
    case lineNumbers
    case largerHeadingText
    case tapToToggleTasks
    case tipsPurchases
    case rateTheApp
    case legalLinks

    nonisolated var isImplemented: Bool {
        switch self {
        case .lineNumbers, .largerHeadingText, .tapToToggleTasks, .tipsPurchases, .rateTheApp, .legalLinks:
            true
        }
    }

    func isVisible(in configuration: SettingsReleaseConfiguration = .current) -> Bool {
        switch self {
        case .lineNumbers, .largerHeadingText, .tapToToggleTasks:
            true
        case .tipsPurchases:
            configuration.showsTipsPage
        case .rateTheApp:
            configuration.showsRateTheApp
        case .legalLinks:
            configuration.showsLegalLinks
        }
    }
}

struct SettingsScreen: View {
    let workspaceName: String?
    let accessState: WorkspaceAccessState
    let editorAppearanceStore: EditorAppearanceStore
    let themeStore: ThemeStore
    let importedFontManager: ImportedFontManager
    let reconnectWorkspaceAction: () -> Void
    let clearWorkspaceAction: () -> Void
    var releaseConfiguration: SettingsReleaseConfiguration = .current
    var dismissAction: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppColorScheme.storageKey) private var appColorSchemeRaw = AppColorScheme.system.rawValue
    @State private var navigationPath: [SettingsPage] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            SettingsHomePage(
                summary: summary,
                appColorScheme: appColorSchemeBinding,
                hasUnlockedThemes: themeStore.hasUnlockedThemes,
                doneAction: done,
                releaseConfiguration: releaseConfiguration
            )
            .navigationDestination(for: SettingsPage.self) { page in
                destination(for: page)
            }
        }
        .onAppear {
            editorAppearanceStore.fallBackToAdaptiveThemeIfSelectedCustomThemeIsNotEntitled(using: themeStore)
            editorAppearanceStore.setImportedFontsUnlocked(themeStore.hasUnlockedThemes)
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
                themeStore: themeStore,
                importedFontManager: importedFontManager,
                backAction: pop
            )
            .roundedNavigationBarTitles()
        case .theme:
            ThemeSettingsPage(
                editorAppearanceStore: editorAppearanceStore,
                themeStore: themeStore,
                push: push,
                backAction: pop
            )
            .roundedNavigationBarTitles()
        case .extraThemes:
            ExtraThemesSettingsPage(
                editorAppearanceStore: editorAppearanceStore,
                themeStore: themeStore,
                push: push,
                backAction: pop
            )
            .roundedNavigationBarTitles()
        case .supporterUnlock:
            SupporterUnlockSettingsPage(
                editorAppearanceStore: editorAppearanceStore,
                themeStore: themeStore,
                backAction: pop
            )
            .roundedNavigationBarTitles()
        case .workspace:
            WorkspaceSettingsPage(
                workspaceName: workspaceName,
                accessState: accessState,
                changeWorkspaceAction: reconnectWorkspaceAction,
                clearWorkspaceAction: clearWorkspaceAction
            )
            .roundedNavigationBarTitles()
        case .newTheme:
            if ThemeEntitlementGate.canCreateCustomTheme(hasUnlockedThemes: themeStore.hasUnlockedThemes) {
                ThemeEditorSettingsPage(
                    editorAppearanceStore: editorAppearanceStore,
                    themeStore: themeStore,
                    editing: nil,
                    backAction: pop
                )
                .roundedNavigationBarTitles()
            } else {
                lockedThemesView
                    .roundedNavigationBarTitles()
            }
        case let .editTheme(id):
            if ThemeEntitlementGate.canEditCustomThemes(hasUnlockedThemes: themeStore.hasUnlockedThemes) == false {
                lockedThemesView
                    .roundedNavigationBarTitles()
            } else if let theme = themeStore.theme(withID: id) {
                ThemeEditorSettingsPage(
                    editorAppearanceStore: editorAppearanceStore,
                    themeStore: themeStore,
                    editing: theme,
                    backAction: pop
                )
                .roundedNavigationBarTitles()
            } else {
                GradientContentUnavailableView(
                    "Theme Missing",
                    systemName: "paintpalette",
                    color: .secondary
                ) {
                    Text("The selected custom theme could not be found.")
                }
                    .roundedNavigationBarTitles()
            }
        case .markdown:
            MarkdownSettingsPage(
                editorAppearanceStore: editorAppearanceStore,
                backAction: pop
            )
            .roundedNavigationBarTitles()
        case .tips:
            if releaseConfiguration.showsTipsPage {
                TipsSettingsPage(backAction: pop)
                    .roundedNavigationBarTitles()
            } else {
                GradientContentUnavailableView(
                    "Tips Unavailable",
                    systemName: "banknote",
                    color: .secondary
                ) {
                    Text("Tips are not enabled in this build.")
                }
                .roundedNavigationBarTitles()
            }
        case .about:
            AboutSettingsPage(
                backAction: pop,
                releaseConfiguration: releaseConfiguration
            )
                .roundedNavigationBarTitles()
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

    private var lockedThemesView: some View {
        GradientContentUnavailableView(
            "Extra Themes Locked",
            systemName: "lock.fill",
            color: .secondary
        ) {
            Text("Built-in themes are free. Extra themes require the Themes unlock.")
        }
    }
}

enum SettingsPage: Hashable {
    case home
    case editor
    case theme
    case extraThemes
    case supporterUnlock
    case workspace
    case newTheme
    case editTheme(UUID)
    case markdown
    case tips
    case about
}

@MainActor
func makePreviewThemeStore(hasUnlockedThemes: Bool = true) -> ThemeStore {
    ThemeStore(
        fileURL: FileManager.default.temporaryDirectory.appending(path: "preview-themes-\(UUID().uuidString).json"),
        entitlements: ThemeEntitlementStore(hasUnlockedThemes: hasUnlockedThemes)
    )
}

@MainActor
func makePreviewImportedFontManager() -> ImportedFontManager {
    ImportedFontManager(
        fontsDirectory: FileManager.default.temporaryDirectory.appending(
            path: "preview-fonts-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    )
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
        importedFontManager: makePreviewImportedFontManager(),
        reconnectWorkspaceAction: {},
        clearWorkspaceAction: {}
    )
}

#Preview("Settings Home - Not Supporter") {
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
        themeStore: makePreviewThemeStore(hasUnlockedThemes: false),
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
