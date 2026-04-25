import SwiftUI
import UniformTypeIdentifiers

struct ThemeExchangeDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    let themes: [CustomTheme]

    init(theme: CustomTheme) {
        themes = [theme]
    }

    init(themes: [CustomTheme]) {
        self.themes = themes
    }

    init(data: Data) throws {
        themes = try Self.decodeThemes(from: data)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try self.init(data: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        .init(regularFileWithContents: try exportedData())
    }

    func exportedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]

        if themes.count == 1, let theme = themes.first {
            return try encoder.encode(ThemeExchangeTheme(theme))
        }

        return try encoder.encode(themes.map(ThemeExchangeTheme.init))
    }

    private static func decodeThemes(from data: Data) throws -> [CustomTheme] {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ThemeExchangeError.invalidJSON
        }

        let decoder = JSONDecoder()

        if jsonObject is [Any] {
            return try decodeThemeArray(from: data, using: decoder)
        }

        guard let dictionary = jsonObject as? [String: Any] else {
            throw ThemeExchangeError.invalidFormat
        }

        if dictionary["themes"] != nil {
            return try decodeThemeBundle(from: data, using: decoder)
        }

        return try decodeSingleTheme(from: data, using: decoder)
    }

    private static func decodeSingleTheme(from data: Data, using decoder: JSONDecoder) throws -> [CustomTheme] {
        do {
            let theme = try decoder.decode(ThemeExchangeTheme.self, from: data)
            return [theme.makeCustomTheme()]
        } catch let error as ThemeSchemaVersionError {
            throw error
        } catch {
            throw ThemeExchangeError.invalidFormat
        }
    }

    private static func decodeThemeArray(from data: Data, using decoder: JSONDecoder) throws -> [CustomTheme] {
        do {
            let themes = try decoder.decode([ThemeExchangeTheme].self, from: data)
            guard themes.isEmpty == false else {
                throw ThemeExchangeError.invalidFormat
            }
            return themes.map { $0.makeCustomTheme() }
        } catch let error as ThemeSchemaVersionError {
            throw error
        } catch let error as DecodingError {
            throw ThemeExchangeError.partialBundleFailure(details: describePartialBundleFailure(error))
        } catch {
            throw ThemeExchangeError.invalidFormat
        }
    }

    private static func decodeThemeBundle(from data: Data, using decoder: JSONDecoder) throws -> [CustomTheme] {
        do {
            let bundle = try decoder.decode(ThemeExchangeBundle.self, from: data)
            guard bundle.themes.isEmpty == false else {
                throw ThemeExchangeError.invalidFormat
            }
            return bundle.themes.map { $0.makeCustomTheme() }
        } catch let error as ThemeSchemaVersionError {
            throw error
        } catch let error as DecodingError {
            throw ThemeExchangeError.partialBundleFailure(details: describePartialBundleFailure(error))
        } catch {
            throw ThemeExchangeError.invalidFormat
        }
    }

    private static func describePartialBundleFailure(_ error: DecodingError) -> String {
        switch error {
        case let .dataCorrupted(context):
            return partialBundleFailureMessage(
                codingPath: context.codingPath,
                description: context.debugDescription
            )
        case let .keyNotFound(key, context):
            return partialBundleFailureMessage(
                codingPath: context.codingPath + [key],
                description: "Missing required value."
            )
        case let .typeMismatch(_, context), let .valueNotFound(_, context):
            return partialBundleFailureMessage(
                codingPath: context.codingPath,
                description: context.debugDescription
            )
        @unknown default:
            return "One of the themes in this import file is invalid."
        }
    }

    private static func partialBundleFailureMessage(
        codingPath: [any CodingKey],
        description: String
    ) -> String {
        let path = codingPathDescription(for: codingPath)
        guard path.isEmpty == false else {
            return "One of the themes in this import file is invalid. \(description)"
        }

        return "One of the themes in this import file is invalid at \(path). \(description)"
    }

    private static func codingPathDescription(for codingPath: [any CodingKey]) -> String {
        var path = ""

        for key in codingPath {
            if let index = key.intValue {
                path += "[\(index)]"
                continue
            }

            let component = key.stringValue
            guard component.isEmpty == false else {
                continue
            }

            if path.isEmpty {
                path = component
            } else {
                path += ".\(component)"
            }
        }

        if path.hasPrefix("[") {
            return "themes\(path)"
        }

        return path
    }
}

