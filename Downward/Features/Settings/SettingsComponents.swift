import SwiftUI

struct SettingsShell<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .frame(maxWidth: contentWidth, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 24)
                .padding(.bottom, 34)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var contentWidth: CGFloat? {
        horizontalSizeClass == .regular ? 720 : nil
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 32 : 20
    }
}

enum SettingsHeaderTitlePlacement {
    case leading
    case center
}

struct SettingsPageHeader<Trailing: View>: View {
    let title: String
    var titlePlacement: SettingsHeaderTitlePlacement = .leading
    var backAction: (() -> Void)?
    @ViewBuilder let trailing: Trailing

    init(
        title: String,
        titlePlacement: SettingsHeaderTitlePlacement = .leading,
        backAction: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.titlePlacement = titlePlacement
        self.backAction = backAction
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                if let backAction {
                    Button(action: backAction) {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.bold))
                            .symbolGradient(.primary)
                            .frame(width: 52, height: 52)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                if titlePlacement == .center {
                    Spacer(minLength: 12)
                    Text(title)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                    Spacer(minLength: 12)
                } else {
                    Spacer(minLength: 12)
                }

                trailing
            }
            .frame(minHeight: 52)

            if titlePlacement == .leading, title.isEmpty == false {
                Text(title)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            }
        }
    }
}

extension SettingsPageHeader where Trailing == EmptyView {
    init(
        title: String,
        titlePlacement: SettingsHeaderTitlePlacement = .leading,
        backAction: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            titlePlacement: titlePlacement,
            backAction: backAction,
            trailing: { EmptyView() }
        )
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

struct SettingsDivider: View {
    var leadingInset: CGFloat = 74

    var body: some View {
        Divider()
            .padding(.leading, leadingInset)
            .padding(.trailing, 28)
    }
}

enum SettingsIcon {
    case symbol(String)
    case text(String)
}

struct SettingsNavigationRow: View {
    let icon: SettingsIcon
    let iconTint: Color
    let title: String
    let value: String?
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowContent(
                icon: icon,
                iconTint: iconTint,
                title: title,
                value: value,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

struct SettingsMenuStyleRow: View {
    let icon: SettingsIcon
    let iconTint: Color
    let title: String
    let value: String

    var body: some View {
        SettingsRowContent(
            icon: icon,
            iconTint: iconTint,
            title: title,
            value: value,
            showsChevron: false,
            trailingSystemImage: "chevron.up.chevron.down"
        )
        .opacity(0.9)
        .accessibilityHint("App appearance selection is not implemented yet.")
    }
}

struct SettingsRowContent: View {
    let icon: SettingsIcon
    let iconTint: Color
    let title: String
    let value: String?
    var showsChevron = false
    var trailingSystemImage: String?

    var body: some View {
        HStack(spacing: 18) {
            SettingsIconView(icon: icon, tint: iconTint)

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 12)

            if let value {
                Text(value)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .symbolGradient(Color(uiColor: .tertiaryLabel))
            }

            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .font(.body.weight(.semibold))
                    .symbolGradient(.primary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct SettingsIconView: View {
    let icon: SettingsIcon
    let tint: Color

    var body: some View {
        Group {
            switch icon {
            case let .symbol(systemName):
                Image(systemName: systemName)
                    .font(.body.weight(.semibold))
                    .symbolGradient(tint)
            case let .text(text):
                Text(text)
                    .font(.body.weight(.medium))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

struct SettingsSelectableRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .symbolGradient(.blue)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsStepperRow: View {
    let icon: SettingsIcon
    let iconTint: Color
    let title: String
    let value: String
    let decrementAction: () -> Void
    let incrementAction: () -> Void
    let canDecrement: Bool
    let canIncrement: Bool

    var body: some View {
        HStack(spacing: 18) {
            SettingsIconView(icon: icon, tint: iconTint)

            Text(title)
                .font(.body)

            Spacer(minLength: 10)

            Text(value)
                .font(.body)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            HStack(spacing: 0) {
                Button(action: decrementAction) {
                    Image(systemName: "minus")
                        .symbolGradient(.primary)
                        .frame(width: 46, height: 34)
                }
                .disabled(canDecrement == false)

                Divider()
                    .frame(height: 24)

                Button(action: incrementAction) {
                    Image(systemName: "plus")
                        .symbolGradient(.primary)
                        .frame(width: 46, height: 34)
                }
                .disabled(canIncrement == false)
            }
            .font(.body.weight(.bold))
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule(style: .continuous))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }
}

struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var isEnabled = true
    var accessibilityHint: String?

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .disabled(isEnabled == false)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityHint(accessibilityHint ?? "")
    }
}

struct SettingsHelperText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 28)
            .padding(.top, -12)
    }
}

extension View {
    func settingsFooterStyle() -> some View {
        font(.system(.footnote, design: .rounded))
    }
}
