import Observation
import SwiftUI

@MainActor
@Observable
final class LifecycleObserver {
    var latestScenePhase: ScenePhase = .active

    func update(phase: ScenePhase) {
        latestScenePhase = phase
    }
}
