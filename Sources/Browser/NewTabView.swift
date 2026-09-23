import SwiftUI

struct NewTabView: View {
    let focusAddress: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 30, weight: .ultraLight))
                    .foregroundStyle(.secondary)
                Text("New tab")
                    .font(.system(size: 26, weight: .medium))
                    .tracking(-0.6)
            }

            Button(action: focusAddress) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text("Search or enter an address")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("⌘L")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 14))
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Color.primary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Focus address and search")
            .frame(maxWidth: 440)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
