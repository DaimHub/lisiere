import XCTest
@testable import Browser

@MainActor
final class ContentBlockingTests: XCTestCase {
    private func matches(_ filter: String, _ address: String) throws -> Bool {
        let expression = try NSRegularExpression(pattern: filter)
        return expression.firstMatch(in: address, range: NSRange(address.startIndex..., in: address)) != nil
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "io.github.daimhub.lisiere.tests.content-blocker"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testDomainFiltersMatchTheDomainAndItsSubdomainsOnly() throws {
        let filter = TrackerBlocklist.urlFilter(forDomain: "doubleclick.net")

        XCTAssertTrue(try matches(filter, "https://doubleclick.net/ad.js"))
        XCTAssertTrue(try matches(filter, "https://securepubads.g.doubleclick.net/tag/js/gpt.js"))
        XCTAssertTrue(try matches(filter, "http://ad.doubleclick.net:8080/pixel"))
        XCTAssertFalse(try matches(filter, "https://notdoubleclick.net/"))
        XCTAssertFalse(try matches(filter, "https://doubleclick.net.example.com/"))
        XCTAssertFalse(try matches(filter, "https://example.com/?ref=doubleclick.net/"))
    }

    func testRulesBlockTrackersOnlyWhenAnotherSiteLoadsThem() {
        let rules = TrackerBlocklist.rules()

        XCTAssertEqual(rules.count, Set(TrackerBlocklist.domains).count + TrackerBlocklist.urlFilters.count)
        XCTAssertEqual(Set(rules.map(\.urlFilter)).count, rules.count, "Duplicate rules")
        XCTAssertTrue(rules.allSatisfy { $0.action.type == "block" && $0.trigger.loadType == ["third-party"] })
        XCTAssertTrue(TrackerBlocklist.domains.allSatisfy { $0 == $0.lowercased() && !$0.contains("/") })
    }

    func testExceptionsTurnBlockingOffLast() throws {
        let rules = TrackerBlocklist.rules(exceptions: ["Example.com", "news.site"])
        let last = try XCTUnwrap(rules.last)

        XCTAssertEqual(last.action.type, "ignore-previous-rules")
        XCTAssertEqual(last.trigger.urlFilter, ".*")
        XCTAssertEqual(last.trigger.ifDomain, ["*example.com", "*news.site"])
        XCTAssertEqual(rules.count, TrackerBlocklist.rules().count + 1)
    }

    func testEncodedRulesUseWebKitsKeys() throws {
        let json = TrackerBlocklist.encodedRules(exceptions: ["example.com"])
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: [String: Any]]])

        XCTAssertNotNil(rules.first?["trigger"]?["url-filter"])
        XCTAssertEqual(rules.first?["trigger"]?["load-type"] as? [String], ["third-party"])
        XCTAssertEqual(rules.last?["trigger"]?["if-domain"] as? [String], ["*example.com"])
        XCTAssertNil(rules.first?["trigger"]?["if-domain"])
    }

    func testBlockingCanBeTurnedOffForASiteAndItsSubdomains() async {
        let defaults = makeDefaults()
        let blocker = ContentBlocker(defaults: defaults)
        XCTAssertTrue(blocker.isEnabled)
        XCTAssertTrue(blocker.isBlocking(on: "www.example.com"))

        await blocker.setBlocking(false, on: "www.Example.com")

        XCTAssertEqual(blocker.exceptions, ["example.com"])
        XCTAssertFalse(blocker.isBlocking(on: "example.com"))
        XCTAssertFalse(blocker.isBlocking(on: "news.example.com"))
        XCTAssertTrue(blocker.isBlocking(on: "example.org"))
        XCTAssertTrue(blocker.isBlocking(on: "notexample.com"))

        let relaunched = ContentBlocker(defaults: defaults)
        XCTAssertEqual(relaunched.exceptions, ["example.com"])

        await relaunched.setBlocking(true, on: "news.example.com")
        XCTAssertTrue(relaunched.exceptions.isEmpty)
    }

    func testTurningBlockingOffEverywhere() {
        let defaults = makeDefaults()
        let blocker = ContentBlocker(defaults: defaults)

        blocker.setEnabled(false)

        XCTAssertFalse(blocker.isBlocking(on: "example.com"))
        XCTAssertFalse(ContentBlocker(defaults: defaults).isEnabled)
    }
}

private extension TrackerBlocklist.Rule {
    var urlFilter: String { trigger.urlFilter }
}
