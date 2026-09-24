import AppKit
import Foundation
import LinkPresentation
import Observation
import SwiftUI

struct Bookmark: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var url: URL

    var displayTitle: String {
        if !title.isEmpty { return title }
        return url.host().map(Bookmark.trimmedHost) ?? url.absoluteString
    }

    static func trimmedHost(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

enum BookmarksBarVisibility: String, CaseIterable, Identifiable {
    case always
    case newTabOnly
    case never

    static let storageKey = "bookmarksBarVisibility"

    var id: Self { self }

    var title: String {
        switch self {
        case .always: "Always Show"
        case .newTabOnly: "Show Only on New Tabs"
        case .never: "Never Show"
        }
    }

    func isVisible(onNewTab isNewTab: Bool) -> Bool {
        switch self {
        case .always: true
        case .newTabOnly: isNewTab
        case .never: false
        }
    }
}

@MainActor
@Observable
final class BookmarkStore {
    private(set) var bookmarks: [Bookmark] = []
    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "bookmarks"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let bookmarks = try? JSONDecoder().decode([Bookmark].self, from: data) {
            self.bookmarks = bookmarks
        }
    }

    func bookmark(for url: URL?) -> Bookmark? {
        guard let url else { return nil }
        return bookmarks.first { $0.url == url }
    }

    func isBookmarked(_ url: URL?) -> Bool {
        bookmark(for: url) != nil
    }

    func add(title: String, url: URL) {
        guard !isBookmarked(url) else { return }
        bookmarks.append(Bookmark(title: title, url: url))
        save()
    }

    /// Adds the page when it isn't bookmarked yet, otherwise removes it.
    func toggle(title: String, url: URL) {
        if let bookmark = bookmark(for: url) {
            remove(bookmark.id)
        } else {
            add(title: title, url: url)
        }
    }

    func remove(_ id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    func rename(_ id: UUID, to title: String) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    func move(_ id: UUID, to destinationIndex: Int) {
        guard let sourceIndex = bookmarks.firstIndex(where: { $0.id == id }),
              bookmarks.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else { return }
        bookmarks.move(fromOffsets: IndexSet(integer: sourceIndex),
                       toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

/// Site icons shared by tabs, the bookmarks bar, and the new tab page.
@MainActor
enum FaviconStore {
    private static var cache: [String: Image] = [:]
    private static var requests: [String: Task<Image?, Never>] = [:]

    static func cachedIcon(for url: URL?) -> Image? {
        url?.host().flatMap { cache[$0] }
    }

    static func icon(for url: URL) async -> Image? {
        guard let host = url.host() else { return nil }
        if let icon = cache[host] { return icon }
        if let request = requests[host] { return await request.value }

        let request = Task { await fetchIcon(for: url) }
        requests[host] = request
        let icon = await request.value
        requests[host] = nil
        if let icon { cache[host] = icon }
        return icon
    }

    private static func fetchIcon(for url: URL) async -> Image? {
        let provider = LPMetadataProvider()
        provider.timeout = 10
        guard let metadata = try? await provider.startFetchingMetadata(for: url),
              let iconProvider = metadata.iconProvider,
              let icon = await withCheckedContinuation({ continuation in
                  _ = iconProvider.loadObject(ofClass: NSImage.self) { image, _ in
                      continuation.resume(returning: image as? NSImage)
                  }
              }) else { return nil }
        return Image(nsImage: icon)
    }
}

/// A site icon, falling back to a colored monogram while it loads or when the site has none.
struct SiteIcon: View {
    let url: URL
    var size: CGFloat = 16
    @State private var icon: Image?

    var body: some View {
        Group {
            if let icon = icon ?? FaviconStore.cachedIcon(for: url) {
                icon
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .task(id: url) { icon = await FaviconStore.icon(for: url) }
    }

    private var monogram: some View {
        let host = url.host().map(Bookmark.trimmedHost) ?? "?"
        let hue = Double(host.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % 360) / 360

        return RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Color(hue: hue, saturation: 0.35, brightness: 0.62).gradient)
            .overlay {
                Text(host.prefix(1).uppercased())
                    .font(.system(size: size * 0.56, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
    }
}
