import Foundation
import OSLog
import Observation

/// Operational events only: never URLs, paths, page contents, cookies or credentials.
enum BrowserDiagnostics {
    static let storage = Logger(subsystem: Bundle.main.bundleIdentifier ?? "io.github.daimhub.lisiere", category: "storage")
    static let webKit = Logger(subsystem: Bundle.main.bundleIdentifier ?? "io.github.daimhub.lisiere", category: "webkit")
    static let lifecycle = Logger(subsystem: Bundle.main.bundleIdentifier ?? "io.github.daimhub.lisiere", category: "lifecycle")
    static let performance = OSSignposter(logger: lifecycle)
}

/// Owns a thread-safe NotificationCenter registration so deleted profiles do not accumulate observers.
final class NotificationObservation: @unchecked Sendable {
    private let token: NSObjectProtocol
    init(name: Notification.Name, handler: @escaping @Sendable (Notification) -> Void) {
        token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main, using: handler)
    }
    deinit { NotificationCenter.default.removeObserver(token) }
}

@MainActor @Observable
final class PersistenceStatus {
    static let shared = PersistenceStatus()
    private(set) var failures: [URL: StoreFile.Failure] = [:]
    func record(_ failure: StoreFile.Failure?, for url: URL) { failures[url] = failure }
    func firstFailure(for urls: [URL]) -> StoreFile.Failure? {
        urls.compactMap { failures[$0] }.first
    }
}
