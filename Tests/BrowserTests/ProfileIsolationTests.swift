import WebKit
import XCTest
@testable import Browser

@MainActor
final class ProfileIsolationTests: XCTestCase {
    private var server: Process?
    private var ids: [UUID] = []
    private var browsers: [BrowserModel] = []

    override func tearDown() async throws {
        defer { server?.terminate(); server = nil }
        for browser in browsers { await ProfileStore.clearWebsiteData(in: browser.websiteDataStore) }
        autoreleasepool {
            browsers.forEach { $0.releaseClosedWindow() }
            browsers = []
        }
        // XCTest's outer autorelease pool can retain the empty store/network session until the host exits.
        // Check the cleanup that is meaningful here: no site records survive. Actual registry/store deletion
        // is covered separately by ProfileStoreTests and the Release workflow.
        for id in ids {
            let store = autoreleasepool { WKWebsiteDataStore(forIdentifier: id) }
            let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
            XCTAssertTrue(records.isEmpty, "Fixture website data survived cleanup")
        }
    }

    private func startServer() throws -> URL {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Fixtures/profile_site.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [fixture.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        server = process
        var bytes = Data()
        while let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty, byte != Data([10]) {
            bytes.append(byte)
        }
        let port = try XCTUnwrap(String(data: bytes, encoding: .utf8).flatMap(Int.init))
        return URL(string: "http://127.0.0.1:\(port)/")!
    }

    private func makeBrowser(id: UUID? = nil) -> BrowserModel {
        let id = id ?? UUID()
        if !ids.contains(id) { ids.append(id) }
        let browser = autoreleasepool {
            BrowserModel(websiteDataStore: WKWebsiteDataStore(forIdentifier: id), profileID: id)
        }
        browsers.append(browser)
        return browser
    }

    private func load(_ url: URL, in browser: BrowserModel) async throws -> WKWebView {
        autoreleasepool { browser.open(url) }
        let tab = try XCTUnwrap(browser.activeTab)
        try await waitUntil(timeout: .seconds(20)) { tab.pageTitle == "Profile isolation" && !tab.isLoading }
        return try XCTUnwrap(tab.webView)
    }

    private func run(_ script: String, in webView: WKWebView) async throws -> String {
        // Return a Sendable JSON string across the Swift continuation.
        try await withCheckedThrowingContinuation { continuation in
            autoreleasepool {
                webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                    continuation.resume(with: result.map { $0 as? String ?? "null" })
                }
            }
        }
    }

