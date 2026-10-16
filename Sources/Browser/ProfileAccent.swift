import AppKit
import SwiftUI

/// An opaque sRGB accent, stored as six hex digits independently of the selected preset.
struct AccentColor: Equatable {
    private let rgb: UInt32

    init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard [3, 6].contains(digits.count),
              digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
        else { return nil }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard let value = UInt32(digits, radix: 16) else { return nil }
        rgb = value
    }

    init?(color: NSColor) {
        guard let color = color.usingColorSpace(.sRGB) else { return nil }
        func byte(_ component: CGFloat) -> UInt32 {
            UInt32((min(1, max(0, component)) * 255).rounded())
        }
        rgb = (byte(color.redComponent) << 16) | (byte(color.greenComponent) << 8) | byte(color.blueComponent)
    }

    var hex: String { String(format: "%06X", rgb) }
    private var components: [Double] {
        [Double((rgb >> 16) & 255), Double((rgb >> 8) & 255), Double(rgb & 255)].map { $0 / 255 }
    }
    var color: Color { Color(.sRGB, red: components[0], green: components[1], blue: components[2], opacity: 1) }

    static let defaultCustom = AccentColor(hex: "617D8A")!
}

enum ProfileAccent: String, CaseIterable, Codable, Identifiable {
    case sage, blue, violet, rose, amber, graphite, custom

    var id: Self { self }
    static var presets: [Self] { allCases.filter { $0 != .custom } }

    var title: String {
        switch self {
        case .sage: "Sage"
        case .blue: "Ocean"
        case .violet: "Violet"
        case .rose: "Rose"
        case .amber: "Amber"
        case .graphite: "Graphite"
        case .custom: "Custom"
        }
    }

    func resolved(custom: AccentColor) -> AccentColor {
        switch self {
        case .sage: AccentColor(hex: "617D8A")!
        case .blue: AccentColor(hex: "3D7AC2")!
        case .violet: AccentColor(hex: "946BC2")!
        case .rose: AccentColor(hex: "B8597A")!
        case .amber: AccentColor(hex: "B07830")!
        case .graphite: AccentColor(hex: "757A85")!
        case .custom: custom
        }
    }
}

/// Shapes retain their actual color; macOS menu template images inherit the menu's tint instead.
struct ProfileAccentPicker: View {
    @Binding var selection: ProfileAccent
    @Binding var customHex: String

    private var custom: AccentColor { AccentColor(hex: customHex) ?? .defaultCustom }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accent color").font(.subheadline.weight(.medium))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(ProfileAccent.presets) { option in
                    choice(option)
                }
            }
            choice(.custom)
            if selection == .custom {
                HStack(spacing: 12) {
                    Text("Custom color")
                    ProfileColorWell(hex: $customHex)
                        .frame(width: 60, height: 24)
                    Spacer(minLength: 0)
                    Text("#").foregroundStyle(.secondary)
                    TextField("RRGGBB", text: $customHex)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 84)
                        .accessibilityLabel("Hex color")
                        .onSubmit { if let color = AccentColor(hex: customHex) { customHex = color.hex } }
                }
                if AccentColor(hex: customHex) == nil {
                    Text("Enter 3 or 6 hex digits.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func choice(_ option: ProfileAccent) -> some View {
        Button { selection = option } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(option.resolved(custom: custom).color)
                    .overlay { Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 0.5) }
                    .frame(width: 14, height: 14)
                Text(option.title).lineLimit(1)
                Spacer(minLength: 0)
                Image(browserIcon: .checkmark, size: 10)
                    .opacity(selection == option ? 1 : 0)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .frame(height: 32)
            .background(.primary.opacity(selection == option ? 0.08 : 0.025),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.primary.opacity(selection == option ? 0.6 : 0.12), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityValue(selection == option ? "Selected" : "Not selected")
        .accessibilityAddTraits(selection == option ? .isSelected : [])
    }
}

/// The expanded native well exposes both quick swatches and the full macOS color panel.
private struct ProfileColorWell: NSViewRepresentable {
    @Binding var hex: String

    func makeCoordinator() -> Coordinator { Coordinator(hex: $hex) }

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell(frame: .zero)
        well.colorWellStyle = .expanded
        well.supportsAlpha = false
        well.target = context.coordinator
        well.action = #selector(Coordinator.changed(_:))
        well.setAccessibilityLabel("Custom color")
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        context.coordinator.hex = $hex
        well.color = NSColor((AccentColor(hex: hex) ?? .defaultCustom).color)
    }

    static func dismantleNSView(_ well: NSColorWell, coordinator: Coordinator) {
        if well.isActive {
            well.deactivate()
            NSColorPanel.shared.close()
        }
    }

    final class Coordinator: NSObject {
        var hex: Binding<String>
        init(hex: Binding<String>) { self.hex = hex }
        @objc func changed(_ sender: NSColorWell) {
            if let color = AccentColor(color: sender.color) { hex.wrappedValue = color.hex }
        }
    }
}
