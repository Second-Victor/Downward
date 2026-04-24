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
    private static let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

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
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                ColorPicker("", selection: $selection, supportsOpacity: false)
                    .labelsHidden()

                Spacer()

                Text(title)
                    .font(.headline)

                Spacer()

                Button("Close", systemImage: "xmark.circle.fill") {
                    dismiss()
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Self.gridColumns, spacing: 12) {
                ForEach(Self.allSwatches.indices, id: \.self) { index in
                    let row = index / 6
                    let column = index % 6
                    SwatchCircle(
                        color: Self.allSwatches[index],
                        isSelected: selectedRow == row && selectedColumn == column
                    ) {
                        selectSwatch(row: row, column: column)
                    }
                }
            }

            BrightnessTrack(
                hue: hue,
                saturation: saturation,
                brightness: $brightness
            )
            .onChange(of: brightness) { _, newBrightness in
                selection = Color(hue: hue, saturation: saturation, brightness: newBrightness)
            }
        }
        .padding()
    }

    private func selectSwatch(row: Int, column: Int) {
        let color = Self.swatches[row][column]
        syncHSB(from: color)
        selectedRow = row
        selectedColumn = column
        selection = Color(hue: hue, saturation: saturation, brightness: brightness)
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

    private let thumbSize: CGFloat = 32
    private let trackHeight: CGFloat = 28

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
