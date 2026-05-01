import SwiftUI
import StoreKit

struct TipsSettingsPage: View {
    let backAction: () -> Void

    @State private var tipJarManager = TipJarManager()

    var body: some View {
        Form {
            Section {
                if tipJarManager.isLoadingProducts {
                    HStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading tips...")
                            .foregroundStyle(.secondary)
                    }
                } else if tipJarManager.products.isEmpty {
                    ContentUnavailableView(
                        "Tips Unavailable",
                        systemImage: "heart.slash",
                        description: Text("Tip purchases could not be loaded. Try again later.")
                    )
                } else {
                    ForEach(tipJarManager.products, id: \.id) { product in
                        Button {
                            Task {
                                await tipJarManager.purchase(product)
                            }
                        } label: {
                            SettingsTipProductRow(
                                product: product,
                                purchaseInProgress: tipJarManager.purchaseInProgress
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(tipJarManager.purchaseInProgress)
                        .accessibilityLabel(tipAccessibilityLabel(for: product))
                        .accessibilityHint("Purchases \(product.displayName) for \(product.displayPrice).")
                    }
                }
            } footer: {
                Text("Tips help support the ongoing development and maintenance of Downward. Thank you for your support!")
                    .settingsFooterStyle()
            }
        }
        .navigationTitle("Tip Jar")
        .task {
            await tipJarManager.loadProducts()
        }
        .alert(purchaseAlertTitle, isPresented: purchaseAlertBinding) {
            Button(purchaseAlertButtonLabel) {
                tipJarManager.resetPurchaseState()
            }
        } message: {
            switch tipJarManager.purchaseState {
            case let .success(productName):
                Text("Your \(productName) tip is greatly appreciated.")
            case let .failed(error):
                Text(error)
            case .idle, .purchasing:
                EmptyView()
            }
        }
    }

    private var purchaseAlertTitle: String {
        switch tipJarManager.purchaseState {
        case .success:
            "Thank You"
        case .failed:
            "Purchase Failed"
        case .idle, .purchasing:
            ""
        }
    }

    private var purchaseAlertButtonLabel: String {
        switch tipJarManager.purchaseState {
        case .success:
            "Done"
        case .failed, .idle, .purchasing:
            "OK"
        }
    }

    private func tipAccessibilityLabel(for product: Product) -> String {
        [
            product.displayName,
            product.description,
            product.displayPrice,
        ]
        .filter { $0.isEmpty == false }
        .joined(separator: ", ")
    }

    private var purchaseAlertBinding: Binding<Bool> {
        Binding(
            get: {
                switch tipJarManager.purchaseState {
                case .success, .failed:
                    true
                case .idle, .purchasing:
                    false
                }
            },
            set: { isPresented in
                if isPresented == false {
                    tipJarManager.resetPurchaseState()
                }
            }
        )
    }
}

struct SettingsTipProductRow: View {
    let product: Product
    let purchaseInProgress: Bool

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: symbolName)
                .font(.body.weight(.semibold))
                .symbolGradient(color)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(product.displayName)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(product.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if purchaseInProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(product.displayPrice)
                    .font(.body.weight(.bold))
                    .foregroundStyle(.blue)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private var symbolName: String {
        if product.price < 2 {
            return "cup.and.saucer.fill"
        } else if product.price < 4 {
            return "mug.fill"
        } else if product.price < 8 {
            return "fork.knife"
        } else {
            return "gift.fill"
        }
    }

    private var color: Color {
        if product.price < 2 {
            return .brown.opacity(0.65)
        } else if product.price < 4 {
            return .orange.opacity(0.75)
        } else if product.price < 8 {
            return .teal.opacity(0.65)
        } else {
            return .pink.opacity(0.72)
        }
    }
}

#Preview("Tips Settings") {
    TipsSettingsPage(backAction: {})
}
