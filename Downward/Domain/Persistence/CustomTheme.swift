import UIKit

nonisolated struct HexColor: Codable, Equatable, Hashable, Sendable {
    var hex: String

    private enum CodingKeys: String, CodingKey {
        case hex
    }

    var uiColor: UIColor {
        guard let rgba = Self.rgbaComponents(from: hex) else {
            return .black
        }

        if rgba.count == 4 {
            return UIColor(red: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
        }

        return UIColor(red: rgba[0], green: rgba[1], blue: rgba[2], alpha: 1)
    }

    init(_ color: UIColor) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let components = [
            Self.twoDigitHex(Int((r * 255).rounded())),
            Self.twoDigitHex(Int((g * 255).rounded())),
            Self.twoDigitHex(Int((b * 255).rounded()))
        ]
        if a < 1 {
            hex = "#" + (components + [Self.twoDigitHex(Int((a * 255).rounded()))]).joined()
        } else {
            hex = "#" + components.joined()
        }
    }

    init(hex: String) {
        self.hex = hex
    }

    init(exchangeString: String, codingPath: [any CodingKey]) throws {
        hex = try Self.normalizedHexString(from: exchangeString, codingPath: codingPath)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(String.self, forKey: .hex)
        hex = try Self.normalizedHexString(from: rawValue, codingPath: [CodingKeys.hex])
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hex, forKey: .hex)
    }

    private static func normalizedHexString(from rawValue: String, codingPath: [any CodingKey]) throws -> String {
        var cleaned = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }

        guard cleaned.count == 6 || cleaned.count == 8 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "Hex colours must contain 6 or 8 hexadecimal digits."
            ))
        }

        guard cleaned.allSatisfy(\.isHexDigit) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "Hex colours may only contain hexadecimal digits."
            ))
        }

        return "#\(cleaned.uppercased())"
    }

    private static func rgbaComponents(from rawValue: String) -> [CGFloat]? {
        var cleaned = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }

        guard cleaned.count == 6 || cleaned.count == 8,
              let rgb = UInt64(cleaned, radix: 16) else {
            return nil
        }

        if cleaned.count == 8 {
            return [
                CGFloat((rgb >> 24) & 0xFF) / 255,
                CGFloat((rgb >> 16) & 0xFF) / 255,
                CGFloat((rgb >> 8) & 0xFF) / 255,
                CGFloat(rgb & 0xFF) / 255
            ]
        }

        return [
            CGFloat((rgb >> 16) & 0xFF) / 255,
            CGFloat((rgb >> 8) & 0xFF) / 255,
            CGFloat(rgb & 0xFF) / 255
        ]
    }

    private static func twoDigitHex(_ value: Int) -> String {
        let clamped = min(max(value, 0), 255)
        let hex = String(clamped, radix: 16, uppercase: true)
        return hex.count == 1 ? "0\(hex)" : hex
    }
}

nonisolated struct CustomTheme: Codable, Identifiable, Equatable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    var id: UUID
    var name: String
    var background: HexColor
    var text: HexColor
    var tint: HexColor
    var boldItalicMarker: HexColor
    var inlineCode: HexColor
    var codeBackground: HexColor
    var horizontalRule: HexColor
    var checkboxUnchecked: HexColor
    var checkboxChecked: HexColor

    init(
        id: UUID,
        name: String,
        background: HexColor,
        text: HexColor,
        tint: HexColor,
        boldItalicMarker: HexColor,
        inlineCode: HexColor,
        codeBackground: HexColor,
        horizontalRule: HexColor,
        checkboxUnchecked: HexColor,
        checkboxChecked: HexColor
    ) {
        self.id = id
        self.name = name
        self.background = background
        self.text = text
        self.tint = tint
        self.boldItalicMarker = boldItalicMarker
        self.inlineCode = inlineCode
        self.codeBackground = codeBackground
        self.horizontalRule = horizontalRule
        self.checkboxUnchecked = checkboxUnchecked
        self.checkboxChecked = checkboxChecked
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case name
        case background
        case text
        case tint
        case boldItalicMarker
        case inlineCode
        case codeBackground
        case horizontalRule
        case checkboxUnchecked
        case checkboxChecked
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        let id = try container.decode(UUID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let background = try container.decode(HexColor.self, forKey: .background)
        let text = try container.decode(HexColor.self, forKey: .text)
        let tint = try container.decode(HexColor.self, forKey: .tint)
        let boldItalicMarker = try container.decodeIfPresent(HexColor.self, forKey: .boldItalicMarker) ?? text
        let inlineCode = try container.decode(HexColor.self, forKey: .inlineCode)
        let codeBackground = try container.decode(HexColor.self, forKey: .codeBackground)
        let horizontalRule = try container.decode(HexColor.self, forKey: .horizontalRule)
        let checkboxUnchecked = try container.decode(HexColor.self, forKey: .checkboxUnchecked)
        let checkboxChecked = try container.decode(HexColor.self, forKey: .checkboxChecked)

        self.init(
            id: id,
            name: name,
            background: background,
            text: text,
            tint: tint,
            boldItalicMarker: boldItalicMarker,
            inlineCode: inlineCode,
            codeBackground: codeBackground,
            horizontalRule: horizontalRule,
            checkboxUnchecked: checkboxUnchecked,
            checkboxChecked: checkboxChecked
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(background, forKey: .background)
        try container.encode(text, forKey: .text)
        try container.encode(tint, forKey: .tint)
        try container.encode(boldItalicMarker, forKey: .boldItalicMarker)
        try container.encode(inlineCode, forKey: .inlineCode)
        try container.encode(codeBackground, forKey: .codeBackground)
        try container.encode(horizontalRule, forKey: .horizontalRule)
        try container.encode(checkboxUnchecked, forKey: .checkboxUnchecked)
        try container.encode(checkboxChecked, forKey: .checkboxChecked)
    }
}
