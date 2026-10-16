import SwiftUI

/// The full badge is the menu label, so its padding participates in hit testing.
struct ToolbarProfileMenu<Content: View>: View {
    let name: String
    let icon: BrowserIcon
    let compact: Bool
    let accent: Color
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        Menu(content: content) {
            HStack(spacing: 5) {
                Image(browserIcon: icon)
                if !compact {
                    Text(name).lineLimit(1).truncationMode(.tail)
                    Image(browserIcon: .chevronDown, size: 9)
                }
            }
            .padding(.horizontal, compact ? 0 : 10)
            .frame(width: compact ? 34 : 132, height: BrowserChrome.navigationControlHeight)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Profile: \(name)")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(ProfileBadgeButtonStyle(accent: accent, hovering: hovering))
        .onHover { hovering = $0 }
        .help("Profile: \(name)")
        .accessibilityLabel("Profile: \(name)")
    }
}

private struct ProfileBadgeButtonStyle: ButtonStyle {
    let accent: Color
    let hovering: Bool
    func makeBody(configuration: Configuration) -> some View {
        Badge(configuration: configuration, accent: accent, hovering: hovering)
    }

    private struct Badge: View {
        let configuration: ButtonStyle.Configuration
        let accent: Color
        let hovering: Bool
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            configuration.label
                .foregroundStyle(accent)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(configuration.isPressed ? 0.30 : hovering ? 0.23 : colorScheme == .dark ? 0.14 : 0.09))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(accent.opacity(hovering || configuration.isPressed ? 0.40 : 0), lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
    }
}
