import XCTest
@testable import Browser

@MainActor
final class TabSearchTests: XCTestCase {
    func testSearchCombinesTitleAndAddressIgnoringCaseAccentsAndExtraSpaces() {
        let ticket = BrowserTab(url: URL(string: "https://jira.example/browse/SYM-1499"),
                                title: "Décisions du projet", interactionState: nil)
        let unrelated = BrowserTab(url: URL(string: "https://drive.example/"),
                                   title: "Décisions du projet", interactionState: nil)
        XCTAssertEqual(TabSearch.results(in: [ticket, unrelated], query: "  decisions\n SYM-1499  ").map(\.id), [ticket.id])
        XCTAssertTrue(TabSearch.results(in: [ticket], query: "decisions SYM-1500").isEmpty)
    }

    func testSearchMatchesDecodedAndEncodedAddresses() {
        let tab = BrowserTab(url: URL(string: "https://example.test/R%C3%A9union%20projet"),
                             title: "Document", interactionState: nil)
        for query in ["reunion projet", "R%C3%A9union", "EXAMPLE.TEST"] {
            XCTAssertEqual(TabSearch.results(in: [tab], query: query).map(\.id), [tab.id])
        }
    }

    func testSearchRetainsPinnedAndGroupedSuspendedTabsWithoutLoadingThem() {
        let pinned = BrowserTab(url: URL(string: "https://mail.example"), title: "Mail", interactionState: nil)
        pinned.isPinned = true
        let grouped = BrowserTab(url: URL(string: "https://docs.example"), title: "Notes", interactionState: nil)
        grouped.groupID = UUID()
        let tabs = [pinned, grouped]
        XCTAssertEqual(TabSearch.results(in: tabs, query: "example").map(\.id), tabs.map(\.id))
        XCTAssertEqual(TabSearch.results(in: tabs, query: " \n ").map(\.id), tabs.map(\.id))
        XCTAssertTrue(tabs.allSatisfy { $0.webView == nil && $0.isSuspended })
        XCTAssertTrue(pinned.isPinned)
        XCTAssertNotNil(grouped.groupID)
    }

    func testSearchKeepsDuplicateTitlesAsSeparateSelectableTabsAndHandlesBlankPages() {
        let first = BrowserTab(url: URL(string: "https://example.test/one"), title: "Notes", interactionState: nil)
        let second = BrowserTab(url: URL(string: "https://example.test/two"), title: "Notes", interactionState: nil)
        let blank = BrowserTab(url: nil, title: "", interactionState: nil)
        XCTAssertEqual(TabSearch.results(in: [first, second, blank], query: "notes").map(\.id), [first.id, second.id])
        XCTAssertEqual(TabSearch.results(in: [first, second, blank], query: "new tab").map(\.id), [blank.id])
        XCTAssertTrue(TabSearch.results(in: [], query: "notes").isEmpty)
    }
}
