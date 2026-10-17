import WebKit
import XCTest
@testable import Browser

/// Keeps passwords in memory, so tests never touch the keychain.
@MainActor
private final class MemoryPasswordStorage: PasswordStorage {
    var items: [SavedPassword: String] = [:]
    var readDelay: Duration = .zero

    func savedPasswords() async throws -> [SavedPassword] {
        try await Task.sleep(for: readDelay)
        return Array(items.keys)
    }
    func password(for account: SavedPassword) throws -> String? { items[account] }
    func save(_ password: String, for account: SavedPassword) throws { items[account] = password }
    func remove(_ account: SavedPassword) throws { items[account] = nil }
}

@MainActor
private final class MessageRecorder: NSObject, WKScriptMessageHandler {
    var captures: [PasswordCapture] = []
    var sawPasswordFields = false
    var fieldAnnouncements = 0

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if (message.body as? [String: Any])?["type"] as? String == "fields" { sawPasswordFields = true; fieldAnnouncements += 1 }
        if let capture = PasswordCapture(body: message.body, isMainFrame: message.frameInfo.isMainFrame,
                                         origin: PasswordOrigin(message.frameInfo.securityOrigin)) {
            captures.append(capture)
        }
    }
}

@MainActor
final class PasswordTests: XCTestCase {
    private let example = PasswordOrigin(host: "example.com")!

    /// A real WebKit page and native sheet, with disposable website data and an in-memory keychain.
    private func promptBrowser() -> (BrowserModel, MemoryPasswordStorage, NSWindow) {
        let storage = MemoryPasswordStorage()
        let dataStoreID = UUID()
        let browser = BrowserModel(websiteDataStore: WKWebsiteDataStore(forIdentifier: dataStoreID),
                                   passwords: PasswordManager(storage: storage))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        browser.window = window
        window.contentView = browser.activeTab?.contentView
        window.orderFront(nil)
        addTeardownBlock { @MainActor in
            await ProfileStore.clearWebsiteData(in: browser.websiteDataStore)
            browser.releaseClosedWindow()
            window.close()
            // XCTest's autorelease pool may keep the empty store alive until the host exits.
            try? await WKWebsiteDataStore.remove(forIdentifier: dataStoreID)
        }
        return (browser, storage, window)
    }

    private func loadPromptForm(in tab: BrowserTab, onSubmit: String) async throws -> WKWebView {
        let webView = try XCTUnwrap(tab.webView)
        tab.isNewTab = false
        webView.loadHTMLString("""
        <title>Sign in</title>
        <form onsubmit="event.preventDefault(); \(onSubmit)">
          <input name="username" autocomplete="username" value="alice">
          <input name="password" type="password" value="test-secret">
          <button>Sign In</button>
        </form>
        """, baseURL: URL(string: "https://example.com/login"))
        try await waitUntil { tab.hasPasswordFields && !tab.isLoading }
        return webView
    }

    func testRedirectWaitsForEveryPasswordChoice() async throws {
        for response in [NSApplication.ModalResponse.alertFirstButtonReturn, .alertSecondButtonReturn,
                         .alertThirdButtonReturn] {
            let (browser, storage, window) = promptBrowser()
            let tab = try XCTUnwrap(browser.activeTab)
            let webView = try await loadPromptForm(in: tab, onSubmit: "location.href = 'about:blank'")
            _ = try await webView.evaluateJavaScript("document.querySelector('button').click(); 0")
            try await waitUntil { window.attachedSheet != nil }
            // Let the queued WebKit navigation run, rather than checking only the moment the sheet appears.
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertEqual(tab.pageTitle, "Sign in")
            XCTAssertNotEqual(webView.url?.absoluteString, "about:blank")
            XCTAssertTrue(storage.items.isEmpty)
            XCTAssertFalse(tab.canSuspend)

            let sheet = try XCTUnwrap(window.attachedSheet)
            window.endSheet(sheet, returnCode: response)
            try await waitUntil { webView.url?.absoluteString == "about:blank" && !tab.isLoading }
            XCTAssertEqual(storage.items.count, response == .alertFirstButtonReturn ? 1 : 0)
            XCTAssertEqual(browser.passwords?.neverSaveSites.contains(example.description),
                           response == .alertThirdButtonReturn)
            if response == .alertFirstButtonReturn {
                XCTAssertEqual(storage.items[SavedPassword(origin: example, username: "alice")], "test-secret")
            }
        }
    }

