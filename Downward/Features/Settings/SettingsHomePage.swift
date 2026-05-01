import SwiftUI

enum SettingsHomeReleaseRow: Equatable {
    case tips
    case rateTheApp
}

struct SettingsHomeReleaseSurfaces: Equatable {
    let showsTipsRow: Bool
    let showsRateTheAppRow: Bool

    init(showsTipsRow: Bool, showsRateTheAppRow: Bool) {
        self.showsTipsRow = showsTipsRow
        self.showsRateTheAppRow = showsRateTheAppRow
    }

    init(configuration: SettingsReleaseConfiguration) {
        showsTipsRow = configuration.showsTipsPage
        showsRateTheAppRow = configuration.showsRateTheApp
    }

    var visibleRows: [SettingsHomeReleaseRow] {
        var rows: [SettingsHomeReleaseRow] = []
        if showsTipsRow {
            rows.append(.tips)
        }
        if showsRateTheAppRow {
            rows.append(.rateTheApp)
        }
        return rows
    }
}

struct SettingsHomePage: View {
    let summary: SettingsHomeSummary
    @Binding var appColorScheme: AppColorScheme
    let hasUnlockedThemes: Bool
    let doneAction: () -> Void
    var releaseConfiguration: SettingsReleaseConfiguration = .current

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
                        colors: [.accentColor],
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
                NavigationLink(value: SettingsPage.workspace) {
                    SettingsHomeRow(
                        systemName: "folder",
                        colors: [.blue],
                        title: "Workspace",
                        detail: summary.workspaceName
                    )
                }
            }

            Section {
                NavigationLink(value: SettingsPage.about) {
                    SettingsHomeRow(
                        systemName: "info.circle",
                        colors: [.blue],
                        title: "About",
                        detail: nil
                    )
                }

                if releaseSurfaces.showsRateTheAppRow {
                    RateTheAppSettingsRow()
                }
            } header: {
                Text("Information")
            }

            Section {
                NavigationLink(value: SettingsPage.supporterUnlock) {
                    SettingsHomeRow(
                        systemName: "heart.fill",
                        colors: [.pink, Color(red: 1.0, green: 0.31, blue: 0.58)],
                        title: hasUnlockedThemes ? "Thanks for being a supporter" : "Supporter",
                        detail: hasUnlockedThemes ? nil : "Perks"
                    )
                }

                if releaseSurfaces.showsTipsRow {
                    NavigationLink(value: SettingsPage.tips) {
                        SettingsHomeRow(
                            systemName: "banknote.fill",
                            colors: [.green],
                            title: "Tips",
                            detail: nil
                        )
                    }
                }
            } header: {
                Text("Support the App")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: doneAction)
            }
        }
        .roundedNavigationBarTitles()
    }

    private var releaseSurfaces: SettingsHomeReleaseSurfaces {
        SettingsHomeReleaseSurfaces(configuration: releaseConfiguration)
    }
}

struct SettingsHomeRow: View {
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

struct SettingsHomeLabel: View {
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

struct SettingsHomeSymbol: View {
    let systemName: String
    let colors: [Color]
    var usesMulticolor = false

    @ViewBuilder
    var body: some View {
        if usesMulticolor {
            Image(systemName: systemName)
                .symbolRenderingMode(.multicolor)
                .frame(width: 22)
                .accessibilityHidden(true)
        } else {
            Image(systemName: systemName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(symbolGradient)
                .frame(width: 22)
                .accessibilityHidden(true)
        }
    }

    private var symbolGradient: LinearGradient {
        LinearGradient(
            colors: colors.isEmpty ? [.primary] : colors,
            startPoint: .bottomLeading,
            endPoint: .topTrailing
        )
    }
}
