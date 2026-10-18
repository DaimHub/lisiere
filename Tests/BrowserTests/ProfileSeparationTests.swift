import AppKit
import WebKit
import Security
import XCTest
@testable import Browser

@MainActor
final class ProfileSeparationTests: XCTestCase {
    func testEmptyAndCopiedProfilesHaveIndependentResources() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ProfileCopy-\(UUID())")
        let suite = "ProfileCopy-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let profiles = ProfileStore(root: root, defaults: defaults, dataStoreFactory: { _ in .nonPersistent() })
        defer {
            for profile in profiles.profiles {
                UserDefaults.standard.removePersistentDomain(forName: ProfileStore.defaultsDomain(for: profile.id))
            }
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let source = try XCTUnwrap(profiles.context(for: BrowserProfile.initialID))
        source.preferences.searchEngine = .kagi
        source.preferences.tabLayout = .vertical
        source.preferences.asksWhereToSave = true
        source.bookmarks.add(title: "Reference", url: URL(string: "https://example.com/reference")!)
        source.sitePermissions.setDecision(true, for: .camera, on: "example.com")
        source.zoomLevels.setLevel(1.5, for: "example.com")
        source.contentBlocker.setEnabled(false)
        let tab = TabSession(url: URL(string: "https://example.com/form"), title: "Source tab",
                             interactionState: Data("must not copy form state".utf8))
        // Pending session data is enough to test the copy without opening a real website.
        let snapshot = SessionSnapshot(windows: [WindowSession(tabs: [tab], selectedIndex: 0)])
        let file = root.appending(path: "Session.plist")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try PropertyListEncoder.binary.encode(snapshot).write(to: file)
        let reloaded = ProfileStore(root: root, defaults: defaults, dataStoreFactory: { _ in .nonPersistent() })
        let copy = try reloaded.create(name: "Work", icon: .briefcase, copying: BrowserProfile.initialID)
        let empty = try reloaded.create(name: "Empty", icon: .leaf)
        defer {
            for profile in [copy, empty] {
                UserDefaults.standard.removePersistentDomain(forName: ProfileStore.defaultsDomain(for: profile.id))
                reloaded.context(for: profile.id)?.prepareForDeletion()
            }
            source.prepareForDeletion()
        }
        let copied = try XCTUnwrap(reloaded.context(for: copy.id))
        let fresh = try XCTUnwrap(reloaded.context(for: empty.id))
        XCTAssertEqual(copied.preferences.searchEngine, .kagi)
        XCTAssertEqual(copied.preferences.tabLayout, .vertical)
        XCTAssertTrue(copied.preferences.asksWhereToSave)
        XCTAssertEqual(copied.bookmarks.bookmarks.first?.title, "Reference")
        XCTAssertFalse(copied.contentBlocker.isEnabled)
        XCTAssertEqual(copied.zoomLevels.level(for: "example.com"), 1.5)
        XCTAssertNil(copied.sitePermissions.decision(for: [.camera], on: "example.com"))
        XCTAssertEqual(copied.session.snapshot.windows.first?.tabs.first?.url, tab.url)
        XCTAssertNil(copied.session.snapshot.windows.first?.tabs.first?.interactionState)
        await copied.history.waitUntilLoaded()
        XCTAssertTrue(copied.history.visits.isEmpty)
        XCTAssertTrue(copied.downloads.items.isEmpty)
        XCTAssertFalse(copied.downloads === source.downloads)
        XCTAssertFalse(copied.passwords === source.passwords)
        XCTAssertFalse(copied.favicons === source.favicons)
        XCTAssertNotEqual(copied.favicons.cache.directory, source.favicons.cache.directory)
        XCTAssertEqual(fresh.preferences.searchEngine, .google)
        XCTAssertEqual(fresh.preferences.tabLayout, .horizontal)
        XCTAssertTrue(fresh.bookmarks.bookmarks.isEmpty)
        XCTAssertTrue(fresh.session.snapshot.windows.isEmpty)
        copied.preferences.searchEngine = .bing
        copied.bookmarks.rename(try XCTUnwrap(copied.bookmarks.bookmarks.first?.id), to: "Independent")
        XCTAssertEqual(source.preferences.searchEngine, .kagi)
        XCTAssertEqual(source.bookmarks.bookmarks.first?.title, "Reference")
        let persisted = ProfileStore(root: root, defaults: defaults)
        XCTAssertEqual(persisted.profile(copy.id)?.icon, .briefcase)
        XCTAssertEqual(persisted.context(for: copy.id)?.preferences.searchEngine, .bing)
        XCTAssertEqual(persisted.context(for: empty.id)?.preferences.searchEngine, .google)
        persisted.context(for: copy.id)?.prepareForDeletion()
        persisted.context(for: empty.id)?.prepareForDeletion()
    }

