import Foundation
import Synchronization

/// A store's file in Application Support, read and written on a background queue so saving never blocks the
/// main thread.
final class StoreFile: Sendable {
    let url: URL
    private let queue = DispatchQueue(label: "io.github.daimhub.lisiere.store-file", qos: .utility)
    /// The latest write asked for, so a write that a newer one overtakes is skipped.
    private let latestWrite = Mutex(0)

    init(url: URL) {
        self.url = url
    }

    static func applicationSupport(named name: String) -> StoreFile {
        StoreFile(url: URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "io.github.daimhub.lisiere")
            .appending(path: name))
    }

    func read() async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async { [url] in continuation.resume(returning: try? Data(contentsOf: url)) }
        }
    }

    /// Reads right away, for state the app needs before it shows anything.
    func readNow() -> Data? {
        queue.sync { try? Data(contentsOf: url) }
    }

    /// Encodes and writes in the background. Pass a closure that captures a copy of the data to save.
    func write(_ encode: @escaping @Sendable () -> Data?) {
        let write = latestWrite.withLock { latest in
            latest += 1
            return latest
        }
        queue.async { [self] in
            guard latestWrite.withLock({ $0 == write }), let data = encode() else { return }
            save(data)
        }
    }

    /// Writes before returning, for when the app is quitting. Writes still waiting in the background are skipped.
    func writeNow(_ data: Data?) {
        latestWrite.withLock { $0 += 1 }
        guard let data else { return }
        queue.sync { save(data) }
    }

    private func save(_ data: Data) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
