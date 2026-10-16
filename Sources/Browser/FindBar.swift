import SwiftUI

/// Searches the active tab's page, shown over its top edge.
struct FindBar: View {
    @Bindable var tab: BrowserTab
    let browser: BrowserModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Find on Page", text: $tab.findText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .frame(width: 180)
                .focused($isFocused)
                .onSubmit { browser.findNext() }
                .onExitCommand { browser.closeFindBar() }
                .onChange(of: tab.findText) { _, _ in tab.findAsYouType() }
                .accessibilityLabel("Find on page")

            if tab.findHasNoMatches {
                Text("Not Found")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }

            Group {
                Button { browser.findNext(backwards: true) } label: {
                    Image(systemName: "chevron.up")
                }
                .help("Previous Match (⇧⌘G)")
                Button { browser.findNext() } label: {
                    Image(systemName: "chevron.down")
                }
                .help("Next Match (⌘G)")
            }
            .disabled(tab.findText.isEmpty)

            Button { browser.closeFindBar() } label: {
                Image(systemName: "xmark")
            }
            .help("Done")
        }
        .buttonStyle(ChromeIconButtonStyle(size: 24))
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 34)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .animation(.easeOut(duration: 0.15), value: tab.findHasNoMatches)
        .onAppear { isFocused = true }
        .onChange(of: browser.findFocusRequest) { _, _ in isFocused = true }
    }
}
