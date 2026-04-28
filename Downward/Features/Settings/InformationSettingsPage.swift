import SwiftUI

struct InformationSettingsPage: View {
    let push: (SettingsPage) -> Void
    let backAction: () -> Void
    var releaseConfiguration: SettingsReleaseConfiguration = .current

    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            if let appStoreReviewURL = releaseConfiguration.appStoreReviewURL {
                Section {
                    Button {
                        openURL(appStoreReviewURL)
                    } label: {
                        Label("Rate the App", systemImage: "star.fill")
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
                    Label("About", systemImage: "info.circle")
                }
                .buttonStyle(.plain)
            } footer: {
                Text("Version details are available in About.")
                    .settingsFooterStyle()
            }
        }
        .navigationTitle("Information")
    }
}

struct AboutSettingsPage: View {
    let backAction: () -> Void
    var releaseConfiguration: SettingsReleaseConfiguration = .current

    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                VStack(spacing: 14) {
                    AppIconPlaceholder()

                    Text("Downward")
                        .font(.title.weight(.bold))

                    Text(versionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Second Victor Ltd.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }

            if releaseConfiguration.showsLegalLinks {
                Section {
                    if let privacyPolicyURL = releaseConfiguration.privacyPolicyURL {
                        Button {
                            openURL(privacyPolicyURL)
                        } label: {
                            Label("Privacy Policy", systemImage: "hand.raised.fill")
                        }
                        .buttonStyle(.plain)
                    }

                    if let termsAndConditionsURL = releaseConfiguration.termsAndConditionsURL {
                        Button {
                            openURL(termsAndConditionsURL)
                        } label: {
                            Label("Terms & Conditions", systemImage: "doc.text.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("About")
    }

    private var versionText: String {
        let infoDictionary = Bundle.main.infoDictionary
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }
}

struct AppIconPlaceholder: View {
    var body: some View {
        Image("AppIcon")
            .resizable()
            .scaledToFit()
            .background(
                LinearGradient(
                    colors: [.blue, .teal],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .frame(width: 96, height: 96)
            .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 14)
            .accessibilityLabel("Downward app icon")
    }
}
