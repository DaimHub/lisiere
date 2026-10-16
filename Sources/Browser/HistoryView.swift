import AppKit
import SwiftUI

/// Every page visited, grouped by day, shown from History ▸ Show All History.
struct HistoryView: View {
    let history: HistoryStore
    let open: (URL, _ inNewTab: Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var clearRange: HistoryClearRange?
    @State private var hoveredEntryID: String?

    var body: some View {
        let days = history.days(matching: query)

        VStack(spacing: 0) {
            header
            Divider()
            if days.isEmpty {
                ContentUnavailableView {
                    Label(query.isEmpty ? "No History" : "No Results",
                          browserIcon: query.isEmpty ? .history : .search, size: 40)
                } description: {
                    Text(query.isEmpty ? "Pages you visit show up here." : "No pages match “\(query)”.")
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(days) { day in
                        Section(Self.title(for: day.date)) {
                            ForEach(day.entries) { entry in
                                row(entry)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 560, idealWidth: 680, minHeight: 420, idealHeight: 560)
        .confirmationDialog(clearRange.map(Self.clearTitle) ?? "", isPresented: Binding(
            get: { clearRange != nil },
            set: { if !$0 { clearRange = nil } }
        ), presenting: clearRange) { range in
            Button("Clear History", role: .destructive) { history.clear(range) }
        } message: { _ in
            Text("This can’t be undone.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("History")
                .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 6) {
                Image(browserIcon: .search, size: 11)
                    .foregroundStyle(.secondary)
                TextField("Search History", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Menu("Clear History", browserIcon: .trash) {
                ForEach(HistoryClearRange.allCases) { range in
                    Button(range.title, browserIcon: .history) { clearRange = range }
                }
            }
            .fixedSize()
            .browserMenu {
                HistoryClearRange.allCases.map { range in
                    .init(title: range.title, icon: .history) { clearRange = range }
                }
            }
            .disabled(history.visits.isEmpty)

            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    private func row(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 10) {
            SiteIcon(url: entry.url, size: 16)
            Text(entry.displayTitle)
                .lineLimit(1)
                .layoutPriority(1)
            Text(AddressSuggestions.strippedAddress(entry.url))
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if hoveredEntryID == entry.id {
                Button { delete(entry) } label: {
                    Image(browserIcon: .close)
                }
                .buttonStyle(ChromeIconButtonStyle(size: 20))
                .help("Delete")
                .accessibilityLabel("Delete history entry")
            }
            Text(entry.date, format: .dateTime.hour().minute())
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.system(size: 13))
        .frame(height: 24)
        .contentShape(Rectangle())
        .onHover { hoveredEntryID = $0 ? entry.id : (hoveredEntryID == entry.id ? nil : hoveredEntryID) }
        .onTapGesture {
            open(entry.url, NSEvent.modifierFlags.contains(.command))
        }
        .browserContextMenu {
            [.init(title: "Open", icon: .open) { open(entry.url, false) },
             .init(title: "Open in New Tab", icon: .add) { open(entry.url, true) },
             .separator,
             .init(title: "Copy Address", icon: .copy) {
                 NSPasteboard.general.clearContents()
                 NSPasteboard.general.setString(entry.url.absoluteString, forType: .string)
             },
             .separator,
             .init(title: "Delete", icon: .trash) { delete(entry) }]
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open(entry.url, false) }
    }

    private func delete(_ entry: HistoryEntry) {
        history.removeVisits(to: entry.url, onDayOf: entry.date)
    }

    private static func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    private static func clearTitle(_ range: HistoryClearRange) -> String {
        switch range {
        case .lastHour: "Clear history from the last hour?"
        case .today: "Clear today’s history?"
        case .todayAndYesterday: "Clear history from today and yesterday?"
        case .all: "Clear all history?"
        }
    }
}
