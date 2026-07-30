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

    func testSavingEmptyDraftKeepsExistingKeyForOriginalOrigin() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let credentials = MemoryCredentialStore()
        let originalURL = URL(string: SettingsStore.defaultProviderURLString)!
        try credentials.saveAPIKey("existing-secret", for: originalURL)
        let model = SettingsViewModel(
            store: store,
            credentials: credentials,
            connectionChecker: RecordingConnectionChecker(),
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )

        model.draftProviderURL = "https://other.example/v1"
        XCTAssertEqual(model.draftAPIKey, "")
        model.draftProviderURL = SettingsStore.defaultProviderURLString
        XCTAssertEqual(model.draftAPIKey, "")

        model.save()

        XCTAssertEqual(model.saveState, .success)
        XCTAssertEqual(try credentials.apiKey(for: originalURL), "existing-secret")
        XCTAssertEqual(model.currentAPIKey, "existing-secret")
        XCTAssertEqual(model.draftAPIKey, "existing-secret")
    }

    func testSaveFailureDoesNotPersistDraftSettings() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = SettingsViewModel(
            store: SettingsStore(defaults: defaults),
            credentials: FailingSaveCredentialStore(),
            connectionChecker: RecordingConnectionChecker(),
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )
        model.draftProviderURL = "https://draft.example/v1"
        model.draftModel = "draft/model"
        model.draftAPIKey = "draft-secret"

        model.save()

        guard case .failure = model.saveState else {
            return XCTFail("Expected save failure")
        }
        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.providerURLString, SettingsStore.defaultProviderURLString)
        XCTAssertEqual(restored.model, SettingsStore.defaultModel)
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

    func testSubmitReloadsKeyForCurrentStoredOrigin() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let credentials = MemoryCredentialStore()
        try credentials.saveAPIKey(
            "original-secret",
            for: URL(string: SettingsStore.defaultProviderURLString)!
        )
        let model = SettingsViewModel(
            store: store,
            credentials: credentials,
            connectionChecker: RecordingConnectionChecker(),
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )
        let editorClient = RecordingEditorAPIClient()
        let editor = EditorViewModel(apiClient: editorClient, clipboard: ClipboardStub())
        editor.source = "Расшифровка"

        let replacementURL = URL(string: "https://replacement.example/v1")!
        try credentials.saveAPIKey("replacement-secret", for: replacementURL)
        store.providerURLString = replacementURL.absoluteString
        model.submit(editor)

        let submitted = await waitForEditorCallCount(1, client: editorClient)
        XCTAssertTrue(submitted)
        let request = await editorClient.recordedCalls().first
        XCTAssertEqual(request?.baseURL, replacementURL)
        XCTAssertEqual(request?.apiKey, "replacement-secret")
    }

    func testSubmitDoesNotSendKeyBoundToDifferentOrigin() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let credentials = MemoryCredentialStore()
        try credentials.saveAPIKey(
            "must-not-leak",
            for: URL(string: SettingsStore.defaultProviderURLString)!
        )
        let model = SettingsViewModel(
            store: store,
            credentials: credentials,
            connectionChecker: RecordingConnectionChecker(),
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )
        let editorClient = RecordingEditorAPIClient()
        let editor = EditorViewModel(apiClient: editorClient, clipboard: ClipboardStub())
        editor.source = "Расшифровка"

        store.providerURLString = "https://attacker.example/v1"
        model.submit(editor)

        let submitted = await waitForEditorCallCount(1, client: editorClient)
        XCTAssertTrue(submitted)
        let request = await editorClient.recordedCalls().first
        XCTAssertEqual(request?.baseURL.absoluteString, "https://attacker.example/v1")
        XCTAssertEqual(request?.apiKey, "")
        XCTAssertFalse(request?.apiKey.contains("must-not-leak") ?? true)
    }

    func testChangingDraftInvalidatesActiveCheckAndIgnoresLateResult() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let checker = ControlledConnectionChecker()
        let model = SettingsViewModel(
            store: SettingsStore(defaults: defaults),
            credentials: MemoryCredentialStore(),
            connectionChecker: checker,
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )
        model.draftAPIKey = "first-key"
        model.checkConnection()
        let startedInitialCheck = await waitForConnectionCallCount(1, checker: checker)
        XCTAssertTrue(startedInitialCheck)

        model.draftModel = "second/model"

        XCTAssertEqual(model.connectionState, .idle)
        XCTAssertTrue(model.canCheckConnection)

        model.checkConnection()
        let startedReplacement = await waitForConnectionCallCount(2, checker: checker)
        XCTAssertTrue(startedReplacement)
        guard startedReplacement else {
            await checker.succeed(call: 0)
            return
        }

        await checker.succeed(call: 0)
        await settleTasks()
        XCTAssertEqual(model.connectionState, .checking)

        await checker.succeed(call: 1)
        await waitForConnectionState(.success, model: model)
        XCTAssertEqual(model.connectionState, .success)

        model.draftAPIKey = "third-key"
        XCTAssertEqual(model.connectionState, .idle)
    }

    func testEachDraftFieldCancelsActiveConnectionCheck() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let checker = ControlledConnectionChecker()
        let model = SettingsViewModel(
            store: SettingsStore(defaults: defaults),
            credentials: MemoryCredentialStore(),
            connectionChecker: checker,
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )
        model.draftAPIKey = "initial-key"

        model.checkConnection()
        let providerCheckStarted = await waitForConnectionCallCount(1, checker: checker)
        XCTAssertTrue(providerCheckStarted)
        model.draftProviderURL = "https://other.example/v1"
        XCTAssertEqual(model.connectionState, .idle)
        await checker.succeed(call: 0)
        await settleTasks()

        model.checkConnection()
        let modelCheckStarted = await waitForConnectionCallCount(2, checker: checker)
        XCTAssertTrue(modelCheckStarted)
        model.draftModel = "other/model"
        XCTAssertEqual(model.connectionState, .idle)
        await checker.succeed(call: 1)
        await settleTasks()

        model.checkConnection()
        let keyCheckStarted = await waitForConnectionCallCount(3, checker: checker)
        XCTAssertTrue(keyCheckStarted)
        model.draftAPIKey = "replacement-key"
        XCTAssertEqual(model.connectionState, .idle)
        await checker.succeed(call: 2)
        await settleTasks()
    }

    func testFailedConnectionCheckCanBeRetried() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let checker = ControlledConnectionChecker()
        let model = SettingsViewModel(
            store: SettingsStore(defaults: defaults),
            credentials: MemoryCredentialStore(),
            connectionChecker: checker,
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )
        model.draftAPIKey = "key"

        model.checkConnection()
        let startedInitialCheck = await waitForConnectionCallCount(1, checker: checker)
        XCTAssertTrue(startedInitialCheck)
        await checker.fail(call: 0, with: APIError.unauthorized)
        await waitForConnectionState(.failure(APIError.unauthorized.localizedDescription), model: model)

        model.checkConnection()
        let startedRetry = await waitForConnectionCallCount(2, checker: checker)
        XCTAssertTrue(startedRetry)
        await checker.succeed(call: 1)
        await waitForConnectionState(.success, model: model)

        XCTAssertEqual(model.connectionState, .success)
    }

    func testRequiresApprovalIsShownAsEnabledAndCanBeDisabled() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let loginService = FakeSettingsLoginItemService()
        loginService.status = .requiresApproval
        let model = SettingsViewModel(
            store: SettingsStore(defaults: defaults),
            credentials: MemoryCredentialStore(),
            connectionChecker: RecordingConnectionChecker(),
            loginItem: LoginItemController(service: loginService)
        )

        XCTAssertTrue(model.loginItemIsEnabled)
        model.setLoginItemEnabled(false)
        XCTAssertEqual(loginService.status, .disabled)
        XCTAssertFalse(model.loginItemIsEnabled)
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

    private func waitForConnectionCallCount(
        _ expected: Int,
        checker: ControlledConnectionChecker
    ) async -> Bool {
        for _ in 0..<500 {
            if await checker.callCount() == expected {
                return true
            }
            await Task.yield()
        }
        return false
    }

    private func waitForConnectionState(
        _ expected: SettingsViewModel.ConnectionState,
        model: SettingsViewModel
    ) async {
        for _ in 0..<500 {
            if model.connectionState == expected {
                return
            }
            await Task.yield()
        }
        XCTFail("Expected connection state \(expected), got \(model.connectionState)")
    }

    private func waitForEditorCallCount(
        _ expected: Int,
        client: RecordingEditorAPIClient
    ) async -> Bool {
        for _ in 0..<500 {
            if await client.recordedCalls().count == expected {
                return true
            }
            await Task.yield()
        }
        return false
    }

    private func settleTasks() async {
        for _ in 0..<20 {
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

private actor ControlledConnectionChecker: ConnectionChecking {
    private var calls: [(url: URL, model: String, apiKey: String)] = []
    private var continuations: [CheckedContinuation<Void, any Error>] = []

    func checkConnection(baseURL: URL, model: String, apiKey: String) async throws {
        calls.append((baseURL, model, apiKey))
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func callCount() -> Int {
        calls.count
    }

    func succeed(call index: Int) {
        continuations[index].resume()
    }

    func fail(call index: Int, with error: any Error) {
        continuations[index].resume(throwing: error)
    }
}

private actor RecordingEditorAPIClient: EditorAPIClient {
    private var calls: [EditorRequest] = []

    func clean(_ request: EditorRequest) async throws -> String {
        calls.append(request)
        return "Готово"
    }

    func recordedCalls() -> [EditorRequest] {
        calls
    }
}

@MainActor
private struct ClipboardStub: ClipboardService {
    func copy(_ string: String) {}
}

private struct FailingSaveCredentialStore: CredentialStore {
    func saveAPIKey(_ apiKey: String, for providerURL: URL) throws {
        throw APIError.transport
    }

    func apiKey(for providerURL: URL) throws -> String? {
        nil
    }

    func deleteAPIKey() throws {}
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
