import SwiftUI

@main
struct MarkdownWorkspaceApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            RootScreen(viewModel: container.rootViewModel)
                .onChange(of: scenePhase, initial: true) { _, newPhase in
                    container.lifecycleObserver.update(phase: newPhase)
                    container.rootViewModel.handleScenePhaseChange(newPhase)
                }
        }
    }
}
