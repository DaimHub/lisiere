import Foundation
import Observation
import Security
import WebKit

/// The HTTPS host and port a password belongs to. Passwords only fill on exactly the same origin, so one saved on
/// accounts.example.com isn't offered on example.com, and none are saved or filled on plain HTTP.
struct PasswordOrigin: Hashable, Comparable, CustomStringConvertible, Sendable {
    let host: String
    let port: Int

    init?(host: String, port: Int = 443) {
        let host = host.lowercased()
        guard !host.isEmpty, (1...65535).contains(port) else { return nil }
        self.host = host
        self.port = port
    }

    init?(url: URL?) {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host() else { return nil }
        self.init(host: host, port: url.port ?? 443)
    }

    /// WebKit reports port 0 for the scheme's default port.
    @MainActor
    init?(_ origin: WKSecurityOrigin) {
        guard origin.protocol.lowercased() == "https" else { return nil }
        self.init(host: origin.host, port: origin.port == 0 ? 443 : origin.port)
    }

    /// As a page's `location.origin` reads it.
    var description: String {
        port == 443 ? "https://\(host)" : "https://\(host):\(port)"
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.host, lhs.port) < (rhs.host, rhs.port)
    }
}

/// A saved sign-in, without its password, which stays in the keychain until it's needed.
struct SavedPassword: Identifiable, Hashable, Sendable {
    let origin: PasswordOrigin
    /// Empty for sites that only ask for a password.
    let username: String

    var id: String { "\(origin) \(username)" }
}

protocol PasswordStorage: AnyObject, Sendable {
    func savedPasswords() async throws -> [SavedPassword]
    func password(for account: SavedPassword) async throws -> String?
    func save(_ password: String, for account: SavedPassword) async throws
    func remove(_ account: SavedPassword) async throws
    func removeAll() async throws
}

extension PasswordStorage {
    func removeAll() async throws {
        for account in try await savedPasswords() { try await remove(account) }
    }
}

/// Serializes blocking Security calls across profiles without occupying the UI's actor.
@globalActor
actor KeychainActor {
    static let shared = KeychainActor()
}

enum PasswordStorageError: Error {
    case keychain(OSStatus)
}

/// Keeps passwords as internet password items in the login keychain, which only this app can read without asking.
/// The data protection keychain would need a provisioning profile in every build.
@KeychainActor
final class KeychainPasswordStorage: PasswordStorage {
    /// Marks the items this app saves, so it never lists or reads another app's.
    private let itemDescription: String
    private let securityDomain: String

    nonisolated init(profileID: UUID? = nil,
                     namespace: String = Bundle.main.bundleIdentifier ?? "io.github.daimhub.lisiere",
                     legacyInitialDomain: Bool = Bundle.main.bundleIdentifier == "io.github.daimhub.lisiere") {
        // Security domain participates in Keychain's unique key; description alone does not.
        itemDescription = "\(namespace) website password"
        securityDomain = profileID.map { "\(namespace).profile.\($0)" }
            ?? (legacyInitialDomain ? "" : "\(namespace).initial")
    }

    private func query(for origin: PasswordOrigin? = nil, username: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecAttrDescription as String: itemDescription,
            kSecAttrSecurityDomain as String: securityDomain,
        ]
        if let origin {
            query[kSecAttrServer as String] = origin.host
            query[kSecAttrPort as String] = origin.port
        }
        if let username { query[kSecAttrAccount as String] = username }
        return query
    }

    func savedPasswords() throws -> [SavedPassword] {
        var query = query()
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw PasswordStorageError.keychain(status) }
        return (result as? [[String: Any]] ?? []).compactMap { item in
            guard let host = item[kSecAttrServer as String] as? String,
                  let origin = PasswordOrigin(host: host, port: item[kSecAttrPort as String] as? Int ?? 443)
            else { return nil }
            return SavedPassword(origin: origin, username: item[kSecAttrAccount as String] as? String ?? "")
        }
    }

    func password(for account: SavedPassword) throws -> String? {
        var query = query(for: account.origin, username: account.username)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw PasswordStorageError.keychain(status) }
        return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }

    func save(_ password: String, for account: SavedPassword) throws {
        let query = query(for: account.origin, username: account.username)
        let data = Data(password.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = account.origin.host
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw PasswordStorageError.keychain(status) }
    }

    func remove(_ account: SavedPassword) throws {
        let status = SecItemDelete(query(for: account.origin, username: account.username) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PasswordStorageError.keychain(status) }
    }

    func removeAll() throws {
        for account in try savedPasswords() { try remove(account) }
    }

}

