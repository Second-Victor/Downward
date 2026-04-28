import SwiftUI

struct TipsSettingsPage: View {
    let backAction: () -> Void

    private let tips = [
        TipRow(icon: "cup.and.saucer.fill", tint: Color.brown.opacity(0.65), title: "Small Coffee", caption: "Buy me a small coffee", price: "£0.99"),
        TipRow(icon: "mug.fill", tint: .orange.opacity(0.75), title: "Large Coffee", caption: "Buy me a large coffee", price: "£2.99"),
        TipRow(icon: "fork.knife", tint: .teal.opacity(0.65), title: "Lunch", caption: "Buy me Lunch", price: "£4.99"),
        TipRow(icon: "wineglass.fill", tint: .red.opacity(0.7), title: "Dinner", caption: "Buy me dinner", price: "£9.99")
    ]

    var body: some View {
        Form {
            Section {
                ForEach(tips) { tip in
                    SettingsTipRow(tip: tip)
                }
            } footer: {
                Text("Tips help support the ongoing development of Downward. Thank you.")
                    .settingsFooterStyle()
            }
        }
        .navigationTitle("Tips")
    }
}

struct TipRow: Identifiable, Equatable {
    let icon: String
    let tint: Color
    let title: String
    let caption: String
    let price: String

    var id: String {
        title
    }

    static func == (lhs: TipRow, rhs: TipRow) -> Bool {
        lhs.id == rhs.id
    }
}

struct SettingsTipRow: View {
    let tip: TipRow

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: tip.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tip.tint)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(tip.title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(tip.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(tip.price)
                .font(.body.weight(.bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityHint("StoreKit purchases are not implemented yet.")
    }
}
