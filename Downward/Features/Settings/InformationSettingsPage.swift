import SwiftUI

struct InformationSettingsPage: View {
    let push: (SettingsPage) -> Void
    let backAction: () -> Void

    var body: some View {
        Form {
            Section {
                Label("Rate the App", systemImage: "star.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHint("App Store review routing is not implemented yet.")
            } footer: {
                Text("If Downward is working well for you, leaving a rating helps.")
                    .settingsFooterStyle()
            }

            Section {
                Button {
                    push(.about)
                } label: {
                    Label("About", systemImage: "info.circle")
                }
                .buttonStyle(.plain)
            } footer: {
                Text("Version details, privacy policy, and terms are available in About.")
                    .settingsFooterStyle()
            }
        }
        .navigationTitle("Information")
    }
}

struct AboutSettingsPage: View {
    let backAction: () -> Void

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

            Section {
                Label("Privacy Policy", systemImage: "hand.raised.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Privacy Policy URL is not configured yet.")

                Label("Terms & Conditions", systemImage: "doc.text.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Terms and Conditions URL is not configured yet.")
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
