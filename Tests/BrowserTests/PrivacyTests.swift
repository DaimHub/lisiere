import WebKit
import XCTest
@testable import Browser

@MainActor
final class PrivacyTests: XCTestCase {
    func testPrivateWindowsRememberNothing() throws {
        let regularDownloads = DownloadManager()
        let browser = BrowserModel.makePrivate(downloads: regularDownloads)

        XCTAssertTrue(browser.isPrivate)
        XCTAssertNil(browser.history)
        XCTAssertFalse(browser.websiteDataStore.isPersistent)
        XCTAssertFalse(browser.sitePermissions === SitePermissions.shared)
        XCTAssertFalse(browser.zoomLevels === ZoomStore.shared)
        XCTAssertFalse(browser.downloads === regularDownloads)
        XCTAssertTrue(browser.downloads.items.isEmpty)
        XCTAssertNil(browser.passwords)
        XCTAssertEqual(browser.appearance.selection, .dark)
        XCTAssertFalse(BrowserModel().isPrivate)
    }

    func testNonPersistentModelsRejectInheritedProfileState() async {
        let site = "private.example"
        let history = HistoryStore(file: nil)
        let permissions = SitePermissions()
        permissions.setDecision(true, for: .camera, on: site)
        let zoom = ZoomStore(defaults: nil)
        zoom.setLevel(1.5, for: site)
        let appearance = AppearanceStore(defaults: nil, appliesToApplication: false)
        appearance.selection = .light
        let blocker = ContentBlocker()
        await blocker.setBlocking(false, on: site)
        let downloads = DownloadManager()
        let browser = BrowserModel(downloads: downloads, sitePermissions: permissions, history: history,
                                   zoomLevels: zoom, websiteDataStore: .nonPersistent(), contentBlocker: blocker,
                                   appearance: appearance)

        XCTAssertNil(browser.history)
        XCTAssertNil(browser.sitePermissions.decision(for: [.camera], on: site))
        XCTAssertEqual(browser.zoomLevels.level(for: site), 1)
        XCTAssertFalse(browser.downloads === downloads)
        XCTAssertFalse(browser.appearance === appearance)
        XCTAssertEqual(browser.appearance.selection, .dark)
        await browser.contentBlocker.waitUntilLoaded()
        XCTAssertTrue(browser.contentBlocker.isBlocking(on: site))
        XCTAssertTrue(browser.contentBlocker.exceptions.isEmpty)
        browser.sitePermissions.setDecision(false, for: .camera, on: site)
        browser.zoomLevels.setLevel(2, for: site)
        XCTAssertEqual(permissions.decision(for: [.camera], on: site), true)
        XCTAssertEqual(zoom.level(for: site), 1.5)
        XCTAssertEqual(appearance.selection, .light)
        XCTAssertFalse(blocker.isBlocking(on: site))
    }

    func testPrivateTabsShareTheirWindowsDataStoreOnly() throws {
        let first = BrowserModel.makePrivate(downloads: DownloadManager())
        let second = BrowserModel.makePrivate(downloads: DownloadManager())
        first.addTab()

        let stores = first.tabs.compactMap { $0.webView?.configuration.websiteDataStore }
        XCTAssertEqual(stores.count, 2)
        XCTAssertTrue(stores.allSatisfy { $0 === first.websiteDataStore })
        XCTAssertFalse(first.websiteDataStore === second.websiteDataStore)
        XCTAssertFalse(first.websiteDataStore === WKWebsiteDataStore.default())
    }

    func testCookiesNeverCrossRegularAndPrivateWindowBoundaries() async throws {
        let identifier = UUID()
        addTeardownBlock { @MainActor in
            // WebKit may release the network process asynchronously after the views close.
            for attempt in 0..<20 {
                do {
                    try await WKWebsiteDataStore.remove(forIdentifier: identifier)
                    return
                } catch {
                    if attempt == 19 { throw error }
                    try await Task.sleep(for: .milliseconds(100))
                }
            }
        }
        let regular = BrowserModel(websiteDataStore: WKWebsiteDataStore(forIdentifier: identifier),
                                   appearance: AppearanceStore(defaults: nil, appliesToApplication: false))
        let first = BrowserModel.makePrivate()
        let second = BrowserModel.makePrivate()
        let freshRecords = await first.websiteDataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        XCTAssertTrue(freshRecords.isEmpty, "A fresh private window has no cached resources or saved website data.")
        let host = "privacy-\(UUID().uuidString.lowercased()).example"
        func cookie(_ name: String) throws -> HTTPCookie {
            try XCTUnwrap(HTTPCookie(properties: [.domain: host, .path: "/", .name: name, .value: "present"]))
        }
        let regularCookie = try cookie("regular")
        let privateCookie = try cookie("private")
        let regularCookies = regular.websiteDataStore.httpCookieStore
        let firstCookies = first.websiteDataStore.httpCookieStore
        let secondCookies = second.websiteDataStore.httpCookieStore
        first.addTab()
        let firstTabCookies = try XCTUnwrap(first.activeTab?.webView?.configuration.websiteDataStore.httpCookieStore)
        await regularCookies.setCookie(regularCookie)
        await firstCookies.setCookie(privateCookie)

        let regularNames = await regularCookies.allCookies().filter { $0.domain == host }.map(\.name)
        let firstNames = await firstTabCookies.allCookies().filter { $0.domain == host }.map(\.name)
        let secondNames = await secondCookies.allCookies().filter { $0.domain == host }.map(\.name)
        XCTAssertEqual(regularNames, ["regular"])
        XCTAssertEqual(firstNames, ["private"], "Tabs in the same private window share only that window's session.")
        XCTAssertTrue(secondNames.isEmpty, "A second private window starts without the first window's cookies.")
        await regularCookies.delete(regularCookie)
        regular.releaseClosedWindow()
        first.releaseClosedWindow()
        second.releaseClosedWindow()
    }

