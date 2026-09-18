import Core
import XCTest
@testable import WhisperClipboard

/// KeychainStore tests. The XCTest host may run without keychain access (no
/// signed host app / no login keychain in CI), so the round-trip test probes
/// availability first and skips gracefully. The wrapper's constants and the
/// empty-value delete semantics are always verified.
final class KeychainStoreTests: XCTestCase {
    private let testStore = KeychainStore(account: "api-key-test-\(UUID().uuidString)")

    override func tearDown() {
        try? testStore.delete()
        super.tearDown()
    }


    /// Whether the test host can actually read/write the keychain. A save of a
    /// probe value that succeeds (and reads back) means access is available.
    private func keychainIsAvailable() -> Bool {
        let probe = "wc-probe-\(UUID().uuidString)"
        do {
            try testStore.save(probe)
            let read = try testStore.read()
            try testStore.delete()
            return read == probe
        } catch {
            return false
        }
    }

    func testServiceAndAccountConstants() {
        XCTAssertEqual(KeychainStore.service, "nl.nielscroiset.whisperclipboard")
        XCTAssertEqual(KeychainStore.account, "anthropic-api-key")
    }

    func testRoundTripWhenAvailable() throws {
        try XCTSkipUnless(keychainIsAvailable(), "Keychain not available on this test host")

        try testStore.save("sk-ant-round-trip")
        XCTAssertEqual(try testStore.read(), "sk-ant-round-trip")
        XCTAssertTrue(testStore.hasValue())

        // Saving replaces (update path).
        try testStore.save("sk-ant-replaced")
        XCTAssertEqual(try testStore.read(), "sk-ant-replaced")

        try testStore.delete()
        XCTAssertNil(try testStore.read())
        XCTAssertFalse(testStore.hasValue())
    }

    func testSavingBlankDeletesWhenAvailable() throws {
        try XCTSkipUnless(keychainIsAvailable(), "Keychain not available on this test host")

        try testStore.save("something")
        try testStore.save("   ") // blank → delete
        XCTAssertNil(try testStore.read())
    }

    func testDeleteOfMissingIsNoThrow() {
        // Deleting a non-existent item must not throw (errSecItemNotFound is OK),
        // regardless of keychain availability for writes.
        XCTAssertNoThrow(try testStore.delete())
    }
}
