import Foundation

struct DebugLogger: Sendable {
    nonisolated func log(_ message: String) {
        #if DEBUG
        print("[Downward] \(message)")
        #endif
    }

    nonisolated func log(category: String, _ message: String) {
        log("[\(category)] \(message)")
    }
}
