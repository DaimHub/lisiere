import XCTest
@testable import Browser

@MainActor
final class BrowserCompatibilityTests: XCTestCase {
    func testTabsAdvertiseSafariCompatibleUserAgent() async throws {
        let page = BrowserTab().page
        _ = page.load(html: "<html><body>Ready</body></html>",
                      baseURL: URL(string: "https://example.com")!)

        let userAgent = try await page.callJavaScript("return navigator.userAgent", arguments: [:]) as? String

        XCTAssertTrue(userAgent?.contains("Version/") == true)
        XCTAssertTrue(userAgent?.contains("Safari/605.1.15") == true)
    }
}