    func testKeychainSeparatesSameOriginAndUsernameByProfile() async throws {
        let first = KeychainPasswordStorage(profileID: UUID())
        let second = KeychainPasswordStorage(profileID: UUID())
        let account = SavedPassword(origin: PasswordOrigin(host: "profile-fixture.invalid")!, username: "fixture")
        addTeardownBlock { try? await first.remove(account); try? await second.remove(account) }
        try await first.save("synthetic-alpha", for: account)
        let secret1 = try await second.password(for: account)
        XCTAssertNil(secret1)
        try await second.save("synthetic-beta", for: account)
        let secret2 = try await first.password(for: account)
        XCTAssertEqual(secret2, "synthetic-alpha")
        let secret3 = try await second.password(for: account)
        XCTAssertEqual(secret3, "synthetic-beta")
        try await first.remove(account)
        let secret4 = try await first.password(for: account)
        XCTAssertNil(secret4)
        let secret5 = try await second.password(for: account)
        XCTAssertEqual(secret5, "synthetic-beta")
    }

    func testLegacyPasswordWithoutSecurityDomainRemainsReadable() async throws {
        let namespace = "io.github.daimhub.lisiere.tests.\(UUID())"
        let account = SavedPassword(origin: PasswordOrigin(host: "legacy-\(UUID()).invalid")!, username: "fixture")
        let query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecAttrDescription as String: "\(namespace) website password",
            kSecAttrServer as String: account.origin.host, kSecAttrPort as String: 443,
            kSecAttrAccount as String: account.username]
        var item = query
        item[kSecValueData as String] = Data("synthetic-legacy".utf8)
        XCTAssertEqual(SecItemAdd(item as CFDictionary, nil), errSecSuccess)
        defer { SecItemDelete(query as CFDictionary) }
        let secret6 = try await KeychainPasswordStorage(namespace: namespace, legacyInitialDomain: true).password(for: account)
        XCTAssertEqual(secret6, "synthetic-legacy")
        let secret7 = try await KeychainPasswordStorage(profileID: UUID(), namespace: namespace, legacyInitialDomain: true).password(for: account)
        XCTAssertNil(secret7)
    }

    func testSwipeUsesOneHorizontalGestureAndIgnoresVerticalMomentumAndContinuation() {
        var swipe = ProfileSwipeState()
        XCTAssertNil(swipe.consume(dx: -90, dy: 0, phase: .changed, momentum: [], precise: true).direction)
        XCTAssertFalse(swipe.consume(dx: 0, dy: 18, phase: .began, momentum: [], precise: true).handled)
        XCTAssertNil(swipe.consume(dx: -100, dy: 0, phase: .changed, momentum: [], precise: true).direction)
        _ = swipe.consume(dx: 0, dy: 0, phase: .ended, momentum: [], precise: true)
        XCTAssertNil(swipe.consume(dx: -20, dy: 1, phase: .began, momentum: [], precise: true).direction)
        XCTAssertEqual(swipe.consume(dx: -60, dy: 1, phase: .changed, momentum: [], precise: true).direction, 1)
        XCTAssertNil(swipe.consume(dx: -100, dy: 0, phase: .changed, momentum: [], precise: true).direction)
        _ = swipe.consume(dx: 0, dy: 0, phase: .ended, momentum: [], precise: true)
        XCTAssertNil(swipe.consume(dx: 100, dy: 0, phase: [], momentum: .changed, precise: true).direction)
        XCTAssertNil(swipe.consume(dx: 100, dy: 0, phase: .began, momentum: [], precise: false).direction)
        XCTAssertEqual(swipe.consume(dx: 80, dy: 0, phase: .began, momentum: [], precise: true).direction, -1)
    }
}
