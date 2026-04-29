import SwiftUI

struct InformationSettingsPage: View {
    let push: (SettingsPage) -> Void
    let backAction: () -> Void
    var releaseConfiguration: SettingsReleaseConfiguration = .current

    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            if let appStoreReviewURL = releaseConfiguration.appStoreReviewURL,
               releaseConfiguration.showsRateTheApp {
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

struct AboutSettingsPage: View {
    let backAction: () -> Void
    var releaseConfiguration: SettingsReleaseConfiguration = .current

    @ScaledMetric private var iconFrameSize: CGFloat = 116
    @ScaledMetric private var iconCornerRadius: CGFloat = 26

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.clear, .gray.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                Spacer(minLength: 28)

                Image("DownwardBrandedIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconFrameSize, height: iconFrameSize)
                    .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 10)
                    .padding(.bottom, 18)

                Text("Downward")
                    .font(.system(.largeTitle, design: .rounded).bold())

                Text(versionText)
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                Text("Second Victor Ltd.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                Text("A calm markdown editor for real folders in Files.")
                    .font(.system(.callout, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.top, 14)

                Spacer(minLength: 28)

                VStack(spacing: 12) {
                    if let projectURL = releaseConfiguration.projectURL {
                        AboutLinkRow(systemName: "safari", title: "Website", destination: projectURL)
                    }

                    if let privacyPolicyURL = releaseConfiguration.privacyPolicyURL {
                        AboutLinkRow(systemName: "lock", title: "Privacy Policy", destination: privacyPolicyURL)
                    }

                    if let termsAndConditionsURL = releaseConfiguration.termsAndConditionsURL {
                        AboutLinkRow(systemName: "checkmark.seal", title: "Terms & Conditions", destination: termsAndConditionsURL)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 30)
        }
        .navigationTitle("About")
        .fontDesign(.rounded)
    }

    private var versionText: String {
        let infoDictionary = Bundle.main.infoDictionary
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

}

private struct AboutLinkRow: View {
    let systemName: String
    let title: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                Text(title)
            }
            .font(.system(.callout, design: .rounded).weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
    }
}
