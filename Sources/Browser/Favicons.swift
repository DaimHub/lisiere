import AppKit
import Foundation
import SwiftUI
import WebKit

/// An icon a page declares with `<link rel="icon">` or `<link rel="apple-touch-icon">`.
struct FaviconCandidate: Equatable, Sendable {
    let url: URL
    /// Widths from the `sizes` attribute, empty when the page doesn't say.
    let sizes: [Int]
    let isScalable: Bool
    let isTouchIcon: Bool

    init(url: URL, sizes: [Int] = [], isScalable: Bool = false, isTouchIcon: Bool = false) {
        self.url = url
        self.sizes = sizes
        self.isScalable = isScalable
        self.isTouchIcon = isTouchIcon
    }

    /// Reads a `<link>` element's attributes. `mask-icon` is left out because it's a monochrome template.
    init?(rel: String, href: String, sizes: String = "", type: String = "", baseURL: URL) {
        let rels = Set(rel.lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
        let isTouchIcon = !rels.isDisjoint(with: ["apple-touch-icon", "apple-touch-icon-precomposed"])
        let href = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rels.contains("icon") || isTouchIcon, !href.isEmpty,
              let url = URL(string: href, relativeTo: baseURL)?.absoluteURL,
              ["http", "https", "data"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let sizeTokens = sizes.lowercased().split(whereSeparator: \.isWhitespace)
        self.init(url: url,
                  sizes: sizeTokens.compactMap { $0.split(separator: "x").first.flatMap { Int($0) } },
                  isScalable: sizeTokens.contains("any") || type.lowercased() == "image/svg+xml"
                      || url.pathExtension.lowercased() == "svg" || url.absoluteString.hasPrefix("data:image/svg"),
                  isTouchIcon: isTouchIcon)
    }

    /// Scans the `<head>` of a page's HTML for icons, honoring `<base href>`.
    static func candidates(inHTML html: String, baseURL: URL) -> [FaviconCandidate] {
        let head = html.range(of: "</head>", options: .caseInsensitive).map { html[..<$0.lowerBound] } ?? html[...]
        let tag = /<(link|base)\b([^>]*)>/.ignoresCase()
        let attribute = /([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/
        var base = baseURL
        var candidates: [FaviconCandidate] = []
        for match in head.matches(of: tag) {
            var attributes: [String: String] = [:]
            for pair in match.output.2.matches(of: attribute) {
                let value = pair.output.2 ?? pair.output.3 ?? pair.output.4 ?? ""
                attributes[pair.output.1.lowercased()] = String(value).replacing("&amp;", with: "&")
            }
            if match.output.1.lowercased() == "base" {
                if let href = attributes["href"], let url = URL(string: href, relativeTo: baseURL) {
                    base = url.absoluteURL
                }
            } else if let candidate = FaviconCandidate(rel: attributes["rel"] ?? "", href: attributes["href"] ?? "",
                                                       sizes: attributes["sizes"] ?? "",
                                                       type: attributes["type"] ?? "", baseURL: base) {
                candidates.append(candidate)
            }
        }
        return candidates
    }

    /// Icon addresses to try, best first, for a 16–32 pt icon on a 2x display, ending with the site's `/favicon.ico`.
    static func ranked(_ candidates: [FaviconCandidate], pageURL: URL) -> [URL] {
        let sorted = candidates.enumerated().sorted { first, second in
            let (a, b) = (first.element.rank, second.element.rank)
            return (a.tier, a.distance, first.offset) < (b.tier, b.distance, second.offset)
        }
        var urls: [URL] = []
        for url in sorted.map(\.element.url) + [defaultIconURL(for: pageURL)].compactMap({ $0 })
        where !urls.contains(url) {
            urls.append(url)
        }
        return urls
    }

    static func defaultIconURL(for pageURL: URL) -> URL? {
        guard ["http", "https"].contains(pageURL.scheme?.lowercased() ?? "") else { return nil }
        return URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL
    }

    /// Known sizes of at least 32 px come first, closest to 64 px. An SVG beats a raster icon of unknown or small size,
    /// and touch icons, which are usually opaque squares, come last.
    private var rank: (tier: Int, distance: Int) {
        if isTouchIcon { return (4, abs((sizes.max() ?? 180) - 64)) }
        if let size = sizes.filter({ $0 >= 32 }).min(by: { abs($0 - 64) < abs($1 - 64) }) { return (0, abs(size - 64)) }
        if isScalable { return (1, 0) }
        if sizes.isEmpty { return (2, 0) }
        return (3, -(sizes.max() ?? 0))
    }
}

/// Icon files kept in Caches, one per host, so icons show without the network after a relaunch.
struct FaviconCache: Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let source: URL
        let data: Data
    }

    let directory: URL
    var maxAge: Duration = .seconds(7 * 24 * 60 * 60)

    func entry(forHost host: String, now: Date = .now) -> Entry? {
        let file = fileURL(forHost: host)
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date,
              now.timeIntervalSince(modified) < TimeInterval(maxAge.components.seconds),
              let data = try? Data(contentsOf: file) else { return nil }
        return try? PropertyListDecoder().decode(Entry.self, from: data)
    }

    func save(_ entry: Entry, forHost host: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? PropertyListEncoder().encode(entry) else { return }
        try? data.write(to: fileURL(forHost: host), options: .atomic)
    }

    private func fileURL(forHost host: String) -> URL {
        directory.appending(path: host.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? host)
    }
}

/// Site icons shared by tabs, the bookmarks bar, and the new tab page.
@MainActor
enum FaviconStore {
    private struct Icon: Sendable {
        let source: URL
        let image: Image
    }

    static var cache = FaviconCache(directory: URL.cachesDirectory
        .appending(path: Bundle.main.bundleIdentifier ?? "dev.athas.browser")
        .appending(path: "Favicons"))
    private static var icons: [String: Icon] = [:]
    private static var requests: [String: Task<Icon?, Never>] = [:]
    /// When a host's icon couldn't be found, so a slow network doesn't leave it without one for long.
    private static var missingHosts: [String: ContinuousClock.Instant] = [:]
    private static var failedSources: Set<URL> = []

    nonisolated private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    static func cachedIcon(for url: URL?) -> Image? {
        url?.host().flatMap { icons[$0]?.image }
    }

    /// An icon for a site that isn't open, such as a bookmark: the cached one, the site's `/favicon.ico`,
    /// or else the best icon its page declares.
    static func icon(for url: URL) async -> Image? {
        guard let host = url.host() else { return nil }
        if let icon = icons[host] { return icon.image }
        if let missing = missingHosts[host], ContinuousClock.now - missing < .seconds(300) { return nil }

        let icon = await deduplicated(host, host: host) {
            if let icon = await diskIcon(forHost: host, in: cache) { return icon }
            guard let fallback = FaviconCandidate.defaultIconURL(for: url) else { return nil }
            if let icon = await download(fallback, forHost: host, into: cache) { return icon }
            guard let (html, pageURL) = await page(at: url) else { return nil }
            let candidates = FaviconCandidate.candidates(inHTML: html, baseURL: pageURL)
            for source in FaviconCandidate.ranked(candidates, pageURL: pageURL).prefix(4) where source != fallback {
                if let icon = await download(source, forHost: host, into: cache) { return icon }
            }
            return nil
        }
        missingHosts[host] = icon == nil ? .now : nil
        return icon?.image
    }

    /// The best of the icons an open page declares, downloaded only when it isn't the one already cached.
    static func icon(forPage url: URL, candidates: [FaviconCandidate]) async -> Image? {
        guard let host = url.host() else { return nil }
        let sources = FaviconCandidate.ranked(candidates, pageURL: url).filter { !failedSources.contains($0) }.prefix(4)
        guard let best = sources.first else { return nil }
        if let icon = icons[host], icon.source == best { return icon.image }

        let icon = await deduplicated(best.absoluteString, host: host) {
            if let icon = await diskIcon(forHost: host, in: cache), icon.source == best { return icon }
            for source in sources {
                if let icon = await download(source, forHost: host, into: cache) { return icon }
                failedSources.insert(source)
            }
            return nil
        }
        if icon != nil { missingHosts[host] = nil }
        return icon?.image
    }

    /// Reads the icon links of the page a web view shows, in a content world the page's scripts can't reach.
    static func candidates(in webView: WKWebView) async -> [FaviconCandidate] {
        let script = """
            Array.from(document.querySelectorAll('link[rel][href]'), link => ({
                rel: link.rel, href: link.href, sizes: link.getAttribute('sizes') || '', type: link.type
            }))
            """
        guard let pageURL = webView.url,
              let links = try? await webView.evaluateJavaScript(script, contentWorld: .defaultClient) as? [[String: String]]
        else { return [] }
        return links.compactMap {
            FaviconCandidate(rel: $0["rel"] ?? "", href: $0["href"] ?? "", sizes: $0["sizes"] ?? "",
                             type: $0["type"] ?? "", baseURL: pageURL)
        }
    }

    /// Shares one load between everything asking for the same icon, and keeps the result for the host.
    private static func deduplicated(_ key: String, host: String,
                                     _ load: @escaping @MainActor () async -> Icon?) async -> Icon? {
        if let request = requests[key] { return await request.value }
        let request = Task(operation: load)
        requests[key] = request
        let icon = await request.value
        requests[key] = nil
        if let icon { icons[host] = icon }
        return icon
    }

    @concurrent
    nonisolated private static func diskIcon(forHost host: String, in cache: FaviconCache) async -> Icon? {
        guard let entry = cache.entry(forHost: host), let image = image(from: entry.data) else { return nil }
        return Icon(source: entry.source, image: image)
    }

    @concurrent
    nonisolated private static func download(_ source: URL, forHost host: String,
                                             into cache: FaviconCache) async -> Icon? {
        guard let (data, _) = await fetch(source), let image = image(from: data) else { return nil }
        cache.save(FaviconCache.Entry(source: source, data: data), forHost: host)
        return Icon(source: source, image: image)
    }

    @concurrent
    nonisolated private static func page(at url: URL) async -> (String, URL)? {
        guard let (data, pageURL) = await fetch(url) else { return nil }
        return (String(decoding: data, as: UTF8.self), pageURL)
    }

    nonisolated private static func fetch(_ url: URL) async -> (Data, URL)? {
        guard let (data, response) = try? await session.data(from: url), !data.isEmpty,
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true
        else { return nil }
        return (data, response.url ?? url)
    }

    nonisolated private static func image(from data: Data) -> Image? {
        guard let image = NSImage(data: data), image.isValid, image.size.width > 0 else { return nil }
        return Image(nsImage: image)
    }
}
