import AppKit
import SwiftUI

/// A restrained wash over the existing window material, shared by both tab layouts.
/// The original choice leaves the material exactly as it was.
enum BrowserInterfaceColor: String, CaseIterable, Identifiable {
    case original, sage, ocean, sand, clay, lavender, custom

    static let storageKey = "browserInterfaceColor"
    static let customStorageKey = "browserCustomInterfaceColor"
    static let defaultCustomHex = "57816A"
    var id: Self { self }

    var title: String {
        switch self {
        case .original: "Original"
        case .sage: "Sage"
        case .ocean: "Ocean"
        case .sand: "Sand"
        case .clay: "Clay"
        case .lavender: "Lavender"
        case .custom: "Custom"
        }
    }

    private var hex: String {
        switch self {
        case .original: "909090"
        case .sage: "57816A"
        case .ocean: "507E9D"
        case .sand: "B29864"
        case .clay: "B47460"
        case .lavender: "8B79AA"
        case .custom: Self.defaultCustomHex
        }
    }

    func seed(customColor: NSColor) -> NSColor {
        self == .custom ? customColor : Self.color(hex: hex)!
    }

    /// Keep hue, but constrain saturation and brightness so arbitrary colors stay quiet and readable.
    func tint(for scheme: ColorScheme, customColor: NSColor) -> NSColor? {
        guard self != .original else { return nil }
        let color = seed(customColor: customColor).usingColorSpace(.sRGB) ?? .gray
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: nil, alpha: nil)
        let dark = scheme == .dark
        return NSColor(calibratedHue: hue,
                       saturation: min(saturation * (dark ? 0.8 : 0.5), dark ? 0.36 : 0.24),
                       brightness: dark ? 0.20 : 0.96, alpha: dark ? 0.84 : 0.72)
    }

    static func color(hex: String) -> NSColor? {
        guard hex.count == 6, hex.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let value = UInt32(hex, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    static func hex(for color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let values = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        guard values.allSatisfy(\.isFinite) else { return nil }
        return values.map { String(format: "%02X", Int((min(1, max(0, $0)) * 255).rounded())) }.joined()
    }
}

struct InterfaceColorSettings: View {
    @Bindable var appearance: AppearanceStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var customHex = ""
    @State private var invalidHex = false
    @FocusState private var editingHex: Bool

    var body: some View {
        Section {
            HStack(spacing: 4) {
                ForEach(BrowserInterfaceColor.allCases) { choice in
                    Button {
                        appearance.interfaceColor = choice
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(Color(nsColor: choice.tint(for: colorScheme,
                                    customColor: appearance.customInterfaceColor) ?? .windowBackgroundColor))
                                .background(Color(nsColor: .windowBackgroundColor), in: Circle())
                                .frame(width: 30, height: 30)
                                .overlay { Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1) }
                                .overlay {
                                    if appearance.interfaceColor == choice {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(4)
                                            .background(.black.opacity(0.65), in: Circle())
                                    }
                                }
                            Text(choice.title)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .background(appearance.interfaceColor == choice ? Color.primary.opacity(0.06) : .clear,
                                in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("\(choice.title) interface color")
                    .accessibilityValue(appearance.interfaceColor == choice ? "Selected" : "Not selected")
                    .accessibilityAddTraits(appearance.interfaceColor == choice ? [.isSelected] : [])
                    .help(choice == .original ? "Restore the original glass appearance" : "Use \(choice.title.lowercased()) for the sidebar and toolbar")
                }
            }
            if appearance.interfaceColor == .custom {
                LabeledContent("Custom color") {
                    TextField("#57816A", text: $customHex)
                        .labelsHidden()
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)
                        .focused($editingHex)
                        .onSubmit(applyHex)
                        .accessibilityLabel("Custom color hex value")
                        .help("Enter six hexadecimal digits, then press Return.")
                    ColorPicker("Custom color", selection: Binding(
                        get: { Color(nsColor: appearance.customInterfaceColor) },
                        set: { appearance.customInterfaceColor = NSColor($0) }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }
                if invalidHex {
                    Text("Use six hex digits, such as #57816A.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Interface Color")
        } footer: {
            Text("A soft tint for the sidebar and toolbar, adapted to light and dark themes. Private windows keep their violet tint.")
        }
        .onAppear(perform: syncHex)
        .onChange(of: appearance.customInterfaceColor) { _, _ in syncHex() }
        .onChange(of: editingHex) { wasEditing, isEditing in
            if wasEditing && !isEditing { applyHex() }
        }
    }

    private func syncHex() {
        customHex = "#" + (BrowserInterfaceColor.hex(for: appearance.customInterfaceColor) ?? BrowserInterfaceColor.defaultCustomHex)
        invalidHex = false
    }

    private func applyHex() {
        let value = customHex.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard let color = BrowserInterfaceColor.color(hex: hex) else {
            invalidHex = true
            return
        }
        appearance.customInterfaceColor = color
        syncHex()
    }
}
