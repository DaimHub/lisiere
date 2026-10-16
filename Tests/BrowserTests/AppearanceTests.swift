import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import Browser

@MainActor
final class AppearanceTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "AppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testMissingAndUnknownPreferencesFollowSystem() {
        let defaults = defaults()
        for value in [nil, "future-theme"] as [String?] {
            defaults.set(value, forKey: BrowserAppearance.storageKey)
            var applied = NSAppearance(named: .aqua)
            let store = AppearanceStore(defaults: defaults) { applied = $0 }
            XCTAssertEqual(store.selection, .system)
            XCTAssertNil(applied)
        }
    }

    func testEveryChoicePersistsAndAppliesOnRelaunch() {
        let defaults = defaults()
        var applied: NSAppearance?
        let store = AppearanceStore(defaults: defaults) { applied = $0 }
        for choice in [BrowserAppearance.dark, .light, .system] {
            store.selection = choice
            XCTAssertEqual(defaults.string(forKey: BrowserAppearance.storageKey), choice.rawValue)
            XCTAssertEqual(applied?.name, choice.appearance?.name)
            applied = NSAppearance(named: .vibrantLight)
            let relaunched = AppearanceStore(defaults: defaults) { applied = $0 }
            XCTAssertEqual(relaunched.selection, choice)
            XCTAssertEqual(applied?.name, choice.appearance?.name)
        }
    }

    func testExistingAndNewNativeSurfacesInheritAppearance() throws {
        let original = NSApp.appearance
        defer { NSApp.appearance = original }
        let store = AppearanceStore(defaults: defaults())
        let existing = makeWindow()
        let field = FocusableTextField(frame: .zero)
        let glass = NSVisualEffectView(frame: .zero)
        existing.contentView?.addSubview(field)
        existing.contentView?.addSubview(glass)
        defer { existing.close() }

        for choice in [BrowserAppearance.dark, .light, .system] {
            store.selection = choice
            let expected = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            let newWindow = makeWindow()
            let alert = NSAlert()
            let panel = NSSavePanel()
            for surface in [existing, newWindow, alert.window, panel] {
                XCTAssertNil(surface.appearance)
                XCTAssertEqual(surface.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), expected)
            }
            XCTAssertEqual(field.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), expected)
            XCTAssertEqual(glass.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), expected)
            newWindow.close()
        }
        XCTAssertNil(NSApp.appearance, "System must remove the override so future macOS changes propagate.")
    }

    func testRegularAndPrivateWebPagesFollowThemeWithoutReloadOrInversion() async throws {
        let original = NSApp.appearance
        defer { NSApp.appearance = original }
        let store = AppearanceStore(defaults: defaults())
        for isPrivate in [false, true] {
            let browser = isPrivate ? BrowserModel.makePrivate(downloads: DownloadManager()) : BrowserModel()
            let tab = BrowserTab(configuration: browser.makeConfiguration(), appearance: store)
            tab.browser = browser
            let webView = try XCTUnwrap(tab.webView)
            let window = makeWindow()
            let host = PageHostView(frame: window.contentView!.bounds)
            window.contentView = host
            host.show(tab.contentView)
            window.orderFront(nil)
            defer { window.close() }
            store.selection = .light
            webView.loadHTMLString("""
                <meta name="color-scheme" content="light dark">
                <style>
                body { background: rgb(250, 250, 250); color: rgb(20, 20, 20); }
                @media (prefers-color-scheme: dark) {
                  body { background: rgb(20, 20, 20); color: rgb(250, 250, 250); }
                }
                #fixed { color: rgb(0, 0, 0); background: rgb(255, 255, 255); }
                </style><title>Theme fixture</title><p id="fixed">Unchanged content</p>
                <script>window.loadID = Math.random();</script>
                """, baseURL: nil)
            try await waitUntil { !webView.isLoading && webView.title == "Theme fixture" }
            let loadID = try await webView.evaluateJavaScript("window.loadID") as? Double
            for appChoice in [BrowserAppearance.light, .dark, .system] {
                store.selection = appChoice
                let appIsDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                for pageChoice in [WebPageAppearance.light, .dark, .followApp] {
                    store.pageSelection = pageChoice
                    let dark = pageChoice == .dark || (pageChoice == .followApp && appIsDark)
                    try await assertPage(webView, dark: dark, background: dark ? "rgb(20, 20, 20)" : "rgb(250, 250, 250)")
                    XCTAssertEqual(NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
                                   appIsDark ? .darkAqua : .aqua, "Website choices must not change the app theme.")
                    let fixed = try await webView.evaluateJavaScript("getComputedStyle(document.querySelector('#fixed')).backgroundColor") as? String
                    let filter = try await webView.evaluateJavaScript("getComputedStyle(document.body).filter") as? String
                    let currentLoadID = try await webView.evaluateJavaScript("window.loadID") as? Double
                    XCTAssertEqual(fixed, "rgb(255, 255, 255)")
                    XCTAssertEqual(filter, "none")
                    XCTAssertEqual(currentLoadID, loadID, "Changing appearance must not reload the page.")
                }
            }
        }
    }

    func testPageWithoutDarkStylesKeepsItsColors() async throws {
        let original = NSApp.appearance
        defer { NSApp.appearance = original }
        let store = AppearanceStore(defaults: defaults())
        let webView = WKWebView()
        store.attach(webView)
        let window = makeWindow()
        window.contentView = webView
        window.orderFront(nil)
        defer { window.close() }
        webView.loadHTMLString("<title>Light site</title><body style='background:white;color:black'>Light only</body>",
                               baseURL: nil)
        try await waitUntil { !webView.isLoading && webView.title == "Light site" }
        for choice in [WebPageAppearance.light, .dark] {
            store.pageSelection = choice
            try await assertPage(webView, dark: choice == .dark, background: "rgb(255, 255, 255)")
            let color = try await webView.evaluateJavaScript("getComputedStyle(document.body).color") as? String
            XCTAssertEqual(color, "rgb(0, 0, 0)")
        }
    }

    func testWebsitePreferencePersistsSeparatelyAndFallsBackToFollowingApp() {
        let defaults = defaults()
        defaults.set("unknown", forKey: WebPageAppearance.storageKey)
        let store = AppearanceStore(defaults: defaults, applyAppearance: { _ in })
        XCTAssertEqual(store.pageSelection, .followApp)
        store.selection = .dark
        for choice in [WebPageAppearance.light, .dark, .followApp] {
            store.pageSelection = choice
            let relaunched = AppearanceStore(defaults: defaults, applyAppearance: { _ in })
            XCTAssertEqual(relaunched.pageSelection, choice)
            XCTAssertEqual(relaunched.selection, .dark)
        }
    }

    func testDetachedAndNewWebViewsUpdateWithoutBeingRetained() {
        let store = AppearanceStore(defaults: defaults(), applyAppearance: { _ in })
        weak var releasedView: WKWebView?
        autoreleasepool {
            let background = WKWebView()
            releasedView = background
            store.attach(background)
            store.pageSelection = .dark
            XCTAssertEqual(background.appearance?.name, .darkAqua)
            let newTab = WKWebView()
            store.attach(newTab)
            XCTAssertEqual(newTab.appearance?.name, .darkAqua)
            store.pageSelection = .light
            XCTAssertEqual(background.appearance?.name, .aqua)
            XCTAssertEqual(newTab.appearance?.name, .aqua)
            store.pageSelection = .followApp
            XCTAssertNil(background.appearance)
            XCTAssertNil(newTab.appearance)
        }
        XCTAssertNil(releasedView, "Appearance tracking must not keep a closed or suspended web view alive.")
    }

    func testSeparateThemeSwitchFollowsAppByDefaultAndRemembersItsChoice() {
        let original = NSApp.appearance
        defer { NSApp.appearance = original }
        let defaults = defaults()
        let store = AppearanceStore(defaults: defaults)
        let webView = WKWebView()
        store.attach(webView)
        XCTAssertFalse(store.usesSeparatePageTheme)
        XCTAssertNil(webView.appearance)
        store.selection = .dark
        store.usesSeparatePageTheme = true
        XCTAssertEqual(store.pageSelection, .dark, "First activation starts with the app's current appearance.")
        store.pageSelection = .light
        XCTAssertEqual(webView.appearance?.name, .aqua)
        store.usesSeparatePageTheme = false
        XCTAssertEqual(store.pageSelection, .followApp)
        XCTAssertNil(webView.appearance, "Turning the switch off immediately restores app inheritance.")
        let relaunched = AppearanceStore(defaults: defaults)
        XCTAssertFalse(relaunched.usesSeparatePageTheme)
        relaunched.usesSeparatePageTheme = true
        XCTAssertEqual(relaunched.pageSelection, .light, "The separate choice survives disabling and relaunching.")
        XCTAssertEqual(relaunched.selection, .dark)
    }

    func testRestoredTabsUseTheLatestWebsitePreference() async throws {
        let store = AppearanceStore(defaults: defaults(), applyAppearance: { _ in })
        let tab = BrowserTab(appearance: store)
        tab.load(URL(string: "data:text/html,<title>Restorable</title>")!)
        try await waitUntil { !tab.isLoading && tab.pageTitle == "Restorable" }
        weak var oldView = tab.webView
        tab.suspend()
        try await waitUntil { oldView == nil }
        store.pageSelection = .dark
        tab.restore()
        XCTAssertEqual(tab.webView?.appearance?.name, .darkAqua)
        try await waitUntil { !tab.isLoading && tab.pageTitle == "Restorable" }

        store.pageSelection = .light
        let saved = BrowserTab(url: tab.url, title: tab.pageTitle, interactionState: tab.interactionState,
                               appearance: store)
        saved.restore()
        XCTAssertEqual(saved.webView?.appearance?.name, .aqua)
        store.pageSelection = .followApp
        XCTAssertNil(tab.webView?.appearance)
        XCTAssertNil(saved.webView?.appearance)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    private func assertPage(_ webView: WKWebView, dark: Bool, background: String,
                            file: StaticString = #filePath, line: UInt = #line) async throws {
        // WebKit receives appearance changes asynchronously, including updates to live media queries.
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            let values = try await webView.evaluateJavaScript("""
                [matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light',
                 getComputedStyle(document.body).backgroundColor]
                """) as? [String]
            if values == [dark ? "dark" : "light", background] { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Web page did not adopt the expected appearance and colors", file: file, line: line)
    }
}
