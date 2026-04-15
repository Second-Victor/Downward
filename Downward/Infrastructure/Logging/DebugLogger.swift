import Foundation

struct DebugLogger: Sendable {
    func log(_ message: String) {
        #if DEBUG
        print("[Downward] \(message)")
        #endif
    }

    func log(category: String, _ message: String) {
        log("[\(category)] \(message)")
    }
}
