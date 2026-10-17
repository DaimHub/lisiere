import Foundation
import SwiftUI

struct AddressSuggestion: Identifiable, Equatable, Sendable {
    let url: URL
    let title: String
    let isBookmarked: Bool

    var id: URL { url }

    var displayTitle: String {
        if !title.isEmpty { return title }
        return url.host().map(Bookmark.trimmedHost) ?? url.absoluteString
    }
}

/// Pages from history and bookmarks that match what's typed in the address bar.
enum AddressSuggestions {
    static let limit = 6

    /// How well a page matches, best first: its address starts with the text, a word in its title does,
    /// or the address or title contains every word typed.
    private enum Match: Int, Comparable {
        case contains = 1
        case titleWord
        case addressPrefix

        static func < (lhs: Match, rhs: Match) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private struct Candidate: Sendable {
        let url: URL
        var title: String
        var visitCount = 0
        var lastVisit = Date.distantPast
        var isBookmarked = false
    }

    /// Immutable, reusable text preparation. Querying never rebuilds dictionaries or tokenizes every title.
    struct Index: Sendable {
        private struct Prepared: Sendable {
            let candidate: Candidate
            let address: String
            let absoluteAddress: String
            let title: String
            let titleWords: [Substring]
            let text: String
            let addressLength: Int

            init(_ candidate: Candidate) {
                self.candidate = candidate
                address = strippedAddress(candidate.url)
                absoluteAddress = candidate.url.absoluteString.lowercased()
                title = candidate.title.lowercased()
                titleWords = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                text = "\(address) \(title)"
                addressLength = address.count
            }

            func match(_ query: String, words: [Substring]) -> Match? {
                if address.hasPrefix(query) || absoluteAddress.hasPrefix(query) { return .addressPrefix }
                if title.hasPrefix(query) || titleWords.contains(where: { $0.hasPrefix(query) }) { return .titleWord }
                return words.allSatisfy { text.contains($0) } ? .contains : nil
            }
        }

        private struct Ranked {
            let page: Prepared
            let match: Match
            let weight: Double

            func precedes(_ other: Ranked) -> Bool {
                if match != other.match { return match > other.match }
                if weight != other.weight { return weight > other.weight }
                if page.addressLength != other.page.addressLength { return page.addressLength < other.page.addressLength }
                return page.candidate.url.absoluteString < other.page.candidate.url.absoluteString
            }
        }

        private let candidates: [Prepared]

        init(pages: [HistoryPage], bookmarks: [Bookmark]) {
            var candidates: [URL: Candidate] = [:]
            for page in pages where ["http", "https"].contains(page.url.scheme?.lowercased() ?? "") {
                candidates[page.url] = Candidate(url: page.url, title: page.title, visitCount: page.visitCount,
                                               lastVisit: page.lastVisit)
            }
            for bookmark in bookmarks {
                var candidate = candidates[bookmark.url] ?? Candidate(url: bookmark.url, title: bookmark.displayTitle)
                candidate.isBookmarked = true
                if let title = bookmark.visibleTitle { candidate.title = title }
                candidates[bookmark.url] = candidate
            }
            self.candidates = candidates.values.map(Prepared.init)
        }

        func rank(_ query: String, now: Date = .now, limit: Int = AddressSuggestions.limit) -> [AddressSuggestion] {
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !query.isEmpty, limit > 0 else { return [] }
            let words = query.split(whereSeparator: \.isWhitespace)
            var best: [Ranked] = []
            for page in candidates {
                guard let match = page.match(query, words: words) else { continue }
                let candidate = page.candidate
                let ranked = Ranked(page: page, match: match,
                    weight: frecency(visitCount: candidate.visitCount, lastVisit: candidate.lastVisit, now: now)
                        + (candidate.isBookmarked ? 2 : 0))
                if best.count == limit, let last = best.last, !ranked.precedes(last) { continue }
                let index = best.firstIndex { ranked.precedes($0) } ?? best.endIndex
                best.insert(ranked, at: index)
                if best.count > limit { best.removeLast() }
            }
            return best.map {
                AddressSuggestion(url: $0.page.candidate.url, title: $0.page.candidate.title,
                                  isBookmarked: $0.page.candidate.isBookmarked)
            }
        }
    }

    /// Compatibility entry point for one-shot callers; the address field reuses an Index across keystrokes.
    static func rank(_ query: String, pages: [HistoryPage], bookmarks: [Bookmark], now: Date = .now,
                     limit: Int = limit) -> [AddressSuggestion] {
        Index(pages: pages, bookmarks: bookmarks).rank(query, now: now, limit: limit)
    }

