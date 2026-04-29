import SwiftUI

extension View {
    func symbolGradient(_ color: Color) -> some View {
        foregroundStyle(
            LinearGradient(
                colors: [color, color.opacity(0.7)],
                startPoint: .bottom,
                endPoint: .top
            )
        )
    }
}

struct GradientIconLabel: View {
    let title: String
    let systemName: String
    let color: Color

    init(_ title: String, systemName: String, color: Color = .accentColor) {
        self.title = title
        self.systemName = systemName
        self.color = color
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemName)
                .symbolRenderingMode(.hierarchical)
                .symbolGradient(color)
                .accessibilityHidden(true)
        }
    }
}

struct GradientContentUnavailableView<Description: View>: View {
    let title: String
    let systemName: String
    let color: Color
    @ViewBuilder let description: Description

    init(
        _ title: String,
        systemName: String,
        color: Color = .accentColor,
        @ViewBuilder description: () -> Description
    ) {
        self.title = title
        self.systemName = systemName
        self.color = color
        self.description = description()
    }

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemName)
                    .symbolGradient(color)
            }
        } description: {
            description
        }
    }
}
