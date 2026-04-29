import SwiftUI

struct PaletteColorPicker: View {
    let title: String
    @Binding var selection: Color
    @Environment(\.dismiss) private var dismiss

    @State private var hue: Double
    @State private var saturation: Double
    @State private var brightness: Double
    @State private var selectedRow: Int?
    @State private var selectedColumn: Int?
    @State private var hexText: String

    private static let swatches: [[Color]] = [
        [
            Color(red: 0.20, green: 0.47, blue: 1.00),
            Color(red: 0.63, green: 0.13, blue: 0.94),
            Color(red: 1.00, green: 0.07, blue: 0.54),
            Color(red: 1.00, green: 0.18, blue: 0.18),
            Color(red: 1.00, green: 0.38, blue: 0.16),
            Color(red: 1.00, green: 0.58, blue: 0.08)
        ],
        [
            Color(red: 1.00, green: 0.82, blue: 0.08),
            Color(red: 0.20, green: 0.78, blue: 0.35),
            Color(red: 0.49, green: 0.90, blue: 0.13),
            Color(red: 0.00, green: 0.88, blue: 0.62),
            Color(red: 0.37, green: 0.30, blue: 0.84),
            Color(red: 0.67, green: 0.49, blue: 0.29)
        ],
        [
            Color(white: 0.70),
            Color(red: 0.40, green: 0.33, blue: 0.27),
            Color(red: 0.40, green: 0.78, blue: 1.00),
            Color(red: 0.00, green: 0.82, blue: 0.88),
            Color(white: 1.0),
            Color(white: 0.0)
        ]
    ]

    private static let allSwatches = swatches.flatMap { $0 }
    private static let flexibleGridColumns = PaletteColorPickerLayout.gridColumns(kind: .flexible)
    private static let fixedGridColumns = PaletteColorPickerLayout.gridColumns(kind: .fixed)

    init(title: String, selection: Binding<Color>) {
        self.title = title
        _selection = selection
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        UIColor(selection.wrappedValue).getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        _hue = State(initialValue: h)
        _saturation = State(initialValue: s)
        _brightness = State(initialValue: b)
        _hexText = State(initialValue: Self.hexString(from: UIColor(selection.wrappedValue)))
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selection)
                    .frame(width: 54, height: 34)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color(uiColor: UIColor(selection).darkerShade()), lineWidth: 2)
                    }

                Spacer()

                Text(title)
                    .font(.headline)

                Spacer()

                HexColorField(
                    text: $hexText,
                    isValid: Self.color(fromHexString: hexText) != nil
                )
                .onSubmit(applyHexText)
                .onChange(of: hexText) {
                    applyHexText()
                }
            }

            ViewThatFits(in: .horizontal) {
                swatchGrid(columns: Self.fixedGridColumns)
                    .frame(width: PaletteColorPickerLayout.fixedGridWidth)

                swatchGrid(columns: Self.flexibleGridColumns)
            }

            BrightnessTrack(
                hue: hue,
                saturation: saturation,
                brightness: $brightness
            )
            .onChange(of: brightness) { _, newBrightness in
                updateSelection(Color(hue: hue, saturation: saturation, brightness: newBrightness))
            }
        }
        .padding()
    }

    private func swatchGrid(columns: [GridItem]) -> some View {
        LazyVGrid(columns: columns, spacing: PaletteColorPickerLayout.swatchSpacing) {
            ForEach(Self.allSwatches.indices, id: \.self) { index in
                let row = index / PaletteColorPickerLayout.columnCount
                let column = index % PaletteColorPickerLayout.columnCount
                SwatchCircle(
                    color: Self.allSwatches[index],
                    isSelected: selectedRow == row && selectedColumn == column
                ) {
                    selectSwatch(row: row, column: column)
                }
            }
        }
    }

    private func selectSwatch(row: Int, column: Int) {
        let color = Self.swatches[row][column]
        syncHSB(from: color)
        selectedRow = row
        selectedColumn = column
        updateSelection(Color(hue: hue, saturation: saturation, brightness: brightness))
    }

    private func syncHSB(from color: Color) {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        UIColor(color).getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        hue = h
        saturation = s
        brightness = b
    }

    private func applyHexText() {
        guard let color = Self.color(fromHexString: hexText) else {
            return
        }

        selectedRow = nil
        selectedColumn = nil
        syncHSB(from: color)
        updateSelection(color, syncHexText: false)
    }

    private func updateSelection(_ color: Color, syncHexText: Bool = true) {
        selection = color
        if syncHexText {
            hexText = Self.hexString(from: UIColor(color))
        }
    }

    private static func color(fromHexString rawValue: String) -> Color? {
        var cleaned = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }

        guard cleaned.count == 6,
              cleaned.allSatisfy(\.isHexDigit),
              let value = UInt32(cleaned, radix: 16) else {
            return nil
        }

        return Color(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }

    private static func hexString(from color: UIColor) -> String {
        let resolvedColor = color.resolvedColor(with: .current)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#000000"
        }

        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
}

enum PaletteColorPickerLayout {
    enum GridKind {
        case fixed
        case flexible
    }

    static let columnCount = 6
    static let fixedSwatchSize: CGFloat = 56
    static let swatchSpacing: CGFloat = 12
    static let fixedGridWidth = CGFloat(columnCount) * fixedSwatchSize
        + CGFloat(columnCount - 1) * swatchSpacing

    static func gridColumns(kind: GridKind) -> [GridItem] {
        let size: GridItem.Size = switch kind {
        case .fixed:
            .fixed(fixedSwatchSize)
        case .flexible:
            .flexible()
        }

        return Array(
            repeating: GridItem(size, spacing: swatchSpacing),
            count: columnCount
        )
    }
}

private struct HexColorField: View {
    @Binding var text: String
    let isValid: Bool

    var body: some View {
        TextField("#RRGGBB", text: $text)
            .font(.system(.callout, design: .monospaced).weight(.semibold))
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .multilineTextAlignment(.center)
            .frame(width: 96)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay {
                Capsule()
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .accessibilityLabel("Hex colour")
            .accessibilityHint("Enter a six digit hexadecimal colour value.")
    }

    private var borderColor: Color {
        isValid ? Color.secondary.opacity(0.22) : Color.red.opacity(0.65)
    }
}

private struct SwatchCircle: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Circle()
                        .strokeBorder(Color(uiColor: UIColor(color).darkerShade()), lineWidth: 2.5)
                }
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(.white, lineWidth: 3)
                            .padding(3)
                    }
                }
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

private struct BrightnessTrack: View {
    let hue: Double
    let saturation: Double
    @Binding var brightness: Double

    private let thumbSize: CGFloat = 44
    private let trackHeight: CGFloat = 22

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = geometry.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackGradient)
                    .frame(height: trackHeight)

                Circle()
                    .fill(Color(hue: hue, saturation: saturation, brightness: brightness))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: thumbOffset(in: trackWidth))
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(max(value.location.x / trackWidth, 0), 1)
                        brightness = 1.0 - fraction
                    }
            )
        }
        .frame(height: thumbSize)
    }

    private var trackGradient: LinearGradient {
        LinearGradient(
            colors: (0...10).map { step in
                Color(
                    hue: hue,
                    saturation: saturation,
                    brightness: 1.0 - Double(step) / 10.0
                )
            },
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func thumbOffset(in trackWidth: CGFloat) -> CGFloat {
        (1.0 - brightness) * (trackWidth - thumbSize)
    }
}
