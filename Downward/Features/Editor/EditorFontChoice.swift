import Foundation

enum EditorFontChoice: String, Codable, CaseIterable, Sendable {
    case `default`
    case systemMonospaced
    case menlo
    case courier
    case courierNew

    var displayName: String {
        switch self {
        case .default:
            "Default"
        case .systemMonospaced:
            "System Monospaced"
        case .menlo:
            "Menlo"
        case .courier:
            "Courier"
        case .courierNew:
            "Courier New"
        }
    }

    var runtimeFontName: String? {
        switch self {
        case .default, .systemMonospaced:
            nil
        case .menlo:
            "Menlo-Regular"
        case .courier:
            "Courier"
        case .courierNew:
            "CourierNewPSMT"
        }
    }
}
