import Foundation
import XCTest
@testable import Rusifikator

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testCheckUsesDraftsWithoutSavingThem() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = MemoryCredentialStore()
        let checker = RecordingConnectionChecker()
        let model = SettingsViewModel(
            store: SettingsStore(defaults: defaults),
            credentials: credentials,
            connectionChecker: checker,
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )

        model.draftProviderURL = "https://draft.example/v1"
        model.draftModel = "draft/model"
        model.draftAPIKey = "draft-secret"
        model.checkConnection()

        await waitForCheckToFinish(model)
        let call = await checker.recordedCall()
        XCTAssertEqual(call?.url.absoluteString, "https://draft.example/v1")
        XCTAssertEqual(call?.model, "draft/model")
        XCTAssertEqual(call?.apiKey, "draft-secret")
        XCTAssertEqual(model.connectionState, .success)

        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.providerURLString, SettingsStore.defaultProviderURLString)
        XCTAssertEqual(restored.model, SettingsStore.defaultModel)
        XCTAssertNil(try credentials.apiKey(for: URL(string: "https://draft.example")!))
    }

    func testSavePersistsDraftsAndKeyForMatchingOrigin() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = MemoryCredentialStore()
        let model = SettingsViewModel(
            store: SettingsStore(defaults: defaults),
            credentials: credentials,
            connectionChecker: RecordingConnectionChecker(),
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )

        model.draftProviderURL = "https://saved.example/v1"
        model.draftModel = "saved/model"
        model.draftAPIKey = "saved-secret"
        model.save()

        XCTAssertEqual(model.saveState, .success)
        XCTAssertEqual(SettingsStore(defaults: defaults).providerURLString, "https://saved.example/v1")
        XCTAssertEqual(SettingsStore(defaults: defaults).model, "saved/model")
        XCTAssertEqual(
            try credentials.apiKey(for: URL(string: "https://saved.example/other")!),
            "saved-secret"
        )
    }

    func testInitializationLoadsKeyOnlyForStoredOrigin() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        store.providerURLString = "https://current.example/"
        let credentials = MemoryCredentialStore()
        try credentials.saveAPIKey(
            "other-secret",
            for: URL(string: "https://other.example/")!
        )

        let model = SettingsViewModel(
            store: store,
            credentials: credentials,
            connectionChecker: RecordingConnectionChecker(),
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )

        XCTAssertEqual(model.draftAPIKey, "")
        XCTAssertEqual(model.currentAPIKey, "")
        XCTAssertNotEqual(model.loadMessage, "other-secret")
    }

    func testChangingProviderOriginRequiresKeyReentry() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let credentials = MemoryCredentialStore()
        try credentials.saveAPIKey(
            "current-secret",
            for: URL(string: SettingsStore.defaultProviderURLString)!
        )
        let model = SettingsViewModel(
            store: store,
            credentials: credentials,
            connectionChecker: RecordingConnectionChecker(),
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )

        model.draftProviderURL = "https://liteapi.gotacat.dev/v1"
        XCTAssertEqual(model.draftAPIKey, "current-secret")

        model.draftProviderURL = "https://other.example/v1"
        XCTAssertEqual(model.draftAPIKey, "")
        XCTAssertEqual(model.currentAPIKey, "current-secret")
    }

    func testResetClearsCredentialsAndRestoresDraftDefaults() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = MemoryCredentialStore()
        let model = SettingsViewModel(
            store: SettingsStore(defaults: defaults),
            credentials: credentials,
            connectionChecker: RecordingConnectionChecker(),
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )
        model.draftProviderURL = "https://saved.example/"
        model.draftModel = "saved/model"
        model.draftAPIKey = "saved-secret"
        model.save()

        model.reset()

        XCTAssertEqual(model.draftProviderURL, SettingsStore.defaultProviderURLString)
        XCTAssertEqual(model.draftModel, SettingsStore.defaultModel)
        XCTAssertEqual(model.draftAPIKey, "")
        XCTAssertEqual(model.currentAPIKey, "")
        XCTAssertNil(try credentials.apiKey(for: URL(string: "https://saved.example/")!))
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "dev.gotacat.Rusifikator.settings-view-model.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func waitForCheckToFinish(_ model: SettingsViewModel) async {
        for _ in 0..<100 where model.connectionState == .checking {
            await Task.yield()
        }
    }
}

private final class MemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private var key: String?
    private var origin: String?

    func saveAPIKey(_ apiKey: String, for providerURL: URL) throws {
        key = apiKey
        origin = try ProviderOrigin.canonicalString(for: providerURL)
    }

    func apiKey(for providerURL: URL) throws -> String? {
        guard let key else { return nil }
        guard origin == (try ProviderOrigin.canonicalString(for: providerURL)) else {
            throw CredentialStoreError.providerOriginMismatch
        }
        return key
    }

    func deleteAPIKey() throws {
        key = nil
        origin = nil
    }
}

private actor RecordingConnectionChecker: ConnectionChecking {
    struct Call {
        let url: URL
        let model: String
        let apiKey: String
    }

    private var call: Call?

    func checkConnection(baseURL: URL, model: String, apiKey: String) async throws {
        call = Call(url: baseURL, model: model, apiKey: apiKey)
    }

    func recordedCall() -> Call? {
        call
    }
}

@MainActor
private final class FakeSettingsLoginItemService: LoginItemServicing {
    var status: LoginItemController.Status = .disabled

    func register() throws {
        status = .enabled
    }

    func unregister() throws {
        status = .disabled
    }

    func openSystemSettings() {}
}
