import XCTest
@testable import Browser

final class PageLoadErrorTests: XCTestCase {
    private let url = URL(string: "https://example.com/page")!

    private func kind(_ domain: String, _ code: Int) -> PageLoadError.Kind? {
        PageLoadError(NSError(domain: domain, code: code), url: url)?.kind
    }

    func testIgnoresLoadsThatDidNotFail() {
        XCTAssertNil(kind(NSURLErrorDomain, NSURLErrorCancelled))
        XCTAssertNil(kind(NSURLErrorDomain, NSURLErrorUnsupportedURL))
        // Frame load interrupted by a policy change, as when a page becomes a download.
        XCTAssertNil(kind(PageLoadError.webKitErrorDomain, 102))
        XCTAssertNil(kind(PageLoadError.webKitErrorDomain, 204))
    }

    func testClassifiesNetworkErrors() {
        XCTAssertEqual(kind(NSURLErrorDomain, NSURLErrorNotConnectedToInternet), .offline)
        XCTAssertEqual(kind(NSURLErrorDomain, NSURLErrorCannotFindHost), .serverNotFound)
        XCTAssertEqual(kind(NSURLErrorDomain, NSURLErrorDNSLookupFailed), .serverNotFound)
        XCTAssertEqual(kind(NSURLErrorDomain, NSURLErrorCannotConnectToHost), .cannotConnect)
        XCTAssertEqual(kind(NSURLErrorDomain, NSURLErrorTimedOut), .timedOut)
        XCTAssertEqual(kind(NSURLErrorDomain, NSURLErrorServerCertificateUntrusted), .invalidCertificate)
        XCTAssertEqual(kind(NSURLErrorDomain, NSURLErrorServerCertificateHasBadDate), .invalidCertificate)
        XCTAssertEqual(kind(NSURLErrorDomain, NSURLErrorSecureConnectionFailed), .secureConnectionFailed)
        if case .other = kind(NSURLErrorDomain, NSURLErrorBadServerResponse) {} else {
            XCTFail("Expected a generic error")
        }
    }

    func testUsesTheFailingAddress() {
        let failingURL = URL(string: "https://expired.example/")!
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateHasBadDate,
                            userInfo: [NSURLErrorFailingURLErrorKey: failingURL])

        let loadError = PageLoadError(error, url: url)

        XCTAssertEqual(loadError?.url, failingURL)
        XCTAssertEqual(loadError?.title, "This Connection Isn’t Private")
        XCTAssertTrue(loadError?.message.contains("expired.example") == true)
        XCTAssertEqual(PageLoadError(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut), url: url)?.url, url)
    }
}
