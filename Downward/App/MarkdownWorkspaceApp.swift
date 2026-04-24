import SwiftUI

@main
struct MarkdownWorkspaceApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var container = AppContainer.live()
    @AppStorage(AppColorScheme.storageKey) private var appColorSchemeRaw = AppColorScheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootScreen(viewModel: container.rootViewModel)
                .preferredColorScheme(appColorScheme.colorScheme)
                .onChange(of: scenePhase, initial: true) { _, newPhase in
                    container.rootViewModel.handleScenePhaseChange(newPhase)
                }
        }
    }

    private var appColorScheme: AppColorScheme {
        AppColorScheme(rawValue: appColorSchemeRaw) ?? .system
    }
}
