import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct EditorSettingsPage: View {
    let editorAppearanceStore: EditorAppearanceStore
    let themeStore: ThemeStore
    let importedFontManager: ImportedFontManager
    let backAction: () -> Void

    @State private var selectedCategory: SettingsFontCategory = .monospaced
    @State private var isImportingFont = false
    @State private var pendingImportTarget = ImportedFontImportTarget.general
    @State private var presentedImportedFontFamilyName: String?

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
                        isSelected: editorAppearanceStore.selectedImportedFontFamilyName == nil
                            && editorAppearanceStore.selectedFontChoice == option.choice
                    ) {
                        editorAppearanceStore.setFontChoice(option.choice)
                    }
                }
            } footer: {
                Text("Choose your favourite font.")
                    .settingsFooterStyle()
            }

            if ThemeEntitlementGate.canImportCustomFonts(hasUnlockedThemes: themeStore.hasUnlockedThemes) {
                Section {
                    Button {
                        pendingImportTarget = .general
                        isImportingFont = true
                    } label: {
                        ImportFontSettingsLabel(title: "Import Font")
                    }

                    ForEach(importedFontManager.families) { family in
                        ImportedFontFamilyRow(
                            family: family,
                            isSelected: editorAppearanceStore.selectedImportedFontFamilyName == family.familyName
                        ) {
                            editorAppearanceStore.setImportedFontFamily(family)
                        } detailAction: {
                            presentedImportedFontFamilyName = family.familyName
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                deleteImportedFontFamily(family)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Imported Fonts")
                } footer: {
                    Text("Import .ttf or .otf fonts to use in the editor. Swipe an imported family to delete it.")
                        .settingsFooterStyle()
                }
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
                        .disabled(
                            editorAppearanceStore.selectedImportedFontFamilyName != nil
                                || editorAppearanceStore.selectedFontChoice.isMonospaced == false
                                || editorAppearanceStore.effectiveLargerHeadingText
                        )
                        .accessibilityHint("Shows line numbers along the left edge of monospaced editor text.")

                    if editorAppearanceStore.effectiveShowLineNumbers {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 16) {
                                SettingsHomeLabel(
                                    title: "Line Number Opacity",
                                    systemName: "circle.lefthalf.filled",
                                    colors: [.blue]
                                )

                                Spacer(minLength: 12)

                                HStack(spacing: 4) {
                                    TextField(
                                        "85",
                                        value: lineNumberOpacityPercentBinding,
                                        format: .number.precision(.fractionLength(0))
                                    )
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .monospacedDigit()
                                    .frame(width: 48)

                                    Text("%")
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Slider(
                                value: lineNumberOpacityBinding,
                                in: 0...1,
                                step: 0.05
                            )
                            .accessibilityLabel("Line number opacity")
                            .accessibilityValue("\(Int((editorAppearanceStore.lineNumberOpacity * 100).rounded())) percent")
                        }
                    }
                } footer: {
                    Text(lineNumbersHelperText)
                        .settingsFooterStyle()
                }
            }

            Section {
                Toggle("Larger Heading Text", isOn: largerHeadingTextBinding)
                    .accessibilityHint("Shows markdown headings larger than the selected editor font size.")
            } footer: {
                Text(largerHeadingHelperText)
                    .settingsFooterStyle()
            }

            Section {
                Toggle("Reopen Last Document", isOn: reopenLastDocumentBinding)
                    .accessibilityHint("Opens the most recently edited document after restoring the workspace.")
            } footer: {
                Text("When disabled, Downward opens to the file browser after launch.")
                    .settingsFooterStyle()
            }
        }
        .navigationTitle("Editor")
        .fileImporter(
            isPresented: $isImportingFont,
            allowedContentTypes: ImportedFontImportType.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            Task {
                await ImportedFontSettingsImportHandler.handle(
                    result: result,
                    importedFontManager: importedFontManager,
                    editorAppearanceStore: editorAppearanceStore,
                    hasUnlockedThemes: themeStore.hasUnlockedThemes,
                    target: pendingImportTarget
                )
                pendingImportTarget = .general
            }
        }
        .sheet(isPresented: importedFontFamilyDetailBinding) {
            if let family = presentedImportedFontFamily {
                NavigationStack {
                    ImportedFontFamilyDetailView(
                        family: family,
                        importAction: { style in
                            pendingImportTarget = .familyStyle(
                                familyName: family.familyName,
                                style: style
                            )
                            presentedImportedFontFamilyName = nil
                            isImportingFont = true
                        }
                    )
                    .navigationTitle(family.displayName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                presentedImportedFontFamilyName = nil
                            }
                        }
                    }
                }
            }
        }
        .alert("Font Error", isPresented: importedFontErrorBinding) {
            Button("OK") { importedFontManager.lastError = nil }
        } message: {
            if let error = importedFontManager.lastError {
                Text(error)
            }
        }
        .onAppear {
            editorAppearanceStore.setImportedFontsUnlocked(themeStore.hasUnlockedThemes)
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

    private var lineNumberOpacityBinding: Binding<Double> {
        Binding(
            get: { editorAppearanceStore.lineNumberOpacity },
            set: { editorAppearanceStore.setLineNumberOpacity($0) }
        )
    }

    private var lineNumberOpacityPercentBinding: Binding<Double> {
        Binding(
            get: { (editorAppearanceStore.lineNumberOpacity * 100).rounded() },
            set: { editorAppearanceStore.setLineNumberOpacity($0 / 100) }
        )
    }

    private var largerHeadingTextBinding: Binding<Bool> {
        Binding(
            get: { editorAppearanceStore.largerHeadingText },
            set: { editorAppearanceStore.setLargerHeadingText($0) }
        )
    }

    private var reopenLastDocumentBinding: Binding<Bool> {
        Binding(
            get: { editorAppearanceStore.reopenLastDocumentOnLaunch },
            set: { editorAppearanceStore.setReopenLastDocumentOnLaunch($0) }
        )
    }

    private var importedFontErrorBinding: Binding<Bool> {
        Binding(
            get: { importedFontManager.lastError != nil },
            set: { isPresented in
                if isPresented == false {
                    importedFontManager.lastError = nil
                }
            }
        )
    }

    private var importedFontFamilyDetailBinding: Binding<Bool> {
        Binding(
            get: { presentedImportedFontFamily != nil },
            set: { isPresented in
                if isPresented == false {
                    presentedImportedFontFamilyName = nil
                }
            }
        )
    }

    private var presentedImportedFontFamily: ImportedFontFamily? {
        guard
            ThemeEntitlementGate.canImportCustomFonts(hasUnlockedThemes: themeStore.hasUnlockedThemes),
            let presentedImportedFontFamilyName
        else {
            return nil
        }

        return importedFontManager.family(named: presentedImportedFontFamilyName)
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

    private func deleteImportedFontFamily(_ family: ImportedFontFamily) {
        guard ThemeEntitlementGate.canImportCustomFonts(hasUnlockedThemes: themeStore.hasUnlockedThemes) else {
            return
        }

        guard importedFontManager.deleteFamily(named: family.familyName) else {
            return
        }

        editorAppearanceStore.clearImportedFontFamilyIfSelected(family.familyName)
    }

    private var lineNumbersHelperText: String {
        if editorAppearanceStore.selectedImportedFontFamilyName != nil {
            return "Line numbers are available with built-in monospaced fonts."
        }

        if editorAppearanceStore.effectiveLargerHeadingText {
            return "Line numbers are disabled while larger heading text is enabled."
        }

        return "Show line numbers along the left edge of the editor."
    }

    private var largerHeadingHelperText: String {
        if editorAppearanceStore.largerHeadingText {
            return "Headings render larger than the selected font size. Line numbers are disabled while this is enabled."
        }

        return "Render markdown headings larger than the selected editor font size."
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
                        .symbolGradient(.accentColor)
                        .bold()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct ImportedFontFamilyRow: View {
    let family: ImportedFontFamily
    let isSelected: Bool
    let action: () -> Void
    let detailAction: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(action: action) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(family.displayName)
                            .font(previewFont)

                        Text(family.styleSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark")
                            .symbolGradient(.accentColor)
                            .bold()
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button(action: detailAction) {
                Image(systemName: "list.bullet.rectangle")
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(family.displayName) styles")
        }
    }

    private var previewFont: Font {
        guard let postScriptName = family.baseRecord?.postScriptName else {
            return .body
        }

        return .custom(postScriptName, size: UIFont.preferredFont(forTextStyle: .body).pointSize)
    }
}

private struct ImportedFontFamilyDetailView: View {
    let family: ImportedFontFamily
    let importAction: (ImportedFontStyleRequest) -> Void

    var body: some View {
        Form {
            Section {
                ForEach(ImportedFontStyleRequest.allCases) { style in
                    ImportedFontStyleStatusRow(
                        style: style,
                        record: family.record(matching: style),
                        importAction: {
                            importAction(style)
                        }
                    )
                }
            } header: {
                Text("Styles")
            }
        }
    }
}

private struct ImportedFontStyleStatusRow: View {
    let style: ImportedFontStyleRequest
    let record: ImportedFontRecord?
    let importAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record == nil ? "circle" : "checkmark.circle.fill")
                .symbolGradient(record == nil ? .secondary : .green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(style.displayName)
                    .font(previewFont)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if record == nil {
                Button(action: importAction) {
                    ImportFontSettingsLabel(title: "Install")
                }
                    .buttonStyle(.borderless)
            }
        }
    }

    private var statusText: String {
        if let record {
            return "Installed as \(record.displayName)"
        }

        return "Not installed"
    }

    private var previewFont: Font {
        guard let record else {
            return .body
        }

        return .custom(record.postScriptName, size: UIFont.preferredFont(forTextStyle: .body).pointSize)
    }
}

private struct ImportFontSettingsLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.arrow.down")
                .symbolRenderingMode(.palette)
                .foregroundStyle(squareOutlineGradient, .green)
                .frame(width: 22)
                .accessibilityHidden(true)

            Text(title)
        }
    }

    private var squareOutlineGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(uiColor: .label),
                Color(uiColor: .label).opacity(0.7)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