    private func read(_ webView: WKWebView) async throws -> [String: Any] {
        let value = try await run("return JSON.stringify(await readMarker())", in: webView)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any])
    }

    private func write(_ marker: String, in webView: WKWebView) async throws {
        let encoded = String(data: try JSONEncoder().encode(marker), encoding: .utf8)!
        _ = try await run("await writeMarker(\(encoded)); return JSON.stringify(true)", in: webView)
    }

    private func assertMarker(_ marker: String, in result: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result["cookie"] as? String, "profileMarker=\(marker)", file: file, line: line)
        for key in ["localStorage", "indexedDB", "cache"] {
            XCTAssertEqual(result[key] as? String, marker, "\(key) crossed profiles", file: file, line: line)
        }
    }

    private func assertEmpty(_ result: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result["cookie"] as? String, "", file: file, line: line)
        for key in ["localStorage", "indexedDB", "cache"] {
            XCTAssertTrue(result[key] is NSNull, "\(key) crossed profiles", file: file, line: line)
        }
        XCTAssertEqual((result["workers"] as? [String])?.count, 0, file: file, line: line)
    }

    func testSameOriginStorageAndHTTPCacheStaySeparateAndSurviveViewRecreation() async throws {
        try await exercisePersistentStores()
    }

    private func exercisePersistentStores() async throws {
        let url = try startServer()
        let a = makeBrowser()
        let b = makeBrowser()
        var first: WKWebView? = try await load(url, in: a)
        let second = try await load(url, in: b)
        assertEmpty(try await read(second))
        try await write("alpha", in: XCTUnwrap(first))
        let alpha = try await read(XCTUnwrap(first))
        assertMarker("alpha", in: alpha)
        XCTAssertTrue((alpha["workers"] as? [String])?.first?.contains("marker=alpha") == true)
        assertEmpty(try await read(second))
        try await write("beta", in: second)
        let beta = try await read(second)
        assertMarker("beta", in: beta)
        XCTAssertNotEqual(alpha["httpCache"] as? String, beta["httpCache"] as? String)
        XCTAssertTrue((beta["workers"] as? [String])?.first?.contains("marker=beta") == true)
        assertMarker("alpha", in: try await read(XCTUnwrap(first)))
        // Also exercise the native WebKit data records, not only JavaScript values.
        let records = await a.websiteDataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let types = records.reduce(into: Set<String>()) { $0.formUnion($1.dataTypes) }
        for type in [WKWebsiteDataTypeCookies, WKWebsiteDataTypeLocalStorage, WKWebsiteDataTypeIndexedDBDatabases,
                     WKWebsiteDataTypeFetchCache, WKWebsiteDataTypeServiceWorkerRegistrations] {
            XCTAssertTrue(types.contains(type), "Missing \(type)")
        }
        first = nil
        a.releaseClosedWindow()
        let recreated = makeBrowser(id: try XCTUnwrap(a.profileID))
        let restored = try await load(url, in: recreated)
        let restoredData = try await read(restored)
        assertMarker("alpha", in: restoredData)
        XCTAssertEqual(restoredData["httpCache"] as? String, alpha["httpCache"] as? String)
        assertMarker("beta", in: try await read(second))
    }

    func testSwitchingProfilesKeepsLivePageStateAndSeparateSameOriginData() async throws {
        let url = try startServer()
        let suite = "ProfileSwitchWebKitTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let profiles = ProfileStore(root: nil, defaults: defaults)
        let a = try profiles.create(name: "A")
        let b = try profiles.create(name: "B")
        ids += [a.id, b.id]
        let owner = try ProfileWindowController(profiles: profiles, profileID: a.id)
        let modelA = owner.browser
        browsers.append(modelA)
        let pageA = try await load(url, in: modelA)
        try await write("alpha", in: pageA)
        _ = try await run("document.getElementById('marker').value = 'unsaved form'; return 'ok'", in: pageA)
        owner.switchTo(b.id)
        browsers.append(owner.browser)
        let pageB = try await load(url, in: owner.browser)
        assertEmpty(try await read(pageB))
        try await write("beta", in: pageB)
        owner.switchTo(a.id)
        XCTAssertTrue(owner.browser === modelA)
        XCTAssertTrue(owner.browser.activeTab?.webView === pageA)
        let input = try await run("return document.getElementById('marker').value", in: pageA)
        XCTAssertEqual(input, "unsaved form")
        assertMarker("alpha", in: try await read(pageA))
        assertMarker("beta", in: try await read(pageB))
        // Cleanup site records before close releases the stores (tearDown also verifies they are empty).
        for model in browsers { await ProfileStore.clearWebsiteData(in: model.websiteDataStore) }
        owner.close()
        for profile in [a, b] {
            defaults.removePersistentDomain(forName: ProfileStore.defaultsDomain(for: profile.id))
            profiles.context(for: profile.id)?.prepareForDeletion()
        }
        defaults.removePersistentDomain(forName: suite)
    }

    func testPrivateWindowsAreFreshPerWindowAndCannotMutatePersistentProfiles() async throws {
        try await exercisePrivateStores()
    }

    private func exercisePrivateStores() async throws {
        let url = try startServer()
        let a = makeBrowser()
        let pageA = try await load(url, in: a)
        try await write("alpha", in: pageA)
        let first = BrowserModel.makePrivate(downloads: DownloadManager(), profileID: a.profileID)
        let second = BrowserModel.makePrivate(downloads: DownloadManager(), profileID: a.profileID)
        browsers += [first, second]
        let privatePage = try await load(url, in: first)
        assertEmpty(try await read(privatePage))
        try await write("private", in: privatePage)
        assertMarker("private", in: try await read(privatePage))
        autoreleasepool { first.addTab() }
        assertMarker("private", in: try await read(load(url, in: first)))
        let otherPrivatePage = try await load(url, in: second)
        assertEmpty(try await read(otherPrivatePage))
        assertMarker("alpha", in: try await read(pageA))
        XCTAssertNil(first.passwords)
        XCTAssertNil(first.history)
        let session = SessionStore(file: nil)
        XCTAssertEqual(session.attach(first), 0)
        XCTAssertTrue(session.snapshot.windows.isEmpty)
        first.releaseClosedWindow()
        let replacement = BrowserModel.makePrivate(downloads: DownloadManager(), profileID: a.profileID)
        browsers.append(replacement)
        assertEmpty(try await read(load(url, in: replacement)))
    }

    func testPopUpsDuplicateSuspendRestoreAndClearingStayInProfile() async throws {
        try await exerciseTabLifecycle()
    }

    private func exerciseTabLifecycle() async throws {
        let url = try startServer()
        let a = makeBrowser()
        let b = makeBrowser()
        let first = try await load(url, in: a)
        let second = try await load(url, in: b)
        try await write("alpha", in: first)
        try await write("beta", in: second)
        let opener = try XCTUnwrap(a.activeTab)
        autoreleasepool {
            a.duplicateTab(opener.id)
            XCTAssertTrue(a.activeTab?.webView?.configuration.websiteDataStore === a.websiteDataStore)
            a.activeTab?.suspend()
            a.activeTab?.restore()
            XCTAssertEqual(a.activeTab?.webView?.configuration.websiteDataStore.identifier, a.profileID)
            let child = a.openChildTab(of: opener, configuration: first.configuration, select: true)
            XCTAssertEqual(child.webView?.configuration.websiteDataStore.identifier, a.profileID)
        }
        let data = BrowsingData(history: HistoryStore(file: nil), session: SessionStore(file: nil), dataStore: a.websiteDataStore)
        await data.clear([.siteData, .cache], range: .all)
        assertMarker("beta", in: try await read(second))
        let cookieStore = autoreleasepool { a.websiteDataStore.httpCookieStore }
        let cookiesA = await cookieStore.allCookies()
        XCTAssertTrue(cookiesA.isEmpty)
    }
}
