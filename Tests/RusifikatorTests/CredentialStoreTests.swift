import Foundation
import Security
import XCTest
@testable import Rusifikator

final class CredentialStoreTests: XCTestCase {
    private var store: KeychainCredentialStore!

    override func setUpWithError() throws {
        let suffix = UUID().uuidString
        store = KeychainCredentialStore(
            service: "dev.gotacat.Rusifikator.tests.\(suffix)",
            apiKeyAccount: "provider-api-key-\(suffix)",
            originAccount: "provider-origin-\(suffix)"
        )
        try store.deleteAPIKey()
    }

    override func tearDownWithError() throws {
        try store.deleteAPIKey()
        store = nil
    }

    func testKeychainCreatesReadsUpdatesAndDeletesKey() throws {
        let providerURL = try XCTUnwrap(URL(string: "https://liteapi.gotacat.dev/v1"))

        XCTAssertNil(try store.apiKey(for: providerURL))

        try store.saveAPIKey("first-secret", for: providerURL)
        XCTAssertEqual(try store.apiKey(for: providerURL), "first-secret")

        try store.saveAPIKey("updated-secret", for: providerURL)
        XCTAssertEqual(try store.apiKey(for: providerURL), "updated-secret")

        try store.deleteAPIKey()
        XCTAssertNil(try store.apiKey(for: providerURL))
    }

    func testDifferentOriginCannotReadSavedKey() throws {
        let trustedURL = try XCTUnwrap(URL(string: "https://liteapi.gotacat.dev/v1"))
        let substitutedURL = try XCTUnwrap(URL(string: "https://attacker.example/v1"))
        try store.saveAPIKey("must-not-leak", for: trustedURL)

        XCTAssertThrowsError(try store.apiKey(for: substitutedURL)) { error in
            XCTAssertEqual(error as? CredentialStoreError, .providerOriginMismatch)
            XCTAssertFalse(error.localizedDescription.contains("must-not-leak"))
        }
    }

    func testPathChangesWithinSameOriginKeepKeyAvailable() throws {
        let savedURL = try XCTUnwrap(URL(string: "https://liteapi.gotacat.dev/"))
        let changedPathURL = try XCTUnwrap(URL(string: "https://liteapi.gotacat.dev/v1/chat/completions"))
        try store.saveAPIKey("same-origin-secret", for: savedURL)

        XCTAssertEqual(try store.apiKey(for: changedPathURL), "same-origin-secret")
    }

    func testNonHTTPSProviderIsRejectedWithoutExposingSecret() throws {
        let providerURL = try XCTUnwrap(URL(string: "http://liteapi.gotacat.dev/"))

        XCTAssertThrowsError(try store.saveAPIKey("private-value", for: providerURL)) { error in
            XCTAssertEqual(error as? CredentialStoreError, .invalidProviderOrigin)
            XCTAssertFalse(error.localizedDescription.contains("private-value"))
        }
    }
}