enum ImportedFontImportTarget: Equatable {
    case general
    case familyStyle(familyName: String, style: ImportedFontStyleRequest)
}

enum ImportedFontSettingsImportHandler {
    @MainActor
    static func handle(
        result: Result<[URL], Error>,
        importedFontManager: ImportedFontManager,
        editorAppearanceStore: EditorAppearanceStore,
        hasUnlockedThemes: Bool,
        target: ImportedFontImportTarget = .general
    ) async {
        guard ThemeEntitlementGate.canImportCustomFonts(hasUnlockedThemes: hasUnlockedThemes) else {
            return
        }

        do {
            let urls = try result.get()
            let records = await importedFontManager.importFonts(from: urls)
            selectImportedFontIfNeeded(
                records: records,
                importedFontManager: importedFontManager,
                editorAppearanceStore: editorAppearanceStore,
                target: target
            )
        } catch {
            guard isUserCancelled(error) == false else {
                return
            }

            importedFontManager.lastError = error.localizedDescription
        }
    }

    @MainActor
    private static func selectImportedFontIfNeeded(
        records: [ImportedFontRecord],
        importedFontManager: ImportedFontManager,
        editorAppearanceStore: EditorAppearanceStore,
        target: ImportedFontImportTarget
    ) {
        switch target {
        case .general:
            if let familyName = records.first?.familyName,
               let family = importedFontManager.family(named: familyName) {
                editorAppearanceStore.setImportedFontFamily(family)
            }
        case let .familyStyle(familyName, style):
            guard let family = importedFontManager.family(named: familyName) else {
                importedFontManager.lastError = "Downward could not find that imported font family."
                return
            }

            if family.record(matching: style) != nil {
                editorAppearanceStore.setImportedFontFamily(family)
                return
            }

            if records.isEmpty == false {
                importedFontManager.lastError = "That file was imported, but it did not add \(style.displayName) to \(familyName)."
            }
        }
    }

    private static func isUserCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.userCancelled.rawValue
    }
}

private enum ImportedFontImportType {
    static var allowedContentTypes: [UTType] {
        var types: [UTType] = [.font]
        if let trueType = UTType(filenameExtension: "ttf") {
            types.append(trueType)
        }
        if let openType = UTType(filenameExtension: "otf") {
            types.append(openType)
        }
        return types
    }
}
