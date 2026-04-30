import SwiftUI

struct AboutSettingsPage: View {
    let backAction: () -> Void
    var releaseConfiguration: SettingsReleaseConfiguration = .current

    private static let companyURL = URL(string: "https://secondvictor.com")!

    @ScaledMetric(relativeTo: .largeTitle) private var iconFrameSize: CGFloat = 170

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [.clear, .gray.opacity(0.1)]),
                startPoint: .top,
                endPoint: .bottomTrailing
            )

            VStack {
                Spacer()

                Image("DownwardBrandedIcon")
                    .resizable()
                    .frame(width: iconFrameSize, height: iconFrameSize)

                appTitle

                Text(versionText)
                    .font(.system(.caption, design: .rounded))

                Spacer()

                Link("Second Victor Ltd.", destination: Self.companyURL)
                    .font(.system(.body, design: .rounded).bold())
                    .foregroundStyle(.primary)
                    .padding(.bottom, 10)
                    .accessibilityHint("Opens the Second Victor website in Safari")

                if let privacyPolicyURL = releaseConfiguration.privacyPolicyURL {
                    AboutLinkRow(systemName: "lock", title: "Privacy Policy", destination: privacyPolicyURL)
                        .padding(.bottom, 1)
                }

                if let termsAndConditionsURL = releaseConfiguration.termsAndConditionsURL {
                    AboutLinkRow(systemName: "checkmark.seal", title: "Terms & Conditions", destination: termsAndConditionsURL)
                        .padding(.bottom, 10)
                }
            }
            .padding(.bottom, 30)
        }
        .navigationTitle("About")
        .ignoresSafeArea(.all)
        .fontDesign(.rounded)
    }

    @ViewBuilder
    private var appTitle: some View {
        if let projectURL = releaseConfiguration.projectURL {
            Link("Downward", destination: projectURL)
                .font(.system(.largeTitle, design: .rounded).bold())
                .foregroundStyle(.primary)
                .accessibilityHint("Opens the Downward project page in Safari")
        } else {
            Text("Downward")
                .font(.system(.largeTitle, design: .rounded).bold())
        }
    }

    private var versionText: String {
        let infoDictionary = Bundle.main.infoDictionary
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(version) © 2026"
    }
}

private struct AboutLinkRow: View {
    let systemName: String
    let title: String
    let destination: URL

    var body: some View {
        HStack {
            Image(systemName: systemName)
            Link(title, destination: destination)
                .foregroundStyle(.primary)
                .accessibilityHint("Opens \(title) in Safari")
        }
        .font(.system(.body, design: .rounded))
    }
}