    /// Visits count for less as they age.
    static func frecency(visitCount: Int, lastVisit: Date, now: Date) -> Double {
        let days = now.timeIntervalSince(lastVisit) / (24 * 60 * 60)
        let recency = switch days {
        case ..<1: 1.0
        case ..<7: 0.7
        case ..<30: 0.4
        case ..<90: 0.2
        default: 0.1
        }
        return Double(visitCount) * recency
    }

    /// The address without its scheme, `www.`, or a trailing slash, as it's typed: "github.com/athasdev".
    static func strippedAddress(_ url: URL) -> String {
        var address = url.absoluteString.lowercased()
        for prefix in ["https://", "http://"] where address.hasPrefix(prefix) {
            address.removeFirst(prefix.count)
        }
        if address.hasPrefix("www.") { address.removeFirst(4) }
        if address.hasSuffix("/") { address.removeLast() }
        return address
    }

    /// The text to complete the address bar to, keeping what was typed: the top suggestion's site while the text
    /// has no path, otherwise its full address. `nil` when the suggestion doesn't start with the text.
    static func inlineCompletion(of text: String, with suggestion: AddressSuggestion?) -> String? {
        guard let suggestion, !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        let address = strippedAddress(suggestion.url)
        let site = String(address.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
        let typed = text.lowercased()
        let target = typed.contains("/") ? address : site
        let candidates = typed.hasPrefix("www.") ? ["www." + target] : [target]
        guard let completion = candidates.first(where: { $0.hasPrefix(typed) }),
              completion.count > text.count else { return nil }
        return text + completion.dropFirst(text.count)
    }
}

/// One index per address field. Both preparation and matching execute away from the UI actor.
actor AddressSuggestionSearch {
    private var revision: Int?
    private var bookmarks: [Bookmark] = []
    private var index: AddressSuggestions.Index?

    func prepare(visits: [HistoryVisit], revision: Int, bookmarks: [Bookmark]) {
        guard self.revision != revision || self.bookmarks != bookmarks || index == nil else { return }
        var pages: [URL: HistoryPage] = [:]
        for visit in visits {
            let page = pages[visit.url]
            pages[visit.url] = HistoryPage(url: visit.url, title: visit.title.isEmpty ? page?.title ?? "" : visit.title,
                                          visitCount: (page?.visitCount ?? 0) + 1, lastVisit: visit.date)
        }
        index = AddressSuggestions.Index(pages: Array(pages.values), bookmarks: bookmarks)
        self.revision = revision
        self.bookmarks = bookmarks
    }

    func rank(_ query: String, visits: [HistoryVisit], revision: Int, bookmarks: [Bookmark]) -> [AddressSuggestion] {
        guard !Task.isCancelled else { return [] }
        prepare(visits: visits, revision: revision, bookmarks: bookmarks)
        guard !Task.isCancelled else { return [] }
        return index?.rank(query) ?? []
    }
}

/// The suggestions shown under the address bar while typing.
struct AddressSuggestionList: View {
    let suggestions: [AddressSuggestion]
    let selectedIndex: Int?
    let choose: (AddressSuggestion) -> Void
    @State private var hoveredID: URL?

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                row(suggestion, isSelected: index == selectedIndex)
            }
        }
        .padding(5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }

    private func row(_ suggestion: AddressSuggestion, isSelected: Bool) -> some View {
        HStack(spacing: 9) {
            SiteIcon(url: suggestion.url, size: 16)
            Text(suggestion.displayTitle)
                .lineLimit(1)
                .layoutPriority(1)
            Text(AddressSuggestions.strippedAddress(suggestion.url))
                .lineLimit(1)
                .foregroundStyle(isSelected ? AnyShapeStyle(Color(nsColor: .alternateSelectedControlTextColor))
                                            : AnyShapeStyle(.secondary))
            Spacer(minLength: 0)
            if suggestion.isBookmarked {
                Image(browserIcon: .bookmarkSelected, size: 10)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color(nsColor: .alternateSelectedControlTextColor))
                                                : AnyShapeStyle(.secondary))
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(isSelected ? AnyShapeStyle(Color(nsColor: .alternateSelectedControlTextColor))
                                    : AnyShapeStyle(.primary))
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(Color(nsColor: .selectedContentBackgroundColor))
                      : AnyShapeStyle(Color.primary.opacity(hoveredID == suggestion.id ? 0.07 : 0)))
        }
        .contentShape(Rectangle())
        .onHover { hoveredID = $0 ? suggestion.id : (hoveredID == suggestion.id ? nil : hoveredID) }
        // Chosen on mouse down, before the address bar loses focus and closes the list.
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in choose(suggestion) })
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { choose(suggestion) }
    }
}
