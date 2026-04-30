import SwiftUI
import UniformTypeIdentifiers

struct ThemeSettingsPage: View {
    let editorAppearanceStore: EditorAppearanceStore
    let themeStore: ThemeStore
    let push: (SettingsPage) -> Void
    let backAction: () -> Void

    var body: some View {
        Form {
            Section {
                ForEach(EditorTheme.builtIn) { theme in
                    ThemeSelectionRow(
                        theme: theme,
                        isSelected: editorAppearanceStore.selectedThemeID == theme.id
                    ) {
                        editorAppearanceStore.setSelectedThemeID(theme.id, using: themeStore)
                    }
                }
            } footer: {
                Text(builtInThemesFooter)
                    .settingsFooterStyle()
            }

            if themeStore.hasUnlockedThemes {
                Section {
                    NavigationLink(value: SettingsPage.extraThemes) {
                        ExtraThemesNavigationLabel(
                            selectedTheme: selectedExtraTheme
                        )
                    }
                } footer: {
                    Text("Create, import, edit and select supporter themes.")
                        .settingsFooterStyle()
                }
            }
        }
        .navigationTitle("Theme")
        .onAppear {
            editorAppearanceStore.fallBackToAdaptiveThemeIfSelectedCustomThemeIsNotEntitled(using: themeStore)
        }
    }

    private var builtInThemesFooter: String {
        if themeStore.hasUnlockedThemes {
            return "Follows the system appearance automatically."
        }

        return "Follows the system appearance automatically. More themes are available for supporters."
    }

    private var selectedExtraTheme: EditorTheme? {
        guard
            themeStore.hasUnlockedThemes,
            let selectedThemeID = UUID(uuidString: editorAppearanceStore.selectedThemeID),
            let customTheme = themeStore.theme(withID: selectedThemeID)
        else {
            return nil
        }

        return EditorTheme(from: customTheme)
    }
}

private struct ExtraThemesNavigationLabel: View {
    let selectedTheme: EditorTheme?