/// Saves the passwords the user signs in with, and fills them back in when asked. Private windows have none.
@MainActor
@Observable
final class PasswordManager {
    static let shared = PasswordManager(storage: KeychainPasswordStorage(), defaults: .standard)
    static let offersToSaveKey = "offersToSavePasswords"
    private static let neverSaveKey = "neverSavePasswordSites"

    enum Offer: Equatable {
        case save
        /// The site has a different password saved for the same user name.
        case update
    }

    /// Every saved sign-in, by site then user name. Loaded the first time it's needed.
    private(set) var passwords: [SavedPassword] = []
    /// Sites the user asked never to save passwords for, as origins.
    private(set) var neverSaveSites: [String]
    var offersToSave: Bool {
        didSet { defaults?.set(offersToSave, forKey: Self.offersToSaveKey) }
    }
    @ObservationIgnored private let storage: PasswordStorage
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var reloadRevision = 0

    /// Pass `nil` defaults to keep the settings in memory only.
    init(storage: PasswordStorage, defaults: UserDefaults? = nil) {
        self.storage = storage
        self.defaults = defaults
        offersToSave = defaults?.object(forKey: Self.offersToSaveKey) as? Bool ?? true
        neverSaveSites = defaults?.stringArray(forKey: Self.neverSaveKey) ?? []
    }

    func removeAll() async throws {
        try await storage.removeAll()
        reloadRevision += 1
        hasLoaded = true
        passwords = []
    }

    func reload() async {
        reloadRevision += 1
        let revision = reloadRevision
        let saved = (try? await storage.savedPasswords()) ?? []
        guard revision == reloadRevision else { return }
        passwords = saved.sorted {
            ($0.origin, $0.username.localizedLowercase) < ($1.origin, $1.username.localizedLowercase)
        }
        hasLoaded = true
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        if let loading { await loading.value; return }
        let task = Task { await self.reload() }
        loading = task
        await task.value
        loading = nil
    }

    /// The sign-ins saved for exactly this origin.
    func passwords(for origin: PasswordOrigin?) -> [SavedPassword] {
        guard let origin else { return [] }
        return passwords.filter { $0.origin == origin }
    }

    func password(for account: SavedPassword) async -> String? {
        try? await storage.password(for: account)
    }

    /// Whether to offer to save a sign-in: not when saving is off or refused for the site, or the same password is
    /// already saved.
    func offer(for capture: PasswordCapture) async -> Offer? {
        guard offersToSave, !neverSaveSites.contains(capture.origin.description) else { return nil }
        await loadIfNeeded()
        guard offersToSave, !neverSaveSites.contains(capture.origin.description) else { return nil }
        let account = capture.account
        guard passwords(for: capture.origin).contains(account) else { return .save }
        let saved = await password(for: account)
        guard offersToSave, !neverSaveSites.contains(capture.origin.description) else { return nil }
        return saved == capture.password ? nil : .update
    }

    func save(_ capture: PasswordCapture) async throws {
        try await storage.save(capture.password, for: capture.account)
        await reload()
    }

    func remove(_ account: SavedPassword) async {
        try? await storage.remove(account)
        await reload()
    }

    func neverSave(on origin: PasswordOrigin) {
        guard !neverSaveSites.contains(origin.description) else { return }
        neverSaveSites.append(origin.description)
        neverSaveSites.sort()
        defaults?.set(neverSaveSites, forKey: Self.neverSaveKey)
    }

    func allowSaving(on site: String) {
        neverSaveSites.removeAll { $0 == site }
        defaults?.set(neverSaveSites, forKey: Self.neverSaveKey)
    }
}
