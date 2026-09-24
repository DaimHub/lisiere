import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// A small web app Codex built from a request, stored as `index.html` in its own folder.
struct GeneratedView: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var prompts: [String]
    var createdAt = Date()
    var updatedAt = Date()
}

/// Generated views shared by every window, kept in Application Support.
@MainActor
@Observable
final class GeneratedViewLibrary {
    private(set) var views: [GeneratedView] = []
    private(set) var models: [CodexModel] = []
    let rootURL: URL

    static let scheme = "athas-view"

    init(rootURL: URL? = nil) {
        self.rootURL = rootURL ?? URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "dev.athas.browser")
            .appending(path: "Views")
        try? FileManager.default.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let views = try? JSONDecoder().decode([GeneratedView].self, from: data) {
            self.views = views
        }
    }

    private var indexURL: URL { rootURL.appending(path: "views.json") }

    func view(withID id: UUID?) -> GeneratedView? {
        guard let id else { return nil }
        return views.first { $0.id == id }
    }

    func directory(for id: UUID) -> URL {
        rootURL.appending(path: id.uuidString.lowercased())
    }

    func entryFile(for id: UUID) -> URL {
        directory(for: id).appending(path: "index.html")
    }

    func hasContent(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: entryFile(for: id).path)
    }

    /// Each view gets its own origin, so its `localStorage` stays separate from the others.
    func url(for id: UUID) -> URL {
        URL(string: "\(Self.scheme)://\(id.uuidString.lowercased())/index.html")!
    }

    func save(_ view: GeneratedView) {
        if let index = views.firstIndex(where: { $0.id == view.id }) {
            views[index] = view
        } else {
            views.insert(view, at: 0)
        }
        persist()
    }

    func delete(_ id: UUID) {
        views.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: directory(for: id))
        persist()
    }

    /// Reads the `<title>` Codex was asked to set.
    func pageTitle(for id: UUID) -> String? {
        guard let html = try? String(contentsOf: entryFile(for: id), encoding: .utf8),
              let start = html.range(of: "<title>", options: .caseInsensitive),
              let end = html.range(of: "</title>", options: .caseInsensitive, range: start.upperBound..<html.endIndex)
        else { return nil }
        let title = html[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    func loadModels() async {
        guard models.isEmpty else { return }
        models = (try? await Codex.models()) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(views) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}

/// Serves `athas-view://<view id>/<path>` from that view's folder.
final class GeneratedViewSchemeHandler: NSObject, WKURLSchemeHandler {
    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// Reads a file inside the view's folder. Paths that lead anywhere else fail.
    func response(for url: URL) throws -> (HTTPURLResponse, Data) {
        guard let host = url.host(), UUID(uuidString: host) != nil else { throw URLError(.badURL) }
        let directory = rootURL.appending(path: host).standardizedFileURL
        let path = url.path().isEmpty || url.path() == "/" ? "index.html" : String(url.path().dropFirst())
        let fileURL = directory.appending(path: path).standardizedFileURL
        guard fileURL.path.hasPrefix(directory.path + "/"),
              let data = try? Data(contentsOf: fileURL) else {
            throw URLError(.fileDoesNotExist)
        }
        let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": mimeType, "Cache-Control": "no-store"])!
        return (response, data)
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        do {
            guard let url = urlSchemeTask.request.url else { throw URLError(.badURL) }
            let (response, data) = try response(for: url)
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}

/// The Studio pane's state in one window: which view is showing and any generation in progress.
@MainActor
@Observable
final class StudioSession {
    struct Generation: Equatable {
        let viewID: UUID
        let isNewView: Bool
        var status = "Starting Codex"
    }

    let library: GeneratedViewLibrary
    let webView: WKWebView
    private(set) var selectedViewID: UUID?
    private(set) var generation: Generation?
    private(set) var lastReply: String?
    var errorMessage: String?
    @ObservationIgnored private var generationTask: Task<Void, Never>?

    init(library: GeneratedViewLibrary) {
        self.library = library
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(GeneratedViewSchemeHandler(rootURL: library.rootURL),
                                          forURLScheme: GeneratedViewLibrary.scheme)
        WebInspector.enableDeveloperExtras(in: configuration)
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isInspectable = true
    }

    var selectedView: GeneratedView? { library.view(withID: selectedViewID) }

    var isGenerating: Bool { generation != nil }

    /// Whether the page area has something to show for the current selection.
    var showsPreview: Bool {
        guard let selectedViewID else { return false }
        return library.hasContent(selectedViewID)
    }

    func select(_ id: UUID?) {
        guard !isGenerating else { return }
        selectedViewID = id
        lastReply = nil
        errorMessage = nil
        reloadPreview()
    }

    func delete(_ id: UUID) {
        guard generation?.viewID != id else { return }
        library.delete(id)
        if selectedViewID == id { select(nil) }
    }

    /// Builds a new view, or changes the selected one.
    func submit(_ request: String, model: String?) {
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isGenerating else { return }

        let existing = selectedView
        let viewID = existing?.id ?? UUID()
        let directory = library.directory(for: viewID)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        errorMessage = nil
        lastReply = nil
        generation = Generation(viewID: viewID, isNewView: existing == nil)
        let prompt = StudioPrompt.make(request: request, previousRequests: existing?.prompts ?? [])

        generationTask = Task {
            do {
                for try await event in Codex.run(prompt: prompt, in: directory, model: model) {
                    handle(event, for: viewID)
                }
                finishGeneration(viewID: viewID, request: request, existing: existing)
            } catch {
                failGeneration(viewID: viewID, existing: existing, error: error)
            }
        }
    }

    func cancel() {
        generationTask?.cancel()
    }

    private func handle(_ event: CodexEvent, for viewID: UUID) {
        switch event {
        case .progress(let status):
            generation?.status = status
        case .message(let text):
            lastReply = text
        case .filesChanged:
            // Show the work as it lands instead of waiting for the whole turn.
            guard library.hasContent(viewID) else { return }
            selectedViewID = viewID
            reloadPreview()
        }
    }

    private func finishGeneration(viewID: UUID, request: String, existing: GeneratedView?) {
        generation = nil
        guard library.hasContent(viewID) else {
            errorMessage = "Codex finished without creating a view."
            return
        }
        var view = existing ?? GeneratedView(title: "", prompts: [])
        view.id = viewID
        view.title = library.pageTitle(for: viewID) ?? Self.fallbackTitle(for: request)
        view.prompts.append(request)
        view.updatedAt = Date()
        library.save(view)
        selectedViewID = viewID
        reloadPreview()
    }

    private func failGeneration(viewID: UUID, existing: GeneratedView?, error: Error) {
        generation = nil
        if existing == nil, !library.hasContent(viewID) {
            try? FileManager.default.removeItem(at: library.directory(for: viewID))
        }
        errorMessage = Task.isCancelled || error is CancellationError ? nil : error.localizedDescription
        reloadPreview()
    }

    private func reloadPreview() {
        guard let selectedViewID, library.hasContent(selectedViewID) else { return }
        webView.load(URLRequest(url: library.url(for: selectedViewID), cachePolicy: .reloadIgnoringLocalCacheData))
    }

    private static func fallbackTitle(for request: String) -> String {
        let words = request.split(separator: " ").prefix(5).joined(separator: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

enum StudioPrompt {
    static func make(request: String, previousRequests: [String]) -> String {
        var prompt = """
        You build small, self-contained web apps that appear in a side panel of a macOS web browser.
        The panel is usually about 400 points wide but can be resized, so the layout must work from 320 points up.

        Rules:
        - Work only in the current directory. The app's entry point is index.html.
        - Keep everything in index.html with inline <style> and <script>. Load nothing from the network:
          no CDNs, web fonts, remote images, or API calls.
        - Save the user's data in localStorage so it survives reloads.
        - Set a short, descriptive <title> of two to four words.
        - Design: clean and minimal, in the spirit of a native macOS app. Use the system font stack
          (-apple-system, BlinkMacSystemFont, sans-serif), generous spacing, subtle borders, and rounded corners.
          Support light and dark mode with prefers-color-scheme. Use one restrained accent color.
        - Make it keyboard-friendly and accessible, with labeled controls and visible focus states.
        - Don't ask questions. Make sensible choices and finish the app.
        - When you're done, reply with one short sentence describing what you built or changed.

        """
        if previousRequests.isEmpty {
            prompt += "Build this:\n\(request)\n"
        } else {
            prompt += """
            index.html already contains the app, built from these earlier requests:
            \(previousRequests.map { "- \($0)" }.joined(separator: "\n"))

            Update it for this request, and keep existing localStorage data readable:
            \(request)

            """
        }
        return prompt
    }
}
