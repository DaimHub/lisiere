import XCTest
@testable import Browser

@MainActor
final class StoreFileTests: XCTestCase {
    func testInvalidBookmarksCannotBeOverwrittenByLaterEdits() {
        let suite = "io.github.daimhub.lisiere.tests.bookmarks.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = Data("invalid bookmarks".utf8)
        defaults.set(original, forKey: "bookmarks")
        let store = BookmarkStore(defaults: defaults)
        store.add(title: "Temporary", url: URL(string: "https://example.test")!)
        XCTAssertEqual(store.persistenceFailure?.operation, .decode)
        XCTAssertEqual(defaults.data(forKey: "bookmarks"), original)
    }

    func testDiskFullFailurePreservesPreviousBytesAndIsRetryable() throws {
        let (_, original) = try fixture()
        try original.writeNow(Data("previous".utf8)).get()
        let file = StoreFile(url: original.url, writeData: { _, _ in
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        })
        XCTAssertThrowsError(try file.writeNow(Data("new".utf8)).get())
        XCTAssertEqual(file.lastFailure?.code, NSFileWriteOutOfSpaceError)
        XCTAssertEqual(file.lastFailure?.canRetry, true)
        XCTAssertEqual(file.readNow(), Data("previous".utf8))
    }

    func testDeniedDirectoryWritePreservesExistingFileAndRecovers() throws {
        let (root, file) = try fixture()
        try file.writeNow(Data("previous".utf8)).get()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path) }
        XCTAssertThrowsError(try file.writeNow(Data("latest".utf8)).get())
        XCTAssertEqual(file.readNow(), Data("previous".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try XCTUnwrap(file.retry()).get()
        XCTAssertEqual(file.readNow(), Data("latest".utf8))
    }

    func testEncodingFailureDoesNotReplaceAnUnreadableFileOrItsDiagnosis() throws {
        let (_, file) = try fixture()
        try Data("damaged".utf8).write(to: file.url)
        XCTAssertNil(file.decodeNow(SessionSnapshot.self))
        XCTAssertThrowsError(try file.writeNow(nil).get())
        XCTAssertEqual(file.lastFailure?.operation, .decode)
        XCTAssertEqual(file.readNow(), Data("damaged".utf8))
    }

    private func fixture() throws -> (URL, StoreFile) {
        let root = FileManager.default.temporaryDirectory.appending(path: "Storage-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, StoreFile(url: root.appending(path: "Session.plist")))
    }

    func testFailedWriteIsReportedAndLatestPayloadCanBeRetried() throws {
        let (root, _) = try fixture()
        let parent = root.appending(path: "occupied")
        try Data("sentinel".utf8).write(to: parent)
        let file = StoreFile(url: parent.appending(path: "Session.plist"))
        XCTAssertThrowsError(try file.writeNow(Data("old".utf8)).get())
        XCTAssertThrowsError(try file.writeNow(Data("latest".utf8)).get())
        XCTAssertEqual(file.lastFailure?.operation, .write)
        XCTAssertEqual(try Data(contentsOf: parent), Data("sentinel".utf8))
        try FileManager.default.removeItem(at: parent)
        try XCTUnwrap(file.retry()).get()
        XCTAssertEqual(file.readNow(), Data("latest".utf8))
        XCTAssertNil(file.lastFailure)
    }

    func testMalformedDataCannotBeOverwrittenByAnEmptyFallback() throws {
        let (_, file) = try fixture()
        let original = Data("damaged session".utf8)
        try original.write(to: file.url)
        XCTAssertNil(file.decodeNow(SessionSnapshot.self))
        XCTAssertEqual(file.lastFailure?.operation, .decode)
        XCTAssertThrowsError(try file.writeNow(PropertyListEncoder.binary.encode(SessionSnapshot())).get())
        file.write { Data("late".utf8) }
        XCTAssertEqual(file.readNow(), original)
        // Restoring a valid file and restarting creates a usable store without changing the format.
        let valid = try PropertyListEncoder.binary.encode(SessionSnapshot())
        try valid.write(to: file.url, options: .atomic)
        let relaunched = StoreFile(url: file.url)
        XCTAssertNotNil(relaunched.decodeNow(SessionSnapshot.self))
        XCTAssertNoThrow(try relaunched.writeNow(valid).get())
    }

    func testUnreadablePathIsNotTreatedAsAnAbsentStore() throws {
        let (_, file) = try fixture()
        try FileManager.default.createDirectory(at: file.url, withIntermediateDirectories: true)
        XCTAssertNil(file.decodeNow(SessionSnapshot.self))
        XCTAssertEqual(file.lastFailure?.operation, .read)
        XCTAssertThrowsError(try file.writeNow(Data()).get())
        var directory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path, isDirectory: &directory))
        XCTAssertTrue(directory.boolValue)
    }

    func testFinalWriteSupersedesQueuedWritesAndDeletionBlocksLateCallbacks() throws {
        let (_, file) = try fixture()
        for n in 0..<100 { file.write { Data("\(n)".utf8) } }
        try file.writeNow(Data("final".utf8)).get()
        XCTAssertEqual(file.readNow(), Data("final".utf8))
        file.disableWrites()
        try FileManager.default.removeItem(at: file.url)
        file.write { Data("late".utf8) }
        file.writeNow(Data("later".utf8))
        XCTAssertNil(file.readNow())
    }

    func testSessionLoadFailurePreservesOriginalEvenOnQuit() throws {
        let (_, file) = try fixture()
        let bytes = Data("bad plist".utf8)
        try bytes.write(to: file.url)
        let session = SessionStore(file: file)
        session.saveBeforeQuitting()
        XCTAssertEqual(file.readNow(), bytes)
        XCTAssertEqual(file.lastFailure?.operation, .decode)
    }

    func testFutureSessionVersionAndUnrelatedPlistArePreserved() throws {
        for object: [String: Any] in [["version": 99, "windows": []], ["unrelated": true]] {
            let (_, file) = try fixture()
            let data = try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
            try data.write(to: file.url)
            let session = SessionStore(file: file)
            session.saveBeforeQuitting()
            XCTAssertEqual(file.readNow(), data)
            XCTAssertEqual(file.lastFailure?.operation, .decode)
        }
    }

    func testCorruptHistoryIsPreservedUntilUserExplicitlyClearsAll() async throws {
        let (_, file) = try fixture()
        let bytes = Data("bad history".utf8)
        try bytes.write(to: file.url)
        let history = HistoryStore(file: file)
        await history.waitUntilLoaded()
        history.recordVisit(to: URL(string: "https://example.test")!, title: "Temporary")
        history.saveNow()
        XCTAssertEqual(file.readNow(), bytes)
        history.clear(.all)
        history.saveNow()
        XCTAssertEqual(file.decodeNow([HistoryVisit].self), [])
        XCTAssertNil(file.lastFailure)
    }
}
