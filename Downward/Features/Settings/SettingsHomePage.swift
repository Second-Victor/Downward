import SwiftUI

struct SettingsHomePage: View {
    let summary: SettingsHomeSummary
    @Binding var appColorScheme: AppColorScheme
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
                if releaseConfiguration.showsTipsPage {
                    NavigationLink(value: SettingsPage.tips) {
                        SettingsHomeRow(
                            systemName: "banknote.fill",
                            colors: [.green],
                            title: "Tips",
                            detail: nil
                        )
                    }
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
        .roundedNavigationBarTitles()
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
                .symbolGradient(colors.first ?? .primary)
                .frame(width: 22)
                .accessibilityHidden(true)
        }
    }
}