    func testImmediatePopupCloseWaitsForSaving() async throws {
        let (browser, storage, window) = promptBrowser()
        let opener = try XCTUnwrap(browser.activeTab)
        let openerView = try await loadPromptForm(in: opener, onSubmit: "")
        _ = try await openerView.evaluateJavaScript("window.popup = window.open('about:blank'); 0")
        try await waitUntil { browser.tabs.count == 2 }
        let popup = try XCTUnwrap(browser.activeTab)
        XCTAssertNotIdentical(popup, opener)
        window.contentView = popup.contentView
        let webView = try await loadPromptForm(in: popup, onSubmit: "window.close()")
        _ = try await webView.evaluateJavaScript("document.querySelector('form').requestSubmit(); 0")
        try await waitUntil { window.attachedSheet != nil }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertNotNil(browser.tab(withID: popup.id))
        XCTAssertTrue(storage.items.isEmpty)

        window.endSheet(try XCTUnwrap(window.attachedSheet), returnCode: .alertFirstButtonReturn)
        try await waitUntil { browser.tab(withID: popup.id) == nil }
        XCTAssertEqual(browser.activeTabID, opener.id)
        XCTAssertEqual(storage.items[SavedPassword(origin: example, username: "alice")], "test-secret")
    }

    func testUserCloseCancelsPendingPasswordAndNavigation() async throws {
        let (browser, storage, window) = promptBrowser()
        let tab = try XCTUnwrap(browser.activeTab)
        let webView = try await loadPromptForm(in: tab, onSubmit: "location.href = 'about:blank'")
        _ = try await webView.evaluateJavaScript("document.querySelector('form').requestSubmit(); 0")
        try await waitUntil { window.attachedSheet != nil }
        browser.closeTab(tab.id)
        try await waitUntil { window.attachedSheet == nil }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertNil(browser.tab(withID: tab.id))
        XCTAssertTrue(storage.items.isEmpty)
        XCTAssertNotEqual(webView.url?.absoluteString, "about:blank")
    }

    func testBackgroundPasswordPromptWaitsForSelectionAndCanBeCancelled() async throws {
        let (browser, storage, window) = promptBrowser()
        let tab = try XCTUnwrap(browser.activeTab)
        let webView = try await loadPromptForm(in: tab, onSubmit: "location.href = 'about:blank'")
        browser.addTab()
        window.contentView = browser.activeTab?.contentView
        _ = try await webView.evaluateJavaScript("document.querySelector('form').requestSubmit(); 0")
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertNil(window.attachedSheet)
        XCTAssertEqual(tab.pageTitle, "Sign in")
        XCTAssertFalse(tab.canSuspend)

        browser.closeTab(tab.id)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertNotEqual(webView.url?.absoluteString, "about:blank")
        XCTAssertTrue(storage.items.isEmpty)
        XCTAssertNil(window.attachedSheet)
    }

    func testUpdatePasswordWaitsForDecision() async throws {
        let (browser, storage, window) = promptBrowser()
        let account = SavedPassword(origin: example, username: "alice")
        storage.items[account] = "old-test-secret"
        let tab = try XCTUnwrap(browser.activeTab)
        let webView = try await loadPromptForm(in: tab, onSubmit: "location.href = 'about:blank'")
        _ = try await webView.evaluateJavaScript("document.querySelector('form').requestSubmit(); 0")
        try await waitUntil { window.attachedSheet != nil }
        XCTAssertEqual(storage.items[account], "old-test-secret")
        window.endSheet(try XCTUnwrap(window.attachedSheet), returnCode: .alertFirstButtonReturn)
        try await waitUntil { webView.url?.absoluteString == "about:blank" && !tab.isLoading }
        XCTAssertEqual(storage.items[account], "test-secret")
    }

