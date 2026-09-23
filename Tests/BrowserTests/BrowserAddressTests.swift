import XCTest
@testable import Browser

final class BrowserAddressTests: XCTestCase {
    func testHTTPSAddressIsPreserved() {
        XCTAssertEqual(BrowserAddress.url(for: " https://example.com/path ")?.absoluteString,
                       "https://example.com/path")
    }

    func testDomainGainsHTTPS() {
        XCTAssertEqual(BrowserAddress.url(for: "example.com/docs")?.absoluteString,
                       "https://example.com/docs")
    }

    func testWordsBecomeEncodedSearch() {
        let url = BrowserAddress.url(for: "swift webkit")
        XCTAssertEqual(url?.host(), "www.google.com")
        XCTAssertEqual(URLComponents(url: url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first?.value, "swift webkit")
    }

    func testEmptyInputDoesNothing() {
        XCTAssertNil(BrowserAddress.url(for: "  "))
    }
}
