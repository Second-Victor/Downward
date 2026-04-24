import SwiftUI
import UniformTypeIdentifiers

struct ThemeSettingsPage: View {
    let editorAppearanceStore: EditorAppearanceStore
    let themeStore: ThemeStore
    let push: (SettingsPage) -> Void
    let backAction: () -> Void
    private let themeImportService = ThemeImportService()

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
            let themes = try await themeImportService.loadThemes(from: url)
            _ = await themeStore.importThemes(themes)
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

struct ThemeSelectionRow: View {
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
