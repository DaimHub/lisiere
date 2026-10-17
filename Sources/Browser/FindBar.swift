import SwiftUI

/// Searches the active tab's page, shown over its top edge.
struct FindBar: View {
    @Bindable var tab: BrowserTab
    let browser: BrowserModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(browserIcon: .search, size: 11)
                .foregroundStyle(.secondary)
            TextField("Find on Page", text: $tab.findText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .frame(minWidth: 30, idealWidth: 180, maxWidth: 180)
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
                    Image(browserIcon: .chevronUp)
                }
                .help("Previous Match (⇧⌘G)")
                .accessibilityLabel("Previous match")
                Button { browser.findNext() } label: {
                    Image(browserIcon: .chevronDown)
                }
                .help("Next Match (⌘G)")
                .accessibilityLabel("Next match")
            }
            .disabled(tab.findText.isEmpty)

            Button { browser.closeFindBar() } label: {
                Image(browserIcon: .close)
            }
            .help("Done")
            .accessibilityLabel("Close find bar")
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
