import Combine
import SwiftUI

@main
struct MarkdownWorkspaceApp: App {
    var body: some Scene {
        WindowGroup {
            AppSceneRoot()
        }
    }
}

private struct AppSceneRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var sceneContainer = AppSceneContainer()
    @AppStorage(AppColorScheme.storageKey) private var appColorSchemeRaw = AppColorScheme.system.rawValue

    var body: some View {
        RootScreen(viewModel: sceneContainer.container.rootViewModel)
            .preferredColorScheme(appColorScheme.colorScheme)
            .fontDesign(.rounded)
            .onChange(of: scenePhase, initial: true) { _, newPhase in
                sceneContainer.container.rootViewModel.handleScenePhaseChange(newPhase)
            }
    }

    private var appColorScheme: AppColorScheme {
        AppColorScheme(rawValue: appColorSchemeRaw) ?? .system
    }
}

@MainActor
private final class AppSceneContainer: ObservableObject {
    // WindowGroup may create multiple iPadOS scenes. Each scene needs its own
    // container so navigation and the live document slot do not mirror windows.
    let container = AppContainer.live()
}
