import XCTest
@testable import Browser

final class SuggestionParityTests: XCTestCase {
    func testPreparedIndexPreservesEveryRankingRuleAndTieBreak() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let titles = ["Swift Blog", "Énergie été", "Cafe\u{301} notes", "中文说明", "", "GitHub: design", "a—b test", "İstanbul Straße"]
        let pages = (0..<1800).map { i in
            HistoryPage(url: URL(string: "https://\(i % 3 == 0 ? "www." : "")site\(i % 41).example/blog/\(i)")!,
                        title: titles[i % titles.count], visitCount: i % 13 + 1,
                        lastVisit: now.addingTimeInterval(-Double(i % 110) * 86400))
        } + [HistoryPage(url: URL(string: "file:///private.txt")!, title: "Swift", visitCount: 100, lastVisit: now)]
        let bookmarks = stride(from: 0, to: 1800, by: 19).map {
            Bookmark(title: $0 % 2 == 0 ? "Bookmark override" : "", url: pages[$0].url)
        } + [Bookmark(title: "Unique bookmark", url: URL(string: "https://unique.example")!)]
        let index = AddressSuggestions.Index(pages: pages, bookmarks: bookmarks)
        for query in ["s", "www", "https://", "swift", "blog swift", "é", "café", "cafe\u{301}", "中文", "a—b", "İ", "straße", "override", "unique", "missing", "  ", "\nSWIFT \t"] {
            for limit in [1, 6, 31] {
                for date in [now, now.addingTimeInterval(8 * 86400)] {
                    XCTAssertEqual(index.rank(query, now: date, limit: limit),
                        LegacyAddressSuggestions.rank(query, pages: pages, bookmarks: bookmarks, now: date, limit: limit),
                        "Query \(query), limit \(limit)")
                }
            }
        }
    }

    func testSearchInvalidatesForTitlesRemovalsAndBookmarks() async {
        let search = AddressSuggestionSearch()
        let url = URL(string: "https://example.test")!
        var visits = [HistoryVisit(url: url, title: "First title", date: .now)]
        let first = await search.rank("first", visits: visits, revision: 1, bookmarks: [])
        XCTAssertEqual(first.first?.title, "First title")
        visits[0].title = "Second title"
        let renamed = await search.rank("second", visits: visits, revision: 2, bookmarks: [])
        XCTAssertEqual(renamed.first?.title, "Second title")
        let marked = await search.rank("favorite", visits: visits, revision: 2,
                                       bookmarks: [Bookmark(title: "Favorite", url: url)])
        XCTAssertEqual(marked.first?.isBookmarked, true)
        let removed = await search.rank("second", visits: [], revision: 3, bookmarks: [])
        XCTAssertTrue(removed.isEmpty)
    }
}

private enum LegacyAddressSuggestions {
    static let limit = 6

    /// How well a page matches, best first: its address starts with the text, a word in its title does,
    /// or the address or title contains every word typed.
    private enum Match: Int, Comparable {
        case contains = 1
        case titleWord
        case addressPrefix

        static func < (lhs: Match, rhs: Match) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private struct Candidate {
        let url: URL
        var title: String
        var visitCount = 0
        var lastVisit = Date.distantPast
        var isBookmarked = false
    }

    /// Ranks matching pages by how well they match, then by how often and how recently they were visited.
    /// A bookmark counts like a few visits.
    static func rank(_ query: String, pages: [HistoryPage], bookmarks: [Bookmark], now: Date = .now,
                     limit: Int = limit) -> [AddressSuggestion] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }

        var candidates: [URL: Candidate] = [:]
        for page in pages where ["http", "https"].contains(page.url.scheme?.lowercased() ?? "") {
            candidates[page.url] = Candidate(url: page.url, title: page.title, visitCount: page.visitCount,
                                             lastVisit: page.lastVisit)
        }
        for bookmark in bookmarks {
            var candidate = candidates[bookmark.url] ?? Candidate(url: bookmark.url, title: bookmark.title)
            candidate.isBookmarked = true
            if !bookmark.title.isEmpty { candidate.title = bookmark.title }
            candidates[bookmark.url] = candidate
        }

        let ranked = candidates.values.compactMap { candidate -> (Candidate, Match, Double, Int)? in
            let address = strippedAddress(candidate.url)
            guard let match = match(query, address: address, url: candidate.url, title: candidate.title)
            else { return nil }
            let weight = frecency(visitCount: candidate.visitCount, lastVisit: candidate.lastVisit, now: now)
                + (candidate.isBookmarked ? 2 : 0)
            return (candidate, match, weight, address.count)
        }
        .sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            if a.2 != b.2 { return a.2 > b.2 }
            if a.3 != b.3 { return a.3 < b.3 }
            return a.0.url.absoluteString < b.0.url.absoluteString
        }

        return ranked.prefix(limit).map {
            AddressSuggestion(url: $0.0.url, title: $0.0.title, isBookmarked: $0.0.isBookmarked)
        }
    }

    private static func match(_ query: String, address: String, url: URL, title: String) -> Match? {
        let title = title.lowercased()
        if address.hasPrefix(query) || url.absoluteString.lowercased().hasPrefix(query) { return .addressPrefix }
        if title.hasPrefix(query)
            || title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(query) }) {
            return .titleWord
        }
        let text = "\(address) \(title)"
        let words = query.split(whereSeparator: \.isWhitespace)
        return words.allSatisfy { text.contains($0) } ? .contains : nil
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