    func testPrivatePopUpsAndRestoredTabsStayPrivate() throws {
        let browser = BrowserModel.makePrivate(downloads: DownloadManager())
        let opener = try XCTUnwrap(browser.activeTab)
        let configuration = try XCTUnwrap(opener.webView?.configuration)

        let popUp = browser.openChildTab(of: opener, configuration: configuration, select: false)
        XCTAssertTrue(popUp.webView?.configuration.websiteDataStore === browser.websiteDataStore)
        XCTAssertEqual(popUp.webView?.appearance?.name, .darkAqua)

        browser.restoreSession(WindowSession(tabs: [
            TabSession(url: URL(string: "data:text/html,<title>A</title>")!, title: "A", interactionState: nil),
            TabSession(url: URL(string: "data:text/html,<title>B</title>")!, title: "B", interactionState: nil),
        ], selectedIndex: 0))
        browser.selectTab(at: 1)

        XCTAssertTrue(browser.activeTab?.webView?.configuration.websiteDataStore === browser.websiteDataStore)
        XCTAssertEqual(browser.activeTab?.webView?.appearance?.name, .darkAqua)
        browser.duplicateTab(try XCTUnwrap(browser.activeTabID))
        XCTAssertTrue(browser.activeTab?.webView?.configuration.websiteDataStore === browser.websiteDataStore)
        browser.closeActiveTab()
        browser.reopenClosedTab()
        XCTAssertTrue(browser.activeTab?.webView?.configuration.websiteDataStore === browser.websiteDataStore)
        XCTAssertEqual(browser.activeTab?.webView?.appearance?.name, .darkAqua)
    }

    func testPrivateZoomLevelsAreForgotten() throws {
        let browser = BrowserModel.makePrivate(downloads: DownloadManager())
        browser.zoomLevels.setLevel(1.5, for: "private.example")

        XCTAssertEqual(browser.zoomLevels.level(for: "private.example"), 1.5)
        XCTAssertEqual(ZoomStore.shared.level(for: "private.example"), 1)
        XCTAssertEqual(BrowserModel.makePrivate(downloads: DownloadManager()).zoomLevels.level(for: "private.example"), 1)
    }

    func testClearingSiteDataLeavesTheCacheAndTheOtherWayAround() {
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()

        let siteData = ClearDataOptions.siteData.websiteDataTypes(from: allTypes)
        XCTAssertTrue(siteData.contains(WKWebsiteDataTypeCookies))
        XCTAssertTrue(siteData.contains(WKWebsiteDataTypeLocalStorage))
        XCTAssertTrue(siteData.isDisjoint(with: ClearDataOptions.cacheTypes))

        let cache = ClearDataOptions.cache.websiteDataTypes(from: allTypes)
        XCTAssertTrue(cache.contains(WKWebsiteDataTypeDiskCache))
        XCTAssertFalse(cache.contains(WKWebsiteDataTypeCookies))

        XCTAssertEqual(ClearDataOptions.all.websiteDataTypes(from: allTypes), allTypes)
        XCTAssertTrue(ClearDataOptions([.history, .favicons]).websiteDataTypes(from: allTypes).isEmpty)
    }

    func testClearingAllHistoryForgetsClosedWindows() async {
        let history = HistoryStore(file: nil)
        let session = SessionStore(file: nil)
        let closing = BrowserModel()
        closing.restoreSession(WindowSession(tabs: [
            TabSession(url: URL(string: "https://swift.org")!, title: "Swift", interactionState: nil),
        ], selectedIndex: 0))
        _ = session.attach(closing)
        session.detach(closing)
        history.recordVisit(to: URL(string: "https://swift.org")!, title: "Swift")
        let data = BrowsingData(history: history, session: session, dataStore: .nonPersistent())

        await data.clear(.history, range: .lastHour)
        XCTAssertTrue(history.visits.isEmpty)
        XCTAssertFalse(session.reopenableWindows.isEmpty)

        await data.clear(.history, range: .all)
        XCTAssertTrue(session.reopenableWindows.isEmpty)
    }
}