    private func submission(username: String = "alice", password: String = "secret") -> [String: Any] {
        ["type": "submit", "username": username, "password": password]
    }

    func testOriginsMatchExactly() throws {
        let accounts = try XCTUnwrap(PasswordOrigin(url: URL(string: "https://Accounts.Example.com/login?next=/")))
        XCTAssertEqual(accounts, PasswordOrigin(host: "accounts.example.com"))
        XCTAssertEqual(accounts.description, "https://accounts.example.com")
        XCTAssertNotEqual(accounts, example)
        XCTAssertNotEqual(PasswordOrigin(url: URL(string: "https://example.com:8443")), example)
        XCTAssertEqual(PasswordOrigin(url: URL(string: "https://example.com:8443"))?.description, "https://example.com:8443")
        XCTAssertEqual(PasswordOrigin(url: URL(string: "https://example.com:443/a")), example)

        XCTAssertNil(PasswordOrigin(url: URL(string: "http://example.com")))
        XCTAssertNil(PasswordOrigin(url: URL(string: "file:///tmp/login.html")))
        XCTAssertNil(PasswordOrigin(url: nil))
    }

    func testOnlyTopFrameHTTPSSubmissionsAreCaptured() throws {
        let capture = try XCTUnwrap(PasswordCapture(body: submission(username: " alice "), isMainFrame: true,
                                                    origin: example))
        XCTAssertEqual(capture.account, SavedPassword(origin: example, username: "alice"))
        XCTAssertEqual(capture.password, "secret")

        XCTAssertNil(PasswordCapture(body: submission(), isMainFrame: false, origin: example))
        XCTAssertNil(PasswordCapture(body: submission(), isMainFrame: true, origin: nil))
        XCTAssertNil(PasswordCapture(body: submission(password: ""), isMainFrame: true, origin: example))
        XCTAssertNil(PasswordCapture(body: ["type": "fields"], isMainFrame: true, origin: example))
        XCTAssertNil(PasswordCapture(body: "alice:secret", isMainFrame: true, origin: example))
        XCTAssertNil(PasswordCapture(body: submission(password: String(repeating: "x", count: 2000)),
                                     isMainFrame: true, origin: example))
    }

    func testOffersToSaveNewAndChangedPasswordsOnly() async throws {
        let storage = MemoryPasswordStorage()
        let passwords = PasswordManager(storage: storage)
        let capture = try XCTUnwrap(PasswordCapture(body: submission(), isMainFrame: true, origin: example))

        let offer1 = await passwords.offer(for: capture)
        XCTAssertEqual(offer1, .save)
        try await passwords.save(capture)
        let offer2 = await passwords.offer(for: capture)
        XCTAssertNil(offer2)
        XCTAssertEqual(passwords.passwords(for: example).map(\.username), ["alice"])
        XCTAssertTrue(passwords.passwords(for: PasswordOrigin(host: "accounts.example.com")).isEmpty)
        XCTAssertTrue(passwords.passwords(for: nil).isEmpty)

        let changed = try XCTUnwrap(PasswordCapture(body: submission(password: "new secret"), isMainFrame: true,
                                                    origin: example))
        let offer3 = await passwords.offer(for: changed)
        XCTAssertEqual(offer3, .update)

        passwords.offersToSave = false
        let offer4 = await passwords.offer(for: changed)
        XCTAssertNil(offer4)
        passwords.offersToSave = true

        let other = PasswordOrigin(host: "other.example")!
        let otherCapture = try XCTUnwrap(PasswordCapture(body: submission(), isMainFrame: true, origin: other))
        passwords.neverSave(on: other)
        let offer5 = await passwords.offer(for: otherCapture)
        XCTAssertNil(offer5)
        passwords.allowSaving(on: other.description)
        let offer6 = await passwords.offer(for: otherCapture)
        XCTAssertEqual(offer6, .save)

        await passwords.remove(capture.account)
        XCTAssertTrue(storage.items.isEmpty)
    }