private nonisolated struct ThemeExchangeBundle: Codable {
    let themes: [ThemeExchangeTheme]
}

private nonisolated struct ThemeExchangeTheme: Codable {
    let id: UUID
    let name: String
    let background: HexColor
    let text: HexColor
    let tint: HexColor
    let boldItalicMarker: HexColor
    let strikethrough: HexColor
    let inlineCode: HexColor
    let codeBackground: HexColor
    let horizontalRule: HexColor
    let checkboxUnchecked: HexColor
    let checkboxChecked: HexColor

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case name
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
    }

    init(_ theme: CustomTheme) {
        id = theme.id
        name = theme.name
        background = theme.background
        text = theme.text
        tint = theme.tint
        boldItalicMarker = theme.boldItalicMarker
        strikethrough = theme.strikethrough
        inlineCode = theme.inlineCode
        codeBackground = theme.codeBackground
        horizontalRule = theme.horizontalRule
        checkboxUnchecked = theme.checkboxUnchecked
        checkboxChecked = theme.checkboxChecked
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        try CustomTheme.validateSchemaVersion(schemaVersion)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        background = try Self.decodeExchangeHexColor(from: container, forKey: .background)
        text = try Self.decodeExchangeHexColor(from: container, forKey: .text)
        tint = try Self.decodeExchangeHexColor(from: container, forKey: .tint)
        boldItalicMarker = try Self.decodeExchangeHexColor(from: container, forKey: .boldItalicMarker)
        strikethrough = try Self.decodeOptionalExchangeHexColor(from: container, forKey: .strikethrough)
            ?? HexColor(text.uiColor.withAlphaComponent(0.62))
        inlineCode = try Self.decodeExchangeHexColor(from: container, forKey: .inlineCode)
        codeBackground = try Self.decodeExchangeHexColor(from: container, forKey: .codeBackground)
        horizontalRule = try Self.decodeExchangeHexColor(from: container, forKey: .horizontalRule)
        checkboxUnchecked = try Self.decodeExchangeHexColor(from: container, forKey: .checkboxUnchecked)
        checkboxChecked = try Self.decodeExchangeHexColor(from: container, forKey: .checkboxChecked)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(CustomTheme.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(background.hex, forKey: .background)
        try container.encode(text.hex, forKey: .text)
        try container.encode(tint.hex, forKey: .tint)
        try container.encode(boldItalicMarker.hex, forKey: .boldItalicMarker)
        try container.encode(strikethrough.hex, forKey: .strikethrough)
        try container.encode(inlineCode.hex, forKey: .inlineCode)
        try container.encode(codeBackground.hex, forKey: .codeBackground)
        try container.encode(horizontalRule.hex, forKey: .horizontalRule)
        try container.encode(checkboxUnchecked.hex, forKey: .checkboxUnchecked)
        try container.encode(checkboxChecked.hex, forKey: .checkboxChecked)
    }

    func makeCustomTheme() -> CustomTheme {
        CustomTheme(
            id: id,
            name: name,
            background: background,
            text: text,
            tint: tint,
            boldItalicMarker: boldItalicMarker,
            strikethrough: strikethrough,
            inlineCode: inlineCode,
            codeBackground: codeBackground,
            horizontalRule: horizontalRule,
            checkboxUnchecked: checkboxUnchecked,
            checkboxChecked: checkboxChecked
        )
    }

    private static func decodeExchangeHexColor(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> HexColor {
        let rawValue = try container.decode(String.self, forKey: key)
        return try HexColor(exchangeString: rawValue, codingPath: container.codingPath + [key])
    }

    private static func decodeOptionalExchangeHexColor(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> HexColor? {
        guard let rawValue = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }

        return try HexColor(exchangeString: rawValue, codingPath: container.codingPath + [key])
    }
}

private enum ThemeExchangeError: LocalizedError {
    case invalidJSON
    case invalidFormat
    case partialBundleFailure(details: String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "The selected file is not valid JSON."
        case .invalidFormat:
            return "The selected JSON file is not a valid Downward theme export."
        case let .partialBundleFailure(details):
            return details
        }
    }
}
