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
    var usesDiscreteColorDots = false
    var usesMulticolor = false

    var body: some View {
        HStack(spacing: 10) {
            SettingsHomeSymbol(
                systemName: systemName,
                colors: colors,
                usesDiscreteColorDots: usesDiscreteColorDots,
                usesMulticolor: usesMulticolor
            )
            Text(title)
        }
    }
}

struct SettingsHomeSymbol: View {
    let systemName: String
    let colors: [Color]
    var usesDiscreteColorDots = false
    var usesMulticolor = false

    @ViewBuilder
    var body: some View {
        if usesDiscreteColorDots {
            SettingsColorDotCluster(colors: colors)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
        } else {
            Image(systemName: systemName)
                .symbolRenderingMode(usesMulticolor ? .multicolor : .hierarchical)
                .foregroundStyle(
                    LinearGradient(
                        colors: resolvedColors,
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 22)
                .accessibilityHidden(true)
        }
    }

    private var resolvedColors: [Color] {
        let resolvedColors: [Color]

        if colors.isEmpty {
            resolvedColors = [.primary, .primary.opacity(0.7)]
        } else if colors.count == 1, let color = colors.first {
            resolvedColors = [color, color.opacity(0.7)]
        } else {
            resolvedColors = colors
        }

        return resolvedColors
    }
}

private struct SettingsColorDotCluster: View {
    let colors: [Color]

    var body: some View {
        ZStack {
            dot(at: CGPoint(x: 7, y: 4.5), color: color(at: 0, fallback: .orange))
            dot(at: CGPoint(x: 15, y: 4.5), color: color(at: 1, fallback: .pink))
            dot(at: CGPoint(x: 3.5, y: 11), color: color(at: 2, fallback: Color(uiColor: .label)))
            dot(at: CGPoint(x: 11, y: 11), color: color(at: 3, fallback: .green))
            dot(at: CGPoint(x: 18.5, y: 11), color: color(at: 4, fallback: .purple))
            dot(at: CGPoint(x: 7, y: 17.5), color: color(at: 5, fallback: .blue))
            dot(at: CGPoint(x: 15, y: 17.5), color: color(at: 6, fallback: .yellow))
        }
    }

    private func dot(at point: CGPoint, color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 7.5, height: 7.5)
            .position(point)
    }

    private func color(at index: Int, fallback: Color) -> Color {
        guard colors.indices.contains(index) else {
            return fallback
        }

        return colors[index]
    }
}
