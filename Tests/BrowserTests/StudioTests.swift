import WebKit
import XCTest
@testable import Browser

@MainActor
final class StudioTests: XCTestCase {
    private func makeLibrary() throws -> GeneratedViewLibrary {
        let root = FileManager.default.temporaryDirectory.appending(path: "StudioTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return GeneratedViewLibrary(rootURL: root)
    }

    private func writeEntry(_ html: String, for id: UUID, in library: GeneratedViewLibrary) throws {
        try FileManager.default.createDirectory(at: library.directory(for: id), withIntermediateDirectories: true)
        try html.write(to: library.entryFile(for: id), atomically: true, encoding: .utf8)
    }

    func testPromptDescribesNewAndFollowUpRequests() {
        let first = StudioPrompt.make(request: "A todo list", previousRequests: [])
        XCTAssertTrue(first.contains("Build this:\nA todo list"))
        XCTAssertTrue(first.contains("localStorage"))

        let followUp = StudioPrompt.make(request: "Add due dates", previousRequests: ["A todo list"])
        XCTAssertTrue(followUp.contains("- A todo list"))
        XCTAssertTrue(followUp.contains("Add due dates"))
        XCTAssertFalse(followUp.contains("Build this:"))
    }

    func testLibraryPersistsViewsAndReadsTitles() throws {
        let library = try makeLibrary()
        let id = UUID()
        try writeEntry("<html><head><title> Simple Tasks </title></head></html>", for: id, in: library)

        library.save(GeneratedView(id: id, title: library.pageTitle(for: id) ?? "", prompts: ["A todo list"]))

        let reloaded = GeneratedViewLibrary(rootURL: library.rootURL)
        XCTAssertEqual(reloaded.views.map(\.title), ["Simple Tasks"])
        XCTAssertTrue(reloaded.hasContent(id))
        XCTAssertEqual(reloaded.url(for: id).absoluteString,
                       "athas-view://\(id.uuidString.lowercased())/index.html")

        reloaded.delete(id)
        XCTAssertTrue(reloaded.views.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.directory(for: id).path))
    }

    func testSchemeHandlerServesFilesInsideTheViewOnly() async throws {
        let library = try makeLibrary()
        let id = UUID()
        try writeEntry("<h1>hi</h1>", for: id, in: library)
        try "secret".write(to: library.rootURL.appending(path: "views.json"), atomically: true, encoding: .utf8)
        let handler = GeneratedViewSchemeHandler(rootURL: library.rootURL)

        var body = Data()
        var mimeType: String?
        for try await result in handler.reply(for: URLRequest(url: library.url(for: id))) {
            switch result {
            case .response(let response): mimeType = response.mimeType
            case .data(let data): body.append(data)
            @unknown default: break
            }
        }
        XCTAssertEqual(String(data: body, encoding: .utf8), "<h1>hi</h1>")
        XCTAssertEqual(mimeType, "text/html")

        let escape = URL(string: "athas-view://\(id.uuidString.lowercased())/../views.json")!
        do {
            for try await _ in handler.reply(for: URLRequest(url: escape)) {}
            XCTFail("Served a file outside the view's folder")
        } catch {}
    }
}
