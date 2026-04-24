import SwiftUI

struct InformationSettingsPage: View {
    let push: (SettingsPage) -> Void
    let backAction: () -> Void

    var body: some View {
        SettingsShell {
            SettingsPageHeader(title: "Information", backAction: backAction)

            SettingsCard {
                SettingsNavigationRow(
                    icon: .symbol("star.fill"),
                    iconTint: .yellow,
                    title: "Rate the App",
                    value: nil,
                    isEnabled: false,
                    action: {}
                )
                .accessibilityHint("App Store review routing is not implemented yet.")
            }

            SettingsHelperText("If Downward is working well for you, leaving a rating helps.")

            SettingsCard {
                SettingsNavigationRow(
                    icon: .symbol("info.circle"),
                    iconTint: .blue.opacity(0.55),
                    title: "About",
                    value: nil,
                    action: { push(.about) }
                )
            }

            SettingsHelperText("Version details, privacy policy, and terms are available in About.")
        }
    }
}

struct AboutSettingsPage: View {
    let backAction: () -> Void

    var body: some View {
        SettingsShell {
            SettingsPageHeader(title: "", backAction: backAction)

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
            .padding(.top, 24)
            .padding(.bottom, 12)

            SettingsCard {
                SettingsNavigationRow(
                    icon: .symbol("hand.raised.fill"),
                    iconTint: .blue,
                    title: "Privacy Policy",
                    value: nil,
                    isEnabled: false,
                    action: {}
                )
                .accessibilityHint("Privacy Policy URL is not configured yet.")
                SettingsDivider()
                SettingsNavigationRow(
                    icon: .symbol("doc.text.fill"),
                    iconTint: .blue,
                    title: "Terms & Conditions",
                    value: nil,
                    isEnabled: false,
                    action: {}
                )
                .accessibilityHint("Terms and Conditions URL is not configured yet.")
            }
        }
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
