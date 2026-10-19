import AppKit
import SwiftUI

@MainActor
enum TabSearch {
    /// Search saved metadata only, so finding a suspended tab never loads its page.
    static func results(in tabs: [BrowserTab], query: String) -> [BrowserTab] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return tabs }
        return tabs.filter { tab in
            let address = tab.url?.absoluteString ?? ""
            let text = tab.title + "\n" + address + "\n" + (address.removingPercentEncoding ?? address)
            return terms.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}

struct TabSearchList: View {
    let tabs: [BrowserTab]
    let activeTabID: UUID?
    let select: (BrowserTab) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedID: UUID?

    private var results: [BrowserTab] { TabSearch.results(in: tabs, query: query) }

    var body: some View {
        let matches = results
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("All Tabs").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(query.isEmpty ? "\(tabs.count)" : "\(matches.count) of \(tabs.count)")
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    .accessibilityLabel("\(matches.count) matching tabs")
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            TabSearchField(text: $query, move: moveSelection, submit: openSelection, cancel: { dismiss() })
                .frame(height: 26)
                .padding(.horizontal, 12).padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if matches.isEmpty {
                            Text("No matching tabs")
                                .font(.system(size: 12.5)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 76)
                                .accessibilityIdentifier("tab-search-empty")
                        }
                        ForEach(matches) { tab in
                            TabSearchRow(tab: tab, isCurrent: tab.id == activeTabID,
                                         isHighlighted: tab.id == selectedID) { select(tab) }
                                .id(tab.id)
                        }
                    }
                    .padding(.horizontal, 6).padding(.bottom, 6)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: matches.isEmpty ? 88 : CGFloat(min(7, matches.count)) * 48 + 6)
                .onChange(of: selectedID, initial: true) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
        .frame(width: 360)
        .onAppear { selectedID = matches.first(where: { $0.id == activeTabID })?.id ?? matches.first?.id }
        .onChange(of: query) { _, _ in selectedID = results.first?.id }
        .onChange(of: matches.map(\.id)) { _, ids in
            if !ids.contains(where: { $0 == selectedID }) { selectedID = ids.first }
        }
        .onExitCommand { dismiss() }
    }

    private func moveSelection(_ direction: Int) {
        let matches = results
        guard !matches.isEmpty else { return }
        let index = matches.firstIndex { $0.id == selectedID } ?? (direction > 0 ? -1 : matches.count)
        selectedID = matches[min(max(index + direction, 0), matches.count - 1)].id
    }

    private func openSelection() {
        guard let tab = results.first(where: { $0.id == selectedID }) else { return }
        select(tab)
    }
}

private struct TabSearchRow: View {
    let tab: BrowserTab
    let isCurrent: Bool
    let isHighlighted: Bool
    let select: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                if let favicon = tab.favicon {
                    favicon.resizable().scaledToFit().frame(width: 16, height: 16)
                } else {
                    Image(browserIcon: tab.isNewTab ? .home : .globe, size: 16).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.title).font(.system(size: 12.5, weight: isCurrent ? .medium : .regular))
                        .lineLimit(1).truncationMode(.tail)
                    if let address = tab.url?.absoluteString {
                        Text(address.removingPercentEncoding ?? address)
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if tab.isPinned { Image(browserIcon: .pin, size: 11).foregroundStyle(.secondary) }
                if isCurrent { Image(browserIcon: .checkmark, size: 12).foregroundStyle(Color.accentColor) }
            }
            .padding(.horizontal, 8)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHighlighted ? Color.accentColor.opacity(0.14) : Color.primary.opacity(isHovered ? 0.06 : 0),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovered = $0 }
        .accessibilityLabel(tab.title)
        .accessibilityValue([tab.url?.absoluteString, tab.isPinned ? "Pinned" : nil,
                             isCurrent ? "Current tab" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
        .accessibilityIdentifier("tab-search-result-\(tab.id)")
    }
}

/// Use AppKit's search field so editing, the clear button and command handling stay native.
private struct TabSearchField: NSViewRepresentable {
    @Binding var text: String
    let move: (Int) -> Void
    let submit: () -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = FocusedSearchField()
        field.placeholderString = "Search tabs by title or address"
        field.setAccessibilityLabel("Search tabs")
        field.setAccessibilityIdentifier("tab-search-field")
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: TabSearchField
        init(_ parent: TabSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)): parent.move(1)
            case #selector(NSResponder.moveUp(_:)): parent.move(-1)
            case #selector(NSResponder.insertNewline(_:)): parent.submit()
            case #selector(NSResponder.cancelOperation(_:)): parent.cancel()
            default: return false
            }
            return true
        }
    }

    private final class FocusedSearchField: NSSearchField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }
    }
}
