import SwiftUI

enum AppColorScheme: String, CaseIterable {
    static let storageKey = "app.colorScheme"

    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system:
            "circle.lefthalf.filled"
        case .light:
            "sun.max.fill"
        case .dark:
            "moon.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .system:
            .gray
        case .light:
            .orange
        case .dark:
            .indigo
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}
