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
        case .lineNumbers, .largerHeadingText, .tapToToggleTasks:
            true
        case .tipsPurchases, .rateTheApp, .legalLinks:
            false
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
            .roundedNavigationBarTitles()
        case .theme:
            ThemeSettingsPage(
                editorAppearanceStore: editorAppearanceStore,
                themeStore: themeStore,
                push: push,
                backAction: pop
            )
            .roundedNavigationBarTitles()
        case .newTheme:
            ThemeEditorSettingsPage(
                editorAppearanceStore: editorAppearanceStore,
                themeStore: themeStore,
                editing: nil,
                backAction: pop
            )
            .roundedNavigationBarTitles()
        case let .editTheme(id):
            if let theme = themeStore.theme(withID: id) {
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
            TipsSettingsPage(backAction: pop)
                .roundedNavigationBarTitles()
        case .information:
            InformationSettingsPage(
                push: push,
                backAction: pop
            )
            .roundedNavigationBarTitles()
        case .about:
            AboutSettingsPage(backAction: pop)
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

enum SettingsPage: Hashable {
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

@MainActor
func makePreviewThemeStore() -> ThemeStore {
    ThemeStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "preview-themes-\(UUID().uuidString).json"))
}
