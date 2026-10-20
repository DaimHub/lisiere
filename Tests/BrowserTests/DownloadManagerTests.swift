import WebKit
import XCTest
@testable import Browser

@MainActor
final class DownloadManagerTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DownloadTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testUniqueNamesNumberTakenFiles() {
        let directory = URL(filePath: "/Downloads")
        let taken: Set<String> = ["report.pdf", "report 2.pdf", "notes", ".env"]
        func name(_ filename: String) -> String {
            DownloadManager.uniqueURL(for: filename, in: directory) { taken.contains($0.lastPathComponent) }
                .lastPathComponent
        }

        XCTAssertEqual(name("report.pdf"), "report 3.pdf")
        XCTAssertEqual(name("notes"), "notes 2")
        XCTAssertEqual(name(".env"), ".env 2")
        XCTAssertEqual(name("photo.jpg"), "photo.jpg")
        XCTAssertEqual(name(""), "Download")
    }

    func testNamesCannotLeaveTheDownloadsFolder() {
        let directory = URL(filePath: "/Downloads")
        let url = DownloadManager.uniqueURL(for: "../../etc/passwd", in: directory) { _ in false }
        XCTAssertEqual(url.path, "/Downloads/passwd")
        XCTAssertEqual(DownloadManager.uniqueURL(for: "..", in: directory) { _ in false }.lastPathComponent,
                       "Download")
    }

    func testDownloadLinkSavesBesideExistingFile() async throws {
        let directory = try makeDirectory()
        try "old".write(to: directory.appending(path: "note.txt"), atomically: true, encoding: .utf8)
        let downloads = DownloadManager(directory: directory)
        let browser = BrowserModel(downloads: downloads)
        let tab = try XCTUnwrap(browser.activeTab)
        tab.isNewTab = false
        tab.restore()
        let webView = try XCTUnwrap(tab.webView)
        webView.loadHTMLString("<title>Files</title><a id=file download=note.txt href='data:text/plain,hello'>Get</a>",
                               baseURL: URL(string: "https://example.com")!)
        try await waitUntil { !tab.isLoading && tab.pageTitle == "Files" }

        _ = try await webView.evaluateJavaScript("document.getElementById('file').click(); 0")

        try await waitUntil { downloads.items.first?.state == .finished }
        let item = try XCTUnwrap(downloads.items.first)
        XCTAssertEqual(item.name, "note 2.txt")
        XCTAssertEqual(item.progress, 1)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(item.destinationURL), encoding: .utf8), "hello")
        XCTAssertEqual(try String(contentsOf: directory.appending(path: "note.txt"), encoding: .utf8), "old")
        XCTAssertFalse(downloads.isDownloading)

        downloads.clearFinished()
        XCTAssertTrue(downloads.items.isEmpty)
    }
}
