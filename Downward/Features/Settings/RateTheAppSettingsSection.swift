import SwiftUI

struct RateTheAppSettingsSection: View {
    let appStoreReviewURL: URL

    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            Button {
                openURL(appStoreReviewURL)
            } label: {
                SettingsHomeLabel(title: "Rate the App", systemName: "star.fill", colors: [.yellow])
            }
            .buttonStyle(.plain)
        } footer: {
            Text("If Downward is working well for you, leaving a rating helps.")
                .settingsFooterStyle()
        }
    }
}
