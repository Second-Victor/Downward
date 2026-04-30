import SwiftUI

struct SupporterUnlockSettingsPage: View {
    let editorAppearanceStore: EditorAppearanceStore
    let themeStore: ThemeStore
    let backAction: () -> Void

    private let benefits = SupporterBenefit.all

    var body: some View {
        Form {
            if themeStore.hasUnlockedThemes {
                Section {
                    Label {
                        Text("Thanks for being a supporter")
                            .font(.headline)
                    } icon: {
                        Image(systemName: "heart.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .pink)
                    }
                } footer: {
                    Text("Your supporter unlock is active on this device.")
                        .settingsFooterStyle()
                }
            }

            Section {
                ForEach(benefits) { benefit in
                    SupporterBenefitRow(benefit: benefit)
                }
            } header: {
                Text("Benefits")
            } footer: {
                Text("A one-time supporter unlock helps fund Downward and unlocks some nice perks.")
                    .settingsFooterStyle()
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
        .navigationTitle(themeStore.hasUnlockedThemes ? "Supporter" : "Supporter Unlock")
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

struct SupporterBenefit: Identifiable {
    let id: String
    let systemName: String
    let color: Color
    let title: String
    let detail: String

    static let all = [
        SupporterBenefit(
            id: "themes",
            systemName: "paintpalette.fill",
            color: .accentColor,
            title: "Extra Themes",
            detail: "Select, edit, create, import, and export custom editor themes."
        ),
        SupporterBenefit(
            id: "fonts",
            systemName: "textformat",
            color: .blue,
            title: "Custom Fonts",
            detail: "Import font families and use them throughout the editor."
        ),
        SupporterBenefit(
            id: "support",
            systemName: "heart.fill",
            color: .pink,
            title: "Support Development",
            detail: "Help keep Downward polished, maintained, and improving."
        )
    ]
}

private struct SupporterBenefitRow: View {
    let benefit: SupporterBenefit

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: benefit.systemName)
                .font(.body.weight(.semibold))
                .symbolGradient(benefit.color)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(benefit.title)
                    .foregroundStyle(.primary)

                Text(benefit.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
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
}
