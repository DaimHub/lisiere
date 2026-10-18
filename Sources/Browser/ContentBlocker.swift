import Foundation
import Observation
import WebKit

/// Blocks the trackers in `TrackerBlocklist` in every web view. The rule list is compiled off the main thread once,
/// and kept in WebKit's rule list store between launches until the list or the sites where blocking is off change.
@MainActor
@Observable
final class ContentBlocker {
    static let shared = ContentBlocker(defaults: .standard, store: .default())
    static let enabledKey = "blocksTrackers"
    private static let exceptionsKey = "trackerBlockingExceptions"
    private static let signatureKey = "trackerRuleListSignature"
    private let identifier: String

    enum State: Equatable { case unavailable, loading, ready, failed }
    private(set) var state = State.unavailable
    @ObservationIgnored private let ruleSource: @Sendable ([String]) -> String
    private(set) var isEnabled: Bool
    /// Sites where blocking is off, along with their subdomains. Stored without "www.".
    private(set) var exceptions: [String]
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let store: WKContentRuleListStore?
    @ObservationIgnored private var ruleList: WKContentRuleList?
    @ObservationIgnored private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var loadRevision = 0

    /// Pass `nil` defaults to keep the settings in memory only, and a `nil` store to never block anything.
    init(defaults: UserDefaults? = nil, store: WKContentRuleListStore? = nil, identifier: String = "Trackers",
         ruleSource: @escaping @Sendable ([String]) -> String = { TrackerBlocklist.encodedRules(exceptions: $0) }) {
        self.ruleSource = ruleSource
        self.identifier = identifier
        self.defaults = defaults
        self.store = store
        isEnabled = defaults?.object(forKey: Self.enabledKey) as? Bool ?? true
        exceptions = defaults?.stringArray(forKey: Self.exceptionsKey) ?? []
        if store != nil { loadRuleList() }
    }

    func removeCompiledRules() async {
        await waitUntilLoaded()
        if let store { try? await store.removeContentRuleList(forIdentifier: identifier) }
        ruleList = nil
        state = .unavailable
        controllers.allObjects.forEach(apply)
    }

    /// Blocks trackers in a web view's pages from now on, and whenever the rule list changes.
    func attach(_ controller: WKUserContentController) {
        controllers.add(controller)
        apply(to: controller)
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        defaults?.set(isEnabled, forKey: Self.enabledKey)
        controllers.allObjects.forEach(apply)
    }

    /// Whether pages from the host have their trackers blocked.
    func isBlocking(on host: String?) -> Bool {
        isEnabled && state == .ready && exception(covering: host) == nil
    }

    func wantsBlocking(on host: String?) -> Bool { isEnabled && exception(covering: host) == nil }

    func statusText(on host: String) -> String {
        guard wantsBlocking(on: host) else { return "Tracker blocking is off for \(Self.site(host))" }
        switch state {
        case .ready: return "Trackers are blocked on \(Self.site(host))"
        case .loading: return "Tracker protection is loading"
        case .unavailable, .failed: return "Tracker protection is unavailable"
        }
    }

    func waitUntilLoaded() async {
        while let task = loading {
            let revision = loadRevision
            await task.value
            if revision == loadRevision { return }
        }
    }
    func retry() async { await loadRuleList().value }

    func exception(covering host: String?) -> String? {
        guard let host = host.map(Self.site) else { return nil }
        return exceptions.first { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Turns blocking on or off for a host's site, and returns once pages loaded from now on follow the change.
    func setBlocking(_ isBlocking: Bool, on host: String) async {
        let site = Self.site(host)
        if isBlocking {
            exceptions.removeAll { site == $0 || site.hasSuffix("." + $0) }
        } else if exception(covering: site) == nil {
            exceptions.append(site)
            exceptions.sort()
        }
        await saveExceptions()
    }

    func removeException(_ site: String) async {
        exceptions.removeAll { $0 == site }
        await saveExceptions()
    }

    func removeAllExceptions() async {
        exceptions = []
        await saveExceptions()
    }

    private func saveExceptions() async {
        defaults?.set(exceptions, forKey: Self.exceptionsKey)
        await loadRuleList().value
    }

    /// The host without "www.", lowercased, as rules match it.
    static func site(_ host: String) -> String {
        let host = host.lowercased()
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func signature(exceptions: [String]) -> String {
        "\(TrackerBlocklist.version) \(exceptions.sorted().joined(separator: " "))"
    }

    /// Loads one rule list at a time, each for the exceptions as they are when it starts.
    @discardableResult
    private func loadRuleList() -> Task<Void, Never> {
        loadRevision += 1
        let revision = loadRevision
        state = store == nil ? .unavailable : .loading
        let previous = loading
        let task = Task { [weak self] in
            await previous?.value
            await self?.loadLatestRuleList(revision: revision)
        }
        loading = task
        return task
    }

    private func loadLatestRuleList(revision: Int) async {
        guard revision == loadRevision, let store else { return }
        let exceptions = exceptions
        let signature = Self.signature(exceptions: exceptions)
        if ruleList != nil, defaults?.string(forKey: Self.signatureKey) == signature { state = .ready; return }
        if defaults?.string(forKey: Self.signatureKey) == signature,
           let list = try? await store.contentRuleList(forIdentifier: identifier) {
            guard revision == loadRevision else { return }
            install(list)
            return
        }
        let encoded = await Self.encodedRules(exceptions: exceptions, source: ruleSource)
        let list: WKContentRuleList
        do {
            guard let compiled = try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: encoded) else {
                guard revision == loadRevision else { return }
                state = .failed
                BrowserDiagnostics.webKit.error("Tracker rules compilation returned no list")
                return
            }
            list = compiled
        } catch {
            guard revision == loadRevision else { return }
            state = .failed
            BrowserDiagnostics.webKit.error("Tracker rules failed to compile, code \((error as NSError).code)")
            return
        }
        guard revision == loadRevision else { return }
        defaults?.set(signature, forKey: Self.signatureKey)
        install(list)
    }

    @concurrent
    nonisolated private static func encodedRules(exceptions: [String], source: @Sendable ([String]) -> String) async -> String {
        source(exceptions)
    }

    private func install(_ list: WKContentRuleList) {
        ruleList = list
        state = .ready
        controllers.allObjects.forEach(apply)
    }

    private func apply(to controller: WKUserContentController) {
        controller.removeAllContentRuleLists()
        if isEnabled, let ruleList { controller.add(ruleList) }
    }
}
