import SwiftUI

struct InformationSettingsPage: View {
    let push: (SettingsPage) -> Void
    let backAction: () -> Void
    var releaseConfiguration: SettingsReleaseConfiguration = .current

    var body: some View {
        Form {
            if let appStoreReviewURL = releaseConfiguration.appStoreReviewURL,
               releaseConfiguration.showsRateTheApp {
                RateTheAppSettingsSection(appStoreReviewURL: appStoreReviewURL)
            }

            Section {
                Button {
                    push(.about)
                } label: {
                    SettingsHomeLabel(title: "About", systemName: "info.circle", colors: [.blue])
                }
                .buttonStyle(.plain)
            } footer: {
                Text("Version details, privacy policy, and terms are available in About.")
                    .settingsFooterStyle()
            }
        }
        .navigationTitle("Information")
        .fontDesign(.rounded)
    }
}
