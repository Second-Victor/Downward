import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ThemeEditorSettingsPage: View {
    let editorAppearanceStore: EditorAppearanceStore
    let themeStore: ThemeStore
    let editing: CustomTheme?
    let backAction: () -> Void

    @State private var name: String
    @State private var background: Color
    @State private var text: Color
    @State private var tint: Color
    @State private var boldItalicMarker: Color
    @State private var strikethrough: Color
    @State private var inlineCode: Color
    @State private var codeBackground: Color
    @State private var horizontalRule: Color
    @State private var checkboxUnchecked: Color
    @State private var checkboxChecked: Color
    @State private var editingColor: ThemeColorProperty?
    @State private var isSaving = false
    @State private var exportDocument: ThemeExchangeDocument?
    @State private var exportFilename = "Theme.json"

    init(
        editorAppearanceStore: EditorAppearanceStore,
        themeStore: ThemeStore,
        editing: CustomTheme? = nil,
        backAction: @escaping () -> Void
    ) {
        self.editorAppearanceStore = editorAppearanceStore
        self.themeStore = themeStore
        self.editing = editing
        self.backAction = backAction

        if let editing {
            _name = State(initialValue: editing.name)
            _background = State(initialValue: Color(uiColor: editing.background.uiColor))
            _text = State(initialValue: Color(uiColor: editing.text.uiColor))
            _tint = State(initialValue: Color(uiColor: editing.tint.uiColor))
            _boldItalicMarker = State(initialValue: Color(uiColor: editing.boldItalicMarker.uiColor))
            _strikethrough = State(initialValue: Color(uiColor: editing.strikethrough.uiColor))
            _inlineCode = State(initialValue: Color(uiColor: editing.inlineCode.uiColor))
            _codeBackground = State(initialValue: Color(uiColor: editing.codeBackground.uiColor))
            _horizontalRule = State(initialValue: Color(uiColor: editing.horizontalRule.uiColor))
            _checkboxUnchecked = State(initialValue: Color(uiColor: editing.checkboxUnchecked.uiColor))
            _checkboxChecked = State(initialValue: Color(uiColor: editing.checkboxChecked.uiColor))
        } else {
            let baseTheme = EditorTheme.adaptive
            _name = State(initialValue: "")
            _background = State(initialValue: Color(uiColor: baseTheme.background))
            _text = State(initialValue: Color(uiColor: baseTheme.text))
            _tint = State(initialValue: Color(uiColor: baseTheme.tint))
            _boldItalicMarker = State(initialValue: Color(uiColor: baseTheme.boldItalicMarker))
            _strikethrough = State(initialValue: Color(uiColor: baseTheme.strikethrough))
            _inlineCode = State(initialValue: Color(uiColor: baseTheme.inlineCode))
            _codeBackground = State(initialValue: Color(uiColor: baseTheme.codeBackground))
            _horizontalRule = State(initialValue: Color(uiColor: baseTheme.horizontalRule))
            _checkboxUnchecked = State(initialValue: Color(uiColor: baseTheme.checkboxUnchecked))
            _checkboxChecked = State(initialValue: Color(uiColor: baseTheme.checkboxChecked))
        }
    }

    var body: some View {
        List {
            Section("Name") {
                TextField("Theme Name", text: $name)
            }

            Section("Colours") {
                if hasLowContrast {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ThemeContrastWarning.title)
                                .font(.footnote.weight(.semibold))
                            Text(ThemeContrastWarning.message)
                                .font(.footnote)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }
                    .listRowBackground(Color.yellow.opacity(0.12))
                }

                ForEach(ThemeColorProperty.allCases) { property in
                    Button {
                        editingColor = property
                    } label: {
                        HStack {
                            Text(property.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            Circle()
                                .fill(colorValue(for: property))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle().strokeBorder(
                                        Color(uiColor: UIColor(colorValue(for: property)).darkerShade()),
                                        lineWidth: 2
                                    )
                                )
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentMargins(.top, ThemeEditorPreviewLayout.listTopContentMargin, for: .scrollContent)
        .overlay(alignment: .top) {
            SettingsMarkdownPreview(
                font: ThemeEditorPreviewLayout.previewFont,
                resolvedTheme: previewResolvedTheme,
                syntaxMode: editorAppearanceStore.markdownSyntaxMode
            )
            .padding(.horizontal, 16)
            .padding(.top, ThemeEditorPreviewLayout.topPadding)
            .padding(.bottom, ThemeEditorPreviewLayout.bottomPadding)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask {
                        Rectangle()
                            .padding(16)
                            .blur(radius: 16)
                    }
            }
            .allowsHitTesting(false)
        }
        .navigationTitle(editing == nil ? "New Theme" : "Edit Theme")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if editing != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ThemeEditorDraftExport.buttonTitle, systemImage: "square.and.arrow.up") {
                        exportTheme()
                    }
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    // Saves are explicit ThemeStore-owned mutations; `isSaving` prevents duplicate
                    // taps while the store serializes persistence.
                    Task {
                        await saveTheme()
                    }
                }
                .disabled(isSaveDisabled)
            }
        }
        .sheet(item: $editingColor) { property in
            PaletteColorPicker(
                title: property.title,
                selection: colorBinding(for: property)
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .fileExporter(
            isPresented: exportPresentationBinding,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            if case let .failure(error) = result, isUserCancelled(error) == false {
                themeStore.lastError = "Could not export the theme JSON: \(error.localizedDescription)"
            }
            exportDocument = nil
        }
        .alert("Theme Error", isPresented: themeErrorBinding) {
            Button("OK") { themeStore.lastError = nil }
        } message: {
            if let error = themeStore.lastError {
                Text(error)
            }
        }
    }

    private var isSaveDisabled: Bool {
        isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var textBackgroundContrastRatio: Double {
        UIColor(text).wcagContrastRatio(against: UIColor(background))
    }

    private var hasLowContrast: Bool {
        textBackgroundContrastRatio < ThemeContrastWarning.minimumReadableRatio
    }

    private var previewResolvedTheme: ResolvedEditorTheme {
        EditorTheme(from: makeTheme(id: editing?.id ?? UUID(), name: name))
            .resolvedEditorTheme
            .applyingColorFormattedText(editorAppearanceStore.colorFormattedText)
    }

    private var exportPresentationBinding: Binding<Bool> {
        Binding(
            get: { exportDocument != nil },
            set: { isPresented in
                if isPresented == false {
                    exportDocument = nil
                }
            }
        )
    }

    private var themeErrorBinding: Binding<Bool> {
        Binding(
            get: { themeStore.lastError != nil },
            set: { isPresented in
                if isPresented == false {
                    themeStore.lastError = nil
                }
            }
        )
    }

    private func colorValue(for property: ThemeColorProperty) -> Color {
        switch property {
        case .background: background
        case .text: text
        case .tint: tint
        case .boldItalicMarker: boldItalicMarker
        case .strikethrough: strikethrough
        case .inlineCode: inlineCode
        case .codeBackground: codeBackground
        case .horizontalRule: horizontalRule
        case .checkboxUnchecked: checkboxUnchecked
        case .checkboxChecked: checkboxChecked
        }
    }

    private func colorBinding(for property: ThemeColorProperty) -> Binding<Color> {
        switch property {
        case .background: $background
        case .text: $text
        case .tint: $tint
        case .boldItalicMarker: $boldItalicMarker
        case .strikethrough: $strikethrough
        case .inlineCode: $inlineCode
        case .codeBackground: $codeBackground
        case .horizontalRule: $horizontalRule
        case .checkboxUnchecked: $checkboxUnchecked
        case .checkboxChecked: $checkboxChecked
        }
    }

    private func saveTheme() async {
        guard isSaving == false else { return }
        isSaving = true
        defer { isSaving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let theme = makeTheme(id: editing?.id ?? UUID(), name: trimmedName)

        if editing != nil {
            guard await themeStore.update(theme) else { return }
        } else {
            guard await themeStore.add(theme) else { return }
            editorAppearanceStore.setSelectedThemeID(theme.id.uuidString)
        }

        backAction()
    }

    private func makeTheme(id: UUID, name: String? = nil) -> CustomTheme {
        CustomTheme(
            id: id,
            name: name ?? self.name.trimmingCharacters(in: .whitespacesAndNewlines),
            background: HexColor(UIColor(background)),
            text: HexColor(UIColor(text)),
            tint: HexColor(UIColor(tint)),
            boldItalicMarker: HexColor(UIColor(boldItalicMarker)),
            strikethrough: HexColor(UIColor(strikethrough)),
            inlineCode: HexColor(UIColor(inlineCode)),
            codeBackground: HexColor(UIColor(codeBackground)),
            horizontalRule: HexColor(UIColor(horizontalRule)),
            checkboxUnchecked: HexColor(UIColor(checkboxUnchecked)),
            checkboxChecked: HexColor(UIColor(checkboxChecked))
        )
    }

    private func exportTheme() {
        let theme = makeTheme(id: editing?.id ?? UUID())
        exportDocument = ThemeEditorDraftExport.document(for: theme)
        exportFilename = ThemeEditorDraftExport.filename(for: theme.name)
    }

    private func isUserCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.userCancelled.rawValue
    }
}

enum ThemeContrastWarning {
    static let minimumReadableRatio = 4.5
    static let title = "This may be hard to read"
    static let message = "The text and background colours are very similar. Try making one lighter or darker. You can still save this theme."
}

enum ThemeEditorDraftExport {
    static let buttonTitle = "Export Draft"

    static func document(for theme: CustomTheme) -> ThemeExchangeDocument {
        ThemeExchangeDocument(theme: theme)
    }

    static func filename(for themeName: String) -> String {
        let trimmed = themeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = trimmed
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .replacing(" ", with: "-")
        let filename = cleaned.isEmpty ? "Theme" : cleaned
        return "\(filename).json"
    }
}

enum ThemeEditorPreviewLayout {
    static let previewFontSize: CGFloat = 15
    static let previewHeight: CGFloat = 270
    static let topPadding: CGFloat = 8
    static let bottomPadding: CGFloat = 8
    static let listTopContentMargin = previewHeight + topPadding + bottomPadding

    static var previewFont: UIFont {
        UIFont.monospacedSystemFont(ofSize: previewFontSize, weight: .regular)
    }
}

enum ThemeColorProperty: String, Identifiable, CaseIterable {
    case background
    case text
    case tint
    case boldItalicMarker
    case strikethrough
    case inlineCode
    case codeBackground
    case horizontalRule
    case checkboxUnchecked
    case checkboxChecked

    var id: Self { self }

    var title: String {
        switch self {
        case .background: "Background"
        case .text: "Text"
        case .tint: "Accent"
        case .boldItalicMarker: "Bold / Italic Markers"
        case .strikethrough: "Strikethrough Text"
        case .inlineCode: "Code"
        case .codeBackground: "Code Background"
        case .horizontalRule: "Horizontal Rule"
        case .checkboxUnchecked: "Unchecked Task"
        case .checkboxChecked: "Checked Task"
        }
    }
}

struct SettingsMarkdownPreview: View {
    static let defaultSampleMarkdown = """
    # Heading 
    **Bold** & *Italic*
    ~~Strike Through~~

    `Inline Code`

    > Block Quote

    
    ---
    - [ ] To do
    - [x] Done
    """

    let font: UIFont
    let resolvedTheme: ResolvedEditorTheme
    let syntaxMode: MarkdownSyntaxMode
    var sampleMarkdown = Self.defaultSampleMarkdown

    var body: some View {
        SettingsMarkdownPreviewTextView(
            text: sampleMarkdown,
            font: font,
            resolvedTheme: resolvedTheme,
            syntaxMode: syntaxMode
        )
        .frame(height: ThemeEditorPreviewLayout.previewHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .padding(.top, 4)
    }
}

private struct SettingsMarkdownPreviewTextView: UIViewRepresentable {
    let text: String
    let font: UIFont
    let resolvedTheme: ResolvedEditorTheme
    let syntaxMode: MarkdownSyntaxMode

    private let renderer = MarkdownStyledTextRenderer()

    func makeUIView(context: Context) -> UITextView {
        let textStorage = NSTextStorage()
        let layoutManager = MarkdownCodeBackgroundLayoutManager()
        layoutManager.resolvedTheme = resolvedTheme
        let textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = UITextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.adjustsFontForContentSizeCategory = false
        textView.textContainerInset = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        textView.setContentHuggingPriority(.defaultLow, for: .vertical)
        applyPreview(to: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        applyPreview(to: textView)
    }

    private func applyPreview(to textView: UITextView) {
        textView.backgroundColor = resolvedTheme.editorBackground
        textView.isOpaque = true
        textView.tintColor = resolvedTheme.accent

        if let layoutManager = textView.layoutManager as? MarkdownCodeBackgroundLayoutManager {
            layoutManager.resolvedTheme = resolvedTheme
        }

        let rendered = renderer.render(
            configuration: .init(
                text: text,
                baseFont: font,
                resolvedTheme: resolvedTheme,
                syntaxMode: syntaxMode,
                revealedRange: nil
            )
        )

        if textView.attributedText?.isEqual(to: rendered) != true {
            textView.attributedText = rendered
        }
    }
}
