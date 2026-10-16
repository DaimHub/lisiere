import AppKit
import CoreServices
import Observation
import WebKit

@MainActor
@Observable
final class DownloadItem: Identifiable {
    enum State {
        case downloading
        case finished
        case failed
        case cancelled
    }

    let id = UUID()
    fileprivate(set) var name: String
    fileprivate(set) var state = State.downloading
    fileprivate(set) var progress = 0.0
    fileprivate(set) var completedBytes: Int64 = 0
    /// Negative while the server hasn't said how large the file is.
    fileprivate(set) var totalBytes: Int64 = -1
    fileprivate(set) var destinationURL: URL?
    @ObservationIgnored fileprivate let download: WKDownload
    @ObservationIgnored fileprivate var progressObservation: NSKeyValueObservation?
    /// Asks whether a download the page started on its own may go ahead, or `nil` when the user started it.
    @ObservationIgnored fileprivate var confirmation: (@MainActor () async -> Bool)?
    /// The window the save panel opens on, when Settings ▸ Downloads asks where to save each file.
    @ObservationIgnored fileprivate weak var window: NSWindow?

    fileprivate init(download: WKDownload) {
        self.download = download
        name = download.originalRequest?.url?.lastPathComponent ?? "Download"
    }
}

/// Downloads from the windows of one profile, saved to the Downloads folder or where the user chooses.
@MainActor
@Observable
final class DownloadManager: NSObject, WKDownloadDelegate {
    // Separate profile lists still write to the same user-selected filesystem. Coordinate names only,
    // so simultaneous downloads in different profiles cannot reserve the same not-yet-created file.
    private static let managers = NSHashTable<DownloadManager>.weakObjects()
    private(set) var items: [DownloadItem] = []
    @ObservationIgnored let directory: URL

    @ObservationIgnored let preferences: ProfilePreferences

    init(directory: URL = .downloadsDirectory, preferences: ProfilePreferences? = nil) {
        self.directory = directory
        self.preferences = preferences ?? ProfilePreferences(defaults: .standard)
        super.init()
        Self.managers.add(self)
    }

    func releaseFinishedDownloads() {
        items.removeAll { $0.state != .downloading }
    }

    var isDownloading: Bool {
        items.contains { $0.state == .downloading }
    }

    /// Combined progress of the downloads still running.
    var progress: Double {
        let running = items.filter { $0.state == .downloading }
        guard !running.isEmpty else { return 0 }
        return running.map(\.progress).reduce(0, +) / Double(running.count)
    }

    /// Pass a confirmation for a download the user didn't start. It's asked before anything is saved,
    /// and the download disappears if it's refused.
    func track(_ download: WKDownload, in window: NSWindow? = nil,
               confirmation: (@MainActor () async -> Bool)? = nil) {
        let item = DownloadItem(download: download)
        item.confirmation = confirmation
        item.window = window
        download.delegate = self
        item.progressObservation = download.progress.observe(\.fractionCompleted) { [weak item] progress, _ in
            let (fraction, completed, total) = (progress.fractionCompleted, progress.completedUnitCount,
                                                progress.totalUnitCount)
            Task { @MainActor [item] in
                item?.progress = fraction
                item?.completedBytes = completed
                item?.totalBytes = total
            }
        }
        items.insert(item, at: 0)
    }

    func cancel(_ item: DownloadItem) {
        guard item.state == .downloading else { return }
        item.state = .cancelled
        let partialFile = item.destinationURL
        item.download.cancel { _ in
            partialFile.map { try? FileManager.default.removeItem(at: $0) }
        }
    }

    func open(_ item: DownloadItem) {
        guard item.state == .finished, let url = item.destinationURL else { return }
        NSWorkspace.shared.open(url)
    }

    func reveal(_ item: DownloadItem) {
        guard let url = item.destinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func clearFinished() {
        items.removeAll { $0.state != .downloading }
    }

    /// A file in `directory` named after `filename` that isn't taken yet, numbered like Finder does: "file 2.pdf".
    nonisolated static func uniqueURL(for filename: String, in directory: URL,
                                      isTaken: (URL) -> Bool) -> URL {
        // Keep only the last path component so a name can't point outside the folder.
        let name = (filename as NSString).lastPathComponent
        let safeName = name.isEmpty || name == "." || name == ".." ? "Download" : name
        let base = (safeName as NSString).deletingPathExtension
        let pathExtension = (safeName as NSString).pathExtension

        var candidate = directory.appending(path: safeName)
        var number = 2
        while isTaken(candidate) {
            let numbered = pathExtension.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(pathExtension)"
            candidate = directory.appending(path: numbered)
            number += 1
        }
        return candidate
    }

    private func item(for download: WKDownload) -> DownloadItem? {
        items.first { $0.download === download }
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        guard let item = item(for: download), item.state == .downloading else { return nil }
        if let confirmation = item.confirmation {
            item.confirmation = nil
            guard await confirmation() else {
                items.removeAll { $0 === item }
                return nil
            }
            // It might have been cancelled while the user was asked.
            guard item.state == .downloading else { return nil }
        }
        if preferences.asksWhereToSave {
            return await chooseDestination(for: item, suggestedFilename: suggestedFilename)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Downloads that are still running haven't necessarily created their files yet.
        let reserved = Set(Self.managers.allObjects.flatMap { manager in
            manager.items.filter { $0.state == .downloading }.compactMap(\.destinationURL)
        })
        let url = Self.uniqueURL(for: suggestedFilename, in: directory) {
            reserved.contains($0) || FileManager.default.fileExists(atPath: $0.path)
        }
        item.name = url.lastPathComponent
        item.destinationURL = url
        return url
    }

    /// Asks where to save the file. Cancelling the panel cancels the download.
    private func chooseDestination(for item: DownloadItem, suggestedFilename: String) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (suggestedFilename as NSString).lastPathComponent
        panel.directoryURL = directory
        panel.canCreateDirectories = true
        let response = if let window = item.window {
            await panel.beginSheetModal(for: window)
        } else {
            await panel.begin()
        }
        guard response == .OK, let url = panel.url, item.state == .downloading else {
            items.removeAll { $0 === item }
            return nil
        }
        // The panel already asked about replacing an existing file.
        try? FileManager.default.removeItem(at: url)
        item.name = url.lastPathComponent
        item.destinationURL = url
        return url
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let item = item(for: download) else { return }
        item.state = .finished
        item.progress = 1
        if let url = item.destinationURL {
            quarantine(url, from: download.originalRequest?.url)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let item = item(for: download), item.state == .downloading else { return }
        item.state = .failed
        // Without resume support, a partial file is of no use.
        if let url = item.destinationURL { try? FileManager.default.removeItem(at: url) }
    }

    /// Marks the file as downloaded from the web, so Gatekeeper checks it before it's opened.
    private func quarantine(_ url: URL, from sourceURL: URL?) {
        var properties: [String: Any] = [
            kLSQuarantineAgentNameKey as String: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") ?? "Lisière",
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
        ]
        if let sourceURL { properties[kLSQuarantineDataURLKey as String] = sourceURL }
        var values = URLResourceValues()
        values.quarantineProperties = properties
        var url = url
        try? url.setResourceValues(values)
    }
}
