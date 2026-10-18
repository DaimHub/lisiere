import Foundation
import Synchronization

/// Serial, atomic persistence. A failed read/decode locks writes for this instance so an empty fallback
/// never overwrites unreadable user data. Restarting after restoring the file permits normal loading.
final class StoreFile: @unchecked Sendable {
    struct Failure: Error, Sendable, Equatable {
        enum Operation: String, Sendable { case read, decode, encode, write }
        let operation: Operation
        let code: Int
        let store: String
        var message: String {
            switch operation {
            case .read, .decode:
                "Saved \(store) could not be read. The original file is preserved. Restore the file and reopen Lisière before saving changes to it."
            case .encode, .write:
                "Changes to \(store) could not be saved. Keep Lisière open, check available storage and access, then retry."
            }
        }
        var canRetry: Bool { operation == .encode || operation == .write }
    }

    let url: URL
    private let queue = DispatchQueue(label: "io.github.daimhub.lisiere.store-file", qos: .utility)
    private let latestWrite = Mutex(0)
    private let writesDisabled = Mutex(false)
    private let failureState = Mutex<Failure?>(nil)
    // These two fields are confined to queue. All other mutable state uses Mutex.
    private var protectsUnreadableData = false
    private var pendingData: Data?
    private let writeData: @Sendable (Data, URL) throws -> Void
    var lastFailure: Failure? { failureState.withLock { $0 } }

    init(url: URL, writeData: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.url = url
        self.writeData = writeData
    }

    static func applicationSupport(named name: String) -> StoreFile {
        StoreFile(url: URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "io.github.daimhub.lisiere").appending(path: name))
    }

    func read() async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.readOnQueue()) }
        }
    }
    func readNow() -> Data? { queue.sync { readOnQueue() } }

    func decode<T: Decodable & Sendable>(_ type: T.Type) async -> T? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.decodeOnQueue(type)) }
        }
    }
    func decodeNow<T: Decodable & Sendable>(_ type: T.Type) -> T? { queue.sync { decodeOnQueue(type) } }

    private func readOnQueue() -> Data? {
        do { return try Data(contentsOf: url) }
        catch {
            let error = error as NSError
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
            protectsUnreadableData = true
            report(.read, error: error)
            return nil
        }
    }

    private func decodeOnQueue<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = readOnQueue() else { return nil }
        do { return try PropertyListDecoder().decode(type, from: data) }
        catch {
            protectsUnreadableData = true
            report(.decode, error: error as NSError)
            return nil
        }
    }

    func write(_ encode: @escaping @Sendable () -> Data?) {
        let revision = latestWrite.withLock { $0 += 1; return $0 }
        queue.async { [self] in
            guard latestWrite.withLock({ $0 == revision }), !writesDisabled.withLock({ $0 }) else { return }
            guard !protectsUnreadableData else { return }
            guard let data = encode() else { report(.encode); return }
            _ = save(data)
        }
    }

    @discardableResult
    func writeNow(_ data: Data?) -> Result<Void, Failure> {
        latestWrite.withLock { $0 += 1 }
        return queue.sync {
            guard !writesDisabled.withLock({ $0 }) else { return .success(()) }
            guard !protectsUnreadableData else { return .failure(lastFailure ?? report(.read)) }
            guard let data else { return .failure(report(.encode)) }
            return save(data)
        }
    }

    /// Retry only the latest failed payload; an older snapshot cannot overwrite newer changes.
    @discardableResult
    func retry() -> Result<Void, Failure>? {
        queue.sync {
            guard let pendingData else { return nil }
            return save(pendingData)
        }
    }

    /// Called only by the existing explicit Clear All History action, never by a load fallback.
    func allowReplacementAfterExplicitClear() {
        queue.sync { protectsUnreadableData = false }
    }

    func disableWrites() {
        writesDisabled.withLock { $0 = true }
        latestWrite.withLock { $0 += 1 }
        queue.sync { pendingData = nil; failureState.withLock { $0 = nil } }
        Task { @MainActor [weak self, url] in PersistenceStatus.shared.record(self?.lastFailure, for: url) }
    }

    private func save(_ data: Data) -> Result<Void, Failure> {
        guard !writesDisabled.withLock({ $0 }) else { return .success(()) }
        guard !protectsUnreadableData else { return .failure(lastFailure ?? report(.read)) }
        pendingData = data
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writeData(data, url)
            pendingData = nil
            failureState.withLock { $0 = nil }
            Task { @MainActor [weak self, url] in PersistenceStatus.shared.record(self?.lastFailure, for: url) }
            return .success(())
        } catch { return .failure(report(.write, error: error as NSError)) }
    }

    @discardableResult
    private func report(_ operation: Failure.Operation, error: NSError? = nil) -> Failure {
        let name = url.lastPathComponent == "Session.plist" ? "tabs" :
            url.lastPathComponent == "History.plist" ? "history" : "browsing data"
        let failure = Failure(operation: operation, code: error?.code ?? 0, store: name)
        let changed = failureState.withLock { previous in
            defer { previous = failure }
            return previous != failure
        }
        if changed {
            BrowserDiagnostics.storage.error("Store operation failed: \(operation.rawValue, privacy: .public), code \(failure.code)")
            Task { @MainActor [weak self, url] in PersistenceStatus.shared.record(self?.lastFailure, for: url) }
        }
        return failure
    }
}
