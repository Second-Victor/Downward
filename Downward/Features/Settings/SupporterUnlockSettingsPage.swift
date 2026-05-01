import SwiftUI

struct SupporterUnlockSettingsPage: View {
    let editorAppearanceStore: EditorAppearanceStore
    let themeStore: ThemeStore
    let backAction: () -> Void
    private let benefits = SupporterBenefit.all

    private var previewThemes: [EditorTheme] {
        let previewThemeNames = ["Monokai", "Solarized", "Sepia Paper"]
        return previewThemeNames.compactMap { name in
            ThemeStore.bundledPremiumThemes.first { $0.name == name }
                .map(EditorTheme.init(from:))
        }
    }

    var body: some View {
        Form {
            if themeStore.hasUnlockedThemes {
                Section {
                    SupporterThanksMessage()
                }
            } else {
                Section {
                    SupporterFundingMessage()
                }

                Section {
                    SupporterThemePreviewStrip(
                        themes: previewThemes
                    )
                } header: {
                    Text("Themes")
                } footer: {
                    Text("Supporters unlock these themes plus more, and you also get theme import, export and editing.")
                        .settingsFooterStyle()
                }

                Section {
                    ForEach(benefits) { benefit in
                        SupporterBenefitRow(benefit: benefit)
                    }
                } header: {
                    Text("Fonts")
                }

                if themeStore.canRestoreThemePurchases {
                    Section {
                        Button {
                            Task {
                                await themeStore.restoreThemePurchases()
                                editorAppearanceStore.setImportedFontsUnlocked(themeStore.hasUnlockedThemes)
                            }
                        } label: {
                            SettingsHomeLabel(
                                title: "Restore Purchases",
                                systemName: "arrow.clockwise.circle.fill",
                                colors: [.purple]
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle(themeStore.hasUnlockedThemes ? "Supporter" : "Supporter Perks")
        .safeAreaInset(edge: .bottom) {
            if themeStore.hasUnlockedThemes == false {
                SupporterPurchaseBar(
                    productName: themeStore.supporterProductDisplayName,
                    price: themeStore.supporterProductDisplayPrice,
                    isLoading: themeStore.isLoadingSupporterProduct,
                    isPurchasing: themeStore.isPurchasingSupporterUnlock
                ) {
                    Task {
                        await themeStore.purchaseSupporterUnlock()
                        editorAppearanceStore.setImportedFontsUnlocked(themeStore.hasUnlockedThemes)
                    }
                }
            }
        }
        .task {
            await themeStore.loadSupporterProduct()
        }
        .alert("Supporter Unlock", isPresented: supporterErrorBinding) {
            Button("OK") { themeStore.clearSupporterPurchaseError() }
        } message: {
            if let error = themeStore.lastError {
                Text(error)
            }
        }
    }

    private var supporterErrorBinding: Binding<Bool> {
        Binding(
            get: { themeStore.lastError != nil },
            set: { isPresented in
                if isPresented == false {
                    themeStore.clearSupporterPurchaseError()
                }
            }
        )
    }
}

private struct SupporterThanksMessage: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 46, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, heartGradient)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("Thanks for being a supporter")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text("Your supporter unlock is active on this device.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var heartGradient: LinearGradient {
        LinearGradient(
            colors: [.pink, .red],
            startPoint: .bottomLeading,
            endPoint: .topTrailing
        )
    }
}

private struct SupporterFundingMessage: View {
    var body: some View {
        HStack(spacing: 14) {
//            Image(systemName: "heart.fill")
//                .font(.body.weight(.semibold))
//                .symbolGradient(.pink)
//                .frame(width: 28)
//                .accessibilityHidden(true)

            Text({
                var s = AttributedString("One-time supporter unlock helps fund Downward and you get some extras.\n\nThe app works great without it, these are just nice to have. 😄")
                if let range = s.range(of: "One-time") {
                    s[range].font = .system(.body, design: .default).weight(.semibold)
                }
                return s
            }())
                .font(.body)
                .foregroundStyle(.primary)
//                .fixedSize(horizontal: false, vertical: true)
        }
//        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
//        .accessibilityElement(children: .combine)
    }
}

private struct SupporterThemePreviewStrip: View {
    let themes: [EditorTheme]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(themes.enumerated()), id: \.element.id) { index, theme in
                SupporterThemePreviewTile(theme: theme)

                if index < themes.count - 1 {
                    Divider()
                        .padding(.leading, 72)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
    }
}

private struct SupporterThemePreviewTile: View {
    let theme: EditorTheme

    var body: some View {
        HStack(spacing: 12) {
            ThemePreviewSwatch(theme: theme)

            Text(theme.label)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(theme.label)
    }
}

struct SupporterBenefit: Identifiable {
    let id: String
    let systemName: String
    let color: Color
    let title: String
    let detail: String

    static let all = [
        SupporterBenefit(
            id: "fonts",
            systemName: "textformat",
            color: .blue,
            title: "Custom Fonts",
            detail: "Import .ttf and .otf font families and use them in the editor."
        )
    ]
}

private struct SupporterBenefitRow: View {
    let benefit: SupporterBenefit

    var body: some View {
        HStack(spacing: 14) {
            benefitIcon
                .font(.body.weight(.semibold))
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(benefit.title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(benefit.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
    }

    @ViewBuilder
    private var benefitIcon: some View {
        Image(systemName: benefit.systemName)
            .symbolGradient(benefit.color)
    }
}

private struct SupporterPurchaseBar: View {
    let productName: String?
    let price: String?
    let isLoading: Bool
    let isPurchasing: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            Button(action: action) {
                HStack(spacing: 10) {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "heart.circle.fill")
                    }

                    Text(buttonTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoading || isPurchasing)
            .accessibilityLabel(accessibilityLabel)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(.bar)
    }

    private var buttonTitle: String {
        if isLoading {
            return "Loading Supporter Unlock..."
        }

        if let productName, let price {
            return "\(productName) - \(price)"
        }

        if let price {
            return "Unlock Supporter Perks - \(price)"
        }

        return "Unlock Supporter Perks"
    }

    private var accessibilityLabel: String {
        if isLoading {
            return "Loading Supporter Unlock"
        }

        if let productName, let price {
            return "\(productName), \(price)"
        }

        if let price {
            return "Unlock Supporter Perks, \(price)"
        }

        return "Unlock Supporter Perks"
    }
}

#Preview("Supporter Unlock Settings") {
    SupporterUnlockSettingsPage(
        editorAppearanceStore: EditorAppearanceStore(),
        themeStore: ThemeStore(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "preview-supporter-\(UUID().uuidString).json"),
            entitlements: ThemeEntitlementStore(hasUnlockedThemes: false)
        ),
        backAction: {}
    )
}

#Preview("Supporter Thanks Settings") {
    SupporterUnlockSettingsPage(
        editorAppearanceStore: EditorAppearanceStore(),
        themeStore: ThemeStore(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "preview-supporter-thanks-\(UUID().uuidString).json"),
            entitlements: ThemeEntitlementStore(hasUnlockedThemes: true)
        ),
        backAction: {}
    )
}
