import SwiftUI
import UIKit

struct EditorSettingsPage: View {
    let editorAppearanceStore: EditorAppearanceStore
    let backAction: () -> Void

    @State private var selectedCategory: SettingsFontCategory = .monospaced
    @State private var largerHeadingText = false

    var body: some View {
        Form {
            Section {
                Picker("Font Type", selection: $selectedCategory) {
                    ForEach(SettingsFontCategory.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedCategory) { _, category in
                    selectFirstAvailableFont(in: category)
                }

                ForEach(availableFontOptions) { option in
                    SettingsFontRow(
                        option: option,
                        isSelected: editorAppearanceStore.selectedFontChoice == option.choice
                    ) {
                        editorAppearanceStore.setFontChoice(option.choice)
                    }
                }
            } footer: {
                Text("Choose your favourite font.")
                    .settingsFooterStyle()
            }

            Section {
                Stepper(value: fontSizeBinding, in: 12...24, step: 1) {
                    LabeledContent {
                        Text("\(Int(editorAppearanceStore.fontSize)) pt")
                            .foregroundStyle(.secondary)
                    } label: {
                        SettingsHomeLabel(
                            title: "Font Size",
                            systemName: "textformat.size",
                            colors: [.blue]
                        )
                    }
                }
            } footer: {
                Text("Adjust the editor font size relative to the system default.")
                    .settingsFooterStyle()
            }

            if selectedCategory == .monospaced {
                Section {
                    Toggle("Line Numbers", isOn: lineNumbersBinding)
                        .disabled(editorAppearanceStore.selectedFontChoice.isMonospaced == false)
                        .accessibilityHint("Shows line numbers along the left edge of monospaced editor text.")
                } footer: {
                    Text("Show line numbers along the left edge of the editor.")
                        .settingsFooterStyle()
                }
            }

            Section {
                Toggle("Larger Heading Text", isOn: $largerHeadingText)
                    .disabled(true)
                    .accessibilityHint("Larger heading text is not implemented as a user setting yet.")
            } footer: {
                Text(largerHeadingHelperText)
                    .settingsFooterStyle()
            }
        }
        .navigationTitle("Editor")
        .fontDesign(.rounded)
        .onAppear {
            selectedCategory = category(for: editorAppearanceStore.selectedFontChoice)
        }
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { editorAppearanceStore.fontSize },
            set: { editorAppearanceStore.setFontSize($0) }
        )
    }

    private var lineNumbersBinding: Binding<Bool> {
        Binding(
            get: { editorAppearanceStore.showLineNumbers },
            set: { editorAppearanceStore.setShowLineNumbers($0) }
        )
    }

    private var availableFontOptions: [SettingsFontOption] {
        options(for: selectedCategory).filter { option in
            editorAppearanceStore.availableFontChoices.contains(option.choice)
        }
    }

    private func options(for category: SettingsFontCategory) -> [SettingsFontOption] {
        switch category {
        case .monospaced:
            SettingsFontOption.monospacedOptions
        case .proportional:
            SettingsFontOption.proportionalOptions
        }
    }

    private func category(for choice: EditorFontChoice) -> SettingsFontCategory {
        if let option = (SettingsFontOption.monospacedOptions + SettingsFontOption.proportionalOptions)
            .first(where: { $0.choice == choice }) {
            return option.category
        }

        return .proportional
    }

    private func selectFirstAvailableFont(in category: SettingsFontCategory) {
        guard let first = options(for: category).first(where: { option in
            editorAppearanceStore.availableFontChoices.contains(option.choice)
        }) else {
            return
        }

        editorAppearanceStore.setFontChoice(first.choice)
    }

    private var largerHeadingHelperText: String {
        if editorAppearanceStore.effectiveShowLineNumbers {
            return "Larger heading text is unavailable while line numbers are enabled."
        }

        return "Larger heading text will be wired after heading-size preferences are implemented."
    }
}

enum SettingsFontCategory: String, CaseIterable {
    case monospaced = "Monospaced"
    case proportional = "Proportional"
}

struct SettingsFontOption: Identifiable, Equatable {
    let choice: EditorFontChoice
    let displayName: String

    var id: EditorFontChoice {
        choice
    }

    static let monospacedOptions = [
        SettingsFontOption(choice: .systemMonospaced, displayName: "SF Mono"),
        SettingsFontOption(choice: .menlo, displayName: "Menlo"),
        SettingsFontOption(choice: .courierNew, displayName: "Courier New")
    ]

    static let proportionalOptions = [
        SettingsFontOption(choice: .default, displayName: "SF Pro"),
        SettingsFontOption(choice: .newYork, displayName: "New York"),
        SettingsFontOption(choice: .georgia, displayName: "Georgia")
    ]

    var category: SettingsFontCategory {
        switch choice {
        case .systemMonospaced, .menlo, .courier, .courierNew:
            .monospaced
        case .default, .newYork, .georgia:
            .proportional
        }
    }

    var previewFont: Font {
        let size = UIFont.preferredFont(forTextStyle: .body).pointSize

        switch choice {
        case .default:
            return .system(.body, design: .default)
        case .systemMonospaced:
            return .system(.body, design: .monospaced)
        case .menlo:
            return .custom("Menlo", size: size)
        case .courier, .courierNew:
            return .custom("Courier New", size: size)
        case .newYork:
            return .system(.body, design: .serif)
        case .georgia:
            return .custom("Georgia", size: size)
        }
    }

    static func displayName(for choice: EditorFontChoice) -> String {
        switch choice {
        case .default:
            "SF Pro"
        case .systemMonospaced:
            "SF Mono"
        case .menlo:
            "Menlo"
        case .courier:
            "Courier"
        case .courierNew:
            "Courier New"
        case .newYork:
            "New York"
        case .georgia:
            "Georgia"
        }
    }
}

struct SettingsFontRow: View {
    let option: SettingsFontOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(option.displayName)
                    .font(option.previewFont)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .bold()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
