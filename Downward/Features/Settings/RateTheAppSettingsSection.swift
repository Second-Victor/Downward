import StoreKit
import SwiftUI

struct RateTheAppSettingsRow: View {
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        Button {
            requestReview()
        } label: {
            SettingsHomeRow(
                systemName: "star.fill",
                colors: [.yellow],
                title: "Rate the App",
                detail: nil
            )
        }
        .buttonStyle(.plain)
    }
}
