import XCTest
@testable import Browser

@MainActor
final class BrowserCompatibilityTests: XCTestCase {
    func testTabsAdvertiseSafariCompatibleUserAgent() async throws {
        let webView = try XCTUnwrap(BrowserTab().webView)
        webView.loadHTMLString("<html><body>Ready</body></html>", baseURL: URL(string: "https://example.com")!)

        let userAgent = try await webView.evaluateJavaScript("navigator.userAgent") as? String

        XCTAssertTrue(userAgent?.contains("Version/") == true)
        XCTAssertTrue(userAgent?.contains("Safari/605.1.15") == true)
    }
}
