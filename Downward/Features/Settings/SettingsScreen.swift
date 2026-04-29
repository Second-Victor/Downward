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
        self.fontName = SettingsFontOption.displayName(for: editorAppearanceStore.selectedFontChoice)
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
        case .lineNumbers, .largerHeadingText, .tapToToggleTasks, .rateTheApp, .legalLinks:
            true
        case .tipsPurchases:
            false
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
                doneAction: done,
                releaseConfiguration: releaseConfiguration
            )
            .navigationDestination(for: SettingsPage.self) { page in
                destination(for: page)
            }
        }
        .onAppear {
            editorAppearanceStore.fallBackToAdaptiveThemeIfSelectedCustomThemeIsNotEntitled(using: themeStore)
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
                ContentUnavailableView("Theme Missing", systemImage: "paintpalette", description: Text("The selected custom theme could not be found."))
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
                EmptyView()
            }
        case .information:
            InformationSettingsPage(
                push: push,
                backAction: pop,
                releaseConfiguration: releaseConfiguration
            )
            .roundedNavigationBarTitles()
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
        ContentUnavailableView(
            "Extra Themes Locked",
            systemImage: "lock.fill",
            description: Text("Built-in themes are free. Extra themes require the Themes unlock.")
        )
    }
}

enum SettingsPage: Hashable {
    case home
    case editor
    case theme
    case extraThemes
    case workspace
    case newTheme
    case editTheme(UUID)
    case markdown
    case tips
    case information
    case about
}

@MainActor
func makePreviewThemeStore() -> ThemeStore {
    ThemeStore(
        fileURL: FileManager.default.temporaryDirectory.appending(path: "preview-themes-\(UUID().uuidString).json"),
        entitlements: ThemeEntitlementStore(hasUnlockedThemes: true)
    )
}