    func testPrivateWindowsNeverLoadTheAutofillScript() {
        let passwords = PasswordManager(storage: MemoryPasswordStorage())

        let browser = BrowserModel(passwords: passwords)
        XCTAssertEqual(browser.makeConfiguration().userContentController.userScripts.count, 1)

        let privateWindow = BrowserModel.makePrivate(downloads: DownloadManager())
        XCTAssertNil(privateWindow.passwords)
        XCTAssertTrue(privateWindow.makeConfiguration().userContentController.userScripts.isEmpty)
        XCTAssertNil(BrowserModel(websiteDataStore: .nonPersistent(), passwords: passwords).passwords)
    }

    private func loadForm(_ html: String, recorder: MessageRecorder) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        PasswordAutofill.install(in: configuration.userContentController, handler: recorder)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)
        webView.loadHTMLString(html, baseURL: URL(string: "https://example.com/login"))
        try await waitUntil { recorder.sawPasswordFields }
        return webView
    }

    func testSubmittedSignInFormsAreReported() async throws {
        let recorder = MessageRecorder()
        let webView = try await loadForm("""
        <form onsubmit="event.preventDefault()">
          <input name="search" type="search">
          <input name="email" type="email" autocomplete="username">
          <input name="password" type="password">
          <button>Sign In</button>
        </form>
        """, recorder: recorder)

        _ = try await webView.evaluateJavaScript("""
        document.querySelector('[name=email]').value = 'alice@example.com';
        document.querySelector('[name=password]').value = 'secret';
        document.querySelector('form').requestSubmit(); 0
        """)

        try await waitUntil { !recorder.captures.isEmpty }
        XCTAssertEqual(recorder.captures, [PasswordCapture(body: submission(username: "alice@example.com"),
                                                           isMainFrame: true, origin: example)])
    }

    func testSignUpFormsReportTheNewPassword() async throws {
        let recorder = MessageRecorder()
        let webView = try await loadForm("""
        <form onsubmit="event.preventDefault()">
          <input name="user" type="text">
          <input name="current" type="password" autocomplete="current-password">
          <input name="new" type="password" autocomplete="new-password">
        </form>
        """, recorder: recorder)

        _ = try await webView.evaluateJavaScript("""
        document.querySelector('[name=user]').value = 'bob';
        document.querySelector('[name=current]').value = 'old';
        document.querySelector('[name=new]').value = 'brand new';
        document.querySelector('form').requestSubmit(); 0
        """)

        try await waitUntil { !recorder.captures.isEmpty }
        XCTAssertEqual(recorder.captures.first?.username, "bob")
        XCTAssertEqual(recorder.captures.first?.password, "brand new")
    }

    func testPasswordsOnlyFillOnTheirOrigin() async throws {
        let recorder = MessageRecorder()
        let webView = try await loadForm("""
        <form><input name="user" type="text"><input name="password" type="password"></form>
        """, recorder: recorder)
        let values = "[document.querySelector('[name=user]').value, document.querySelector('[name=password]').value]"

        let refused = try await webView.callAsyncJavaScript(PasswordAutofill.fillScript, arguments: [
            "origin": "https://evil.example", "username": "alice", "secret": "secret",
        ], in: nil, contentWorld: PasswordAutofill.world)
        XCTAssertEqual(refused as? Bool, false)
        let refusedValues = try await webView.evaluateJavaScript(values) as? [String]
        XCTAssertEqual(refusedValues, ["", ""])

        let filled = try await webView.callAsyncJavaScript(PasswordAutofill.fillScript, arguments: [
            "origin": example.description, "username": "alice", "secret": "secret",
        ], in: nil, contentWorld: PasswordAutofill.world)
        XCTAssertEqual(filled as? Bool, true)
        let filledValues = try await webView.evaluateJavaScript(values) as? [String]
        XCTAssertEqual(filledValues, ["alice", "secret"])
    }

    func testPageScriptsCantReachTheAutofillHandler() async throws {
        let recorder = MessageRecorder()
        let webView = try await loadForm("<form><input type=password></form>", recorder: recorder)

        let reachable = try await webView.evaluateJavaScript(
            "typeof window.webkit?.messageHandlers?.\(PasswordAutofill.handlerName)")
        XCTAssertEqual(reachable as? String, "undefined")
    }
    func testClosingDuringCredentialLookupNeverShowsALateSheet() async throws {
        let (browser, storage, window) = promptBrowser()
        storage.readDelay = .milliseconds(450)
        let tab = try XCTUnwrap(browser.activeTab)
        let webView = try await loadPromptForm(in: tab, onSubmit: "location.href = 'about:blank'")
        _ = try await webView.evaluateJavaScript("document.querySelector('form').requestSubmit(); 0")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(window.attachedSheet)
        XCTAssertNotEqual(webView.url?.absoluteString, "about:blank")
        browser.closeTab(tab.id)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertNil(window.attachedSheet)
        XCTAssertTrue(storage.items.isEmpty)
        XCTAssertNil(browser.tab(withID: tab.id))
    }

    func testPasswordDetectionInspectsChangedSubtreesWithoutDocumentRescans() async throws {
        for insertion in [
            "document.body.insertAdjacentHTML('beforeend', '<input type=password>')",
            "document.body.insertAdjacentHTML('beforeend', '<form><div><input type=password></div></form>')",
            "document.querySelector('#disabled').disabled = false",
            "document.querySelector('#plain').type = 'password'"
        ] {
            let recorder = MessageRecorder()
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.userContentController.addUserScript(WKUserScript(source: """
                globalThis.fullPasswordScans = 0;
                const original = Document.prototype.querySelectorAll;
                Document.prototype.querySelectorAll = function(selector) {
                    if (selector === 'input[type=password]') globalThis.fullPasswordScans++;
                    return original.call(this, selector);
                };
                """, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: PasswordAutofill.world))
            PasswordAutofill.install(in: configuration.userContentController, handler: recorder)
            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.loadHTMLString("<title>Dynamic</title><input id=disabled type=password disabled><input id=plain>",
                                   baseURL: URL(string: "https://example.com/dynamic"))
            try await waitUntil { !webView.isLoading && webView.title == "Dynamic" }
            let scans = try await webView.callAsyncJavaScript("""
                for (let i = 0; i < 40; i++) {
                    const span = document.createElement('span');
                    span.textContent = 'unrelated update';
                    document.body.append(span);
                    await Promise.resolve();
                }
                const detached = document.createElement('input'); detached.type = 'password';
                document.body.append(detached); detached.remove();
                await Promise.resolve();
                return globalThis.fullPasswordScans;
                """, arguments: [:], in: nil, contentWorld: PasswordAutofill.world)
            XCTAssertEqual(scans as? Int, 1)
            XCTAssertFalse(recorder.sawPasswordFields)
            _ = try await webView.evaluateJavaScript(insertion + "; 0")
            try await waitUntil { recorder.sawPasswordFields }
            XCTAssertEqual(recorder.fieldAnnouncements, 1)
            let finalScans = try await webView.callAsyncJavaScript("return globalThis.fullPasswordScans;",
                arguments: [:], in: nil, contentWorld: PasswordAutofill.world)
            XCTAssertEqual(finalScans as? Int, 1)
        }
    }

}