    var body: some View {
        HStack(spacing: 10) {
            SettingsHomeSymbol(
                systemName: "circle.hexagongrid.fill",
                colors: [.accentColor],
                usesMulticolor: true
            )

            Text("Extra Themes")

            Spacer(minLength: 12)

            if let selectedTheme {
                Text(selectedTheme.label)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct ExtraThemesSettingsPage: View {
    let editorAppearanceStore: EditorAppearanceStore
    let themeStore: ThemeStore
    let push: (SettingsPage) -> Void
    let backAction: () -> Void
    private let themeImportService = ThemeImportService()

    @State private var isImportingTheme = false

    var body: some View {
        Form {
            Section {
                ForEach(themeStore.themes) { customTheme in
                    ThemeSelectionRow(
                        theme: EditorTheme(from: customTheme),
                        isSelected: editorAppearanceStore.selectedThemeID == customTheme.id.uuidString,
                        isEnabled: themeStore.hasUnlockedThemes,
                        onEdit: themeStore.hasUnlockedThemes ? { push(.editTheme(customTheme.id)) } : nil
                    ) {
                        editorAppearanceStore.setSelectedThemeID(customTheme.id.uuidString, using: themeStore)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if themeStore.canDeleteTheme(id: customTheme.id) {
                            Button(role: .destructive) {
                                // Explicit theme mutations are ThemeStore-owned and serialized there;
                                // do not cancel user-requested persistence with view lifetime changes.
                                Task {
                                    let didDelete = await themeStore.delete(id: customTheme.id)
                                    editorAppearanceStore.fallBackToAdaptiveThemeIfSelectedThemeWasDeleted(
                                        customTheme.id,
                                        didDelete: didDelete
                                    )
                                }
                            } label: {
                                GradientIconLabel("Delete", systemName: "trash", color: .red)
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if themeStore.hasUnlockedThemes {
                            Button {
                                push(.editTheme(customTheme.id))
                            } label: {
                                GradientIconLabel("Edit", systemName: "pencil", color: .orange)
                            }
                            .tint(.orange)
                        }
                    }
                }

                Button {
                    push(.newTheme)
                } label: {
                    NewThemeSettingsLabel()
                }
                .disabled(ThemeEntitlementGate.canCreateCustomTheme(hasUnlockedThemes: themeStore.hasUnlockedThemes) == false)

                Button {
                    isImportingTheme = true
                } label: {
                    ImportThemeSettingsLabel()
                }
                .disabled(ThemeEntitlementGate.canImportCustomThemes(hasUnlockedThemes: themeStore.hasUnlockedThemes) == false)

            } header: {
                Text("Themes")
            } footer: {
                Text("Support the app development and unlock themes")
                    .settingsFooterStyle()
            }

            Section {
                Toggle(
                    "Match Editor Menus to Theme",
                    isOn: Binding(
                        get: { editorAppearanceStore.matchSystemChromeToTheme },
                        set: { editorAppearanceStore.setMatchSystemChromeToTheme($0) }
                    )
                )
                .disabled(themeStore.hasUnlockedThemes == false)
            } footer: {
                Text("When enabled, editor menus and keyboard controls follow the selected editor theme instead of the app appearance.")
                    .settingsFooterStyle()
            }
        }
        .navigationTitle("Extra Themes")
        .fileImporter(
            isPresented: $isImportingTheme,
            allowedContentTypes: [.json]
        ) { result in
            // Import is an explicit user action. The file read can outlive this view, while
            // ThemeStore owns duplicate/import serialization and user-readable errors.
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
        .onAppear {
            editorAppearanceStore.fallBackToAdaptiveThemeIfSelectedCustomThemeIsNotEntitled(using: themeStore)
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
        guard ThemeEntitlementGate.canImportCustomThemes(hasUnlockedThemes: themeStore.hasUnlockedThemes) else {
            themeStore.lastError = ThemeEntitlementGate.lockedMessage
            return
        }

        await ThemeSettingsImportHandler.handle(
            result: result,
            themeStore: themeStore,
            hasUnlockedThemes: themeStore.hasUnlockedThemes
        ) { url in
            try await themeImportService.loadThemes(from: url)
        }
    }
}

private struct ImportThemeSettingsLabel: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.arrow.down")
                .symbolRenderingMode(.palette)
                .foregroundStyle(squareOutlineGradient, .green)
                .frame(width: 22)
                .accessibilityHidden(true)

            Text("Import Theme")
        }
    }

    private var squareOutlineGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(uiColor: .label),
                Color(uiColor: .label).opacity(0.7)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

private struct NewThemeSettingsLabel: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
                .frame(width: 22)
                .accessibilityHidden(true)

            Text("New Theme")
        }
    }
}

enum ThemeSettingsImportHandler {
    typealias LoadThemes = @Sendable (URL) async throws -> [CustomTheme]

    @MainActor
    static func handle(
        result: Result<URL, Error>,
        themeStore: ThemeStore,
        hasUnlockedThemes: Bool = true,
        loadThemes: LoadThemes
    ) async {
        guard ThemeEntitlementGate.canImportCustomThemes(hasUnlockedThemes: hasUnlockedThemes) else {
            themeStore.lastError = ThemeEntitlementGate.lockedMessage
            return
        }

        do {
            let url = try result.get()
            let themes = try await loadThemes(url)
            _ = await themeStore.importThemes(themes)
        } catch {
            guard isUserCancelled(error) == false else {
                return
            }
            themeStore.lastError = ThemeImportErrorFormatter.message(for: error)
        }
    }

    private static func isUserCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.userCancelled.rawValue
    }
}

struct ThemeSelectionRow: View {
    let theme: EditorTheme
    let isSelected: Bool
    var isEnabled = true
    var onEdit: (() -> Void)?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                guard isEnabled else {
                    return
                }

                action()
            } label: {
                HStack {
                    ThemePreviewSwatch(theme: theme)
                    Text(theme.label)
                        .opacity(isEnabled ? 1 : 0.55)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .symbolGradient(.accentColor)
                            .bold()
                            .opacity(isEnabled ? 1 : 0.55)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isEnabled ? [] : .isStaticText)

            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3)
                        .symbolGradient(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ThemePreviewSwatch: View {
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

#Preview("Theme Settings") {
    ThemeSettingsPage(
        editorAppearanceStore: EditorAppearanceStore(),
        themeStore: makePreviewThemeStore(),
        push: { _ in },
        backAction: {}
    )
}
