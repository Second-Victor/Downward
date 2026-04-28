import SwiftUI

struct SettingsHomePage: View {
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
        .roundedNavigationBarTitles()
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
