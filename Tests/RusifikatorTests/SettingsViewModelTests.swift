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
        await model.waitForInitialLoad()

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
        let key = try await credentials.apiKey(for: URL(string: "https://draft.example")!)
        XCTAssertNil(key)
    }

    func testSavePersistsDraftsAndKeyForMatchingOrigin() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = MemoryCredentialStore()
        let model = SettingsViewModel(
            store: SettingsStore(defaults: defaults),
            credentials: credentials,
            connectionChecker: RecordingConnectionChecker(),
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )
        await model.waitForInitialLoad()

        model.draftProviderURL = "https://saved.example/v1"
        model.draftModel = "saved/model"
        model.draftAPIKey = "saved-secret"
        model.draftPartialPreviewEnabled = true
        await model.save()

        XCTAssertEqual(model.saveState, .success)
        XCTAssertEqual(SettingsStore(defaults: defaults).providerURLString, "https://saved.example/v1")
        XCTAssertEqual(SettingsStore(defaults: defaults).model, "saved/model")
        XCTAssertTrue(SettingsStore(defaults: defaults).partialPreviewEnabled)
        let savedKey = try await credentials.apiKey(for: URL(string: "https://saved.example/other")!)
        XCTAssertEqual(savedKey, "saved-secret")
    }

    func testSavingEmptyDraftKeepsExistingKeyForOriginalOrigin() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let credentials = MemoryCredentialStore()
        let originalURL = URL(string: SettingsStore.defaultProviderURLString)!
        try await credentials.saveAPIKey("existing-secret", for: originalURL)
        let model = SettingsViewModel(
            store: store,
            credentials: credentials,
            connectionChecker: RecordingConnectionChecker(),
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )
        await model.waitForInitialLoad()

        model.draftProviderURL = "https://other.example/v1"
        XCTAssertEqual(model.draftAPIKey, "existing-secret")
        model.draftProviderURL = SettingsStore.defaultProviderURLString
        XCTAssertEqual(model.draftAPIKey, "existing-secret")
        model.draftAPIKey = ""

        await model.save()

        XCTAssertEqual(model.saveState, .success)
        let existingKey = try await credentials.apiKey(for: originalURL)
        XCTAssertEqual(existingKey, "existing-secret")
        XCTAssertEqual(model.currentAPIKey, "existing-secret")
        XCTAssertEqual(model.draftAPIKey, "existing-secret")
    }

    func testSaveFailureDoesNotPersistDraftSettings() async {
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

        await model.save()

        guard case .failure = model.saveState else {
            return XCTFail("Expected save failure")
        }
        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.providerURLString, SettingsStore.defaultProviderURLString)
        XCTAssertEqual(restored.model, SettingsStore.defaultModel)
    }

    func testInitializationLoadsKeyOnlyForStoredOrigin() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        store.providerURLString = "https://current.example/"
        let credentials = MemoryCredentialStore()
        try await credentials.saveAPIKey(
            "other-secret",
            for: URL(string: "https://other.example/")!
        )

        let model = SettingsViewModel(
            store: store,
            credentials: credentials,
            connectionChecker: RecordingConnectionChecker(),
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )
        await model.waitForInitialLoad()

        XCTAssertEqual(model.draftAPIKey, "")
        XCTAssertEqual(model.currentAPIKey, "")
        XCTAssertNotEqual(model.loadMessage, "other-secret")
    }

    func testIncrementalProviderURLTypingPreservesKeyBoundToOriginalOrigin() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let credentials = MemoryCredentialStore()
        try await credentials.saveAPIKey(
            "current-secret",
            for: URL(string: SettingsStore.defaultProviderURLString)!
        )
        let model = SettingsViewModel(
            store: store,
            credentials: credentials,
            connectionChecker: RecordingConnectionChecker(),
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )
        await model.waitForInitialLoad()

        model.draftProviderURL = "https://liteapi.gotacat.dev/v1"
        XCTAssertEqual(model.draftAPIKey, "current-secret")

        model.draftProviderURL = "https://other.example"
        XCTAssertEqual(model.draftAPIKey, "current-secret")

        model.draftProviderURL = "https://other.example/v1"
        XCTAssertEqual(model.draftAPIKey, "current-secret")
        XCTAssertEqual(model.currentAPIKey, "current-secret")
    }

    func testCheckRejectsKeyBoundToDifferentProviderOrigin() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let checker = RecordingConnectionChecker()
        let model = SettingsViewModel(
            store: SettingsStore(defaults: defaults),
            credentials: MemoryCredentialStore(),
            connectionChecker: checker,
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )
        await model.waitForInitialLoad()

        model.draftAPIKey = "draft-secret"
        model.draftProviderURL = "https://other.example/v1"
        model.checkConnection()

        XCTAssertEqual(
            model.connectionState,
            .failure(CredentialStoreError.providerOriginMismatch.localizedDescription)
        )
        let call = await checker.recordedCall()
        XCTAssertNil(call)
    }

    func testEditingCarriedKeyDoesNotRebindItToDifferentProviderOrigin() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = MemoryCredentialStore()
        try await credentials.saveAPIKey(
            "original-secret",
            for: URL(string: SettingsStore.defaultProviderURLString)!
        )
        let checker = RecordingConnectionChecker()
        let model = SettingsViewModel(
            store: SettingsStore(defaults: defaults),
            credentials: credentials,
            connectionChecker: checker,
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )
        await model.waitForInitialLoad()

        model.draftProviderURL = "https://other.example/v1"
        model.draftAPIKey += "x"
        model.checkConnection()

        XCTAssertEqual(
            model.connectionState,
            .failure(CredentialStoreError.providerOriginMismatch.localizedDescription)
        )
        let call = await checker.recordedCall()
        XCTAssertNil(call)

        model.draftAPIKey = ""
        model.draftAPIKey = "new-secret"
        model.checkConnection()
        await settleTasks()
        let reboundCall = await checker.recordedCall()
        XCTAssertEqual(reboundCall?.url.absoluteString, "https://other.example/v1")
        XCTAssertEqual(reboundCall?.apiKey, "new-secret")
    }

    func testSaveRejectsKeyBoundToDifferentProviderOrigin() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let model = SettingsViewModel(
            store: store,
            credentials: MemoryCredentialStore(),
            connectionChecker: RecordingConnectionChecker(),
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )
        await model.waitForInitialLoad()

        model.draftAPIKey = "draft-secret"
        model.draftProviderURL = "https://other.example/v1"
        await model.save()

        XCTAssertEqual(
            model.saveState,
            .failure(CredentialStoreError.providerOriginMismatch.localizedDescription)
        )
        XCTAssertEqual(store.providerURLString, SettingsStore.defaultProviderURLString)
    }

    func testSavingEmptyKeyForChangedProviderRejectsOldOriginCredential() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let credentials = MemoryCredentialStore()
        try await credentials.saveAPIKey(
            "existing-secret",
            for: URL(string: SettingsStore.defaultProviderURLString)!
        )
        let model = SettingsViewModel(
            store: store,
            credentials: credentials,
            connectionChecker: RecordingConnectionChecker(),
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )
        await model.waitForInitialLoad()

        model.draftProviderURL = "https://other.example/v1"
        model.draftAPIKey = ""
        await model.save()

        XCTAssertEqual(
            model.saveState,
            .failure(CredentialStoreError.providerOriginMismatch.localizedDescription)
        )
        XCTAssertEqual(store.providerURLString, SettingsStore.defaultProviderURLString)
        let existingKey = try await credentials.apiKey(for: URL(string: SettingsStore.defaultProviderURLString)!)
        XCTAssertEqual(existingKey, "existing-secret")
    }

    func testChangingProviderPathKeepsNewlyTypedKeyForSameOrigin() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = SettingsViewModel(
            store: SettingsStore(defaults: defaults),
            credentials: MemoryCredentialStore(),
            connectionChecker: RecordingConnectionChecker(),
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )
        await model.waitForInitialLoad()

        model.draftAPIKey = "draft-secret"
        model.draftProviderURL = "https://liteapi.gotacat.dev/v2"

        XCTAssertEqual(model.draftAPIKey, "draft-secret")
    }

    func testSubmitReloadsKeyForCurrentStoredOrigin() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let credentials = MemoryCredentialStore()
        try await credentials.saveAPIKey(
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
        try await credentials.saveAPIKey("replacement-secret", for: replacementURL)
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
        try await credentials.saveAPIKey(
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

        for _ in 0..<500 where editor.state == .loading { await Task.yield() }
        let calls = await editorClient.recordedCalls()
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(editor.state, .error)
        XCTAssertFalse(editor.errorMessage?.contains("must-not-leak") ?? true)
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

        model.draftAPIKey = ""
        model.draftAPIKey = "key-for-other-origin"
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

    func testUnknownConnectionErrorDoesNotExposeSensitiveDescription() async {
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
        let checkStarted = await waitForConnectionCallCount(1, checker: checker)
        XCTAssertTrue(checkStarted)
        await checker.fail(call: 0, with: SensitiveConnectionError())

        await waitForConnectionState(
            .failure("Не удалось выполнить действие. Попробуй ещё раз."),
            model: model
        )
    }

    func testRequiresApprovalIsShownAsEnabledAndCanBeDisabled() async {
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
        await model.waitForInitialLoad()

        XCTAssertTrue(model.loginItemIsEnabled)
        model.setLoginItemEnabled(false)
        XCTAssertEqual(loginService.status, .disabled)
        XCTAssertFalse(model.loginItemIsEnabled)
    }

    func testResetClearsCredentialsAndRestoresDraftDefaults() async throws {
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
        model.draftPartialPreviewEnabled = true
        await model.save()

        await model.reset()

        XCTAssertEqual(model.draftProviderURL, SettingsStore.defaultProviderURLString)
        XCTAssertEqual(model.draftModel, SettingsStore.defaultModel)
        XCTAssertEqual(model.draftAPIKey, "")
        XCTAssertEqual(model.currentAPIKey, "")
        XCTAssertFalse(model.draftPartialPreviewEnabled)
        let key = try await credentials.apiKey(for: URL(string: "https://saved.example/")!)
        XCTAssertNil(key)
    }

    func testDiscardRestoresAppliedSettingsAndCredential() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        store.providerURLString = "https://saved.example/v1"
        store.model = "saved/model"
        store.partialPreviewEnabled = true
        let credentials = MemoryCredentialStore()
        try await credentials.saveAPIKey(
            "saved-secret",
            for: URL(string: "https://saved.example/v1")!
        )
        let model = SettingsViewModel(
            store: store,
            credentials: credentials,
            connectionChecker: RecordingConnectionChecker(),
            loginItem: LoginItemController(service: FakeSettingsLoginItemService())
        )
        await model.waitForInitialLoad()

        model.draftProviderURL = "https://other.example/v1"
        model.draftModel = "other/model"
        model.draftPartialPreviewEnabled = false
        model.draftAPIKey = "other-secret"
        model.discardDraftChanges()
        XCTAssertTrue(model.draftPartialPreviewEnabled)
        await model.waitForInitialLoad()

        XCTAssertEqual(model.draftProviderURL, "https://saved.example/v1")
        XCTAssertEqual(model.draftModel, "saved/model")
        XCTAssertEqual(model.draftAPIKey, "saved-secret")
        XCTAssertEqual(model.currentAPIKey, "saved-secret")
        XCTAssertEqual(model.connectionState, .idle)
        XCTAssertEqual(model.saveState, .idle)
    }

    func testSuccessfulSaveAppliesSnapshotPreservesNewDraftAndBlocksDependentActions() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let credentials = ControlledSettingsCredentials()
        let model = SettingsViewModel(store: store, credentials: credentials,
                                      connectionChecker: RecordingConnectionChecker(),
                                      loginItem: LoginItemController(service: FakeSettingsLoginItemService()))
        await credentials.waitForReads(1)
        await credentials.finishRead(0, key: nil)
        await model.waitForInitialLoad()
        model.draftProviderURL = "https://saved.example/v1"
        model.draftModel = "saved/model"
        model.draftAPIKey = "saved-key"
        model.draftPartialPreviewEnabled = true
        let save = Task { await model.save() }
        await credentials.waitForWrite()
        XCTAssertTrue(model.isSaving)
        XCTAssertFalse(model.canCheckConnection)
        let editorClient = RecordingEditorAPIClient()
        let editor = EditorViewModel(apiClient: editorClient, clipboard: ClipboardStub())
        editor.source = "Source"
        model.submit(editor)
        model.discardDraftChanges()
        await model.reset()
        let secondSave = await model.save()
        XCTAssertFalse(secondSave)
        XCTAssertEqual(store.providerURLString, SettingsStore.defaultProviderURLString)
        model.draftProviderURL = "https://new.example/v1"
        model.draftModel = "new/model"
        model.draftAPIKey = ""
        model.draftAPIKey = "new-key"
        model.draftPartialPreviewEnabled = false
        await credentials.finishWrite()
        let close = await save.value
        XCTAssertFalse(close)
        XCTAssertFalse(model.isSaving)
        XCTAssertEqual(model.saveState, .idle, "Changed visible drafts must not be reported as saved")
        XCTAssertEqual(store.providerURLString, "https://saved.example/v1")
        XCTAssertEqual(store.model, "saved/model")
        XCTAssertTrue(store.partialPreviewEnabled)
        XCTAssertEqual(model.currentAPIKey, "saved-key")
        XCTAssertEqual(model.draftProviderURL, "https://new.example/v1")
        XCTAssertEqual(model.draftModel, "new/model")
        XCTAssertFalse(model.draftPartialPreviewEnabled)
        XCTAssertEqual(model.draftAPIKey, "new-key")
        let calls = await editorClient.recordedCalls()
        XCTAssertTrue(calls.isEmpty)
        let deletes = await credentials.deletes
        XCTAssertEqual(deletes, 0)
    }

    func testLateInitialAndDiscardLoadsCannotReplaceNewDraft() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = ControlledSettingsCredentials()
        let model = SettingsViewModel(store: SettingsStore(defaults: defaults), credentials: credentials,
                                      connectionChecker: RecordingConnectionChecker(),
                                      loginItem: LoginItemController(service: FakeSettingsLoginItemService()))
        await credentials.waitForReads(1)
        model.draftAPIKey = "new-draft"
        await credentials.finishRead(0, key: "old-applied")
        await model.waitForInitialLoad()
        XCTAssertEqual(model.draftAPIKey, "new-draft")
        XCTAssertEqual(model.currentAPIKey, "old-applied")
        model.discardDraftChanges()
        await credentials.waitForReads(2)
        model.draftAPIKey = "after-discard"
        await credentials.finishRead(1, key: "old-applied")
        await model.waitForInitialLoad()
        XCTAssertEqual(model.draftAPIKey, "after-discard")
    }

    func testInvalidSaveKeepsPendingCredentialLoadAvailableAfterModelCorrection() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let credentials = ControlledSettingsCredentials()
        let checker = RecordingConnectionChecker()
        let model = SettingsViewModel(store: store, credentials: credentials,
                                      connectionChecker: checker,
                                      loginItem: LoginItemController(service: FakeSettingsLoginItemService()))
        await credentials.waitForReads(1)
        model.draftModel = ""
        let close = await model.save()
        XCTAssertFalse(close)
        XCTAssertEqual(model.saveState, .failure("Укажи модель."))
        XCTAssertEqual(store.model, SettingsStore.defaultModel)
        model.draftModel = "corrected/model"
        await credentials.finishRead(0, key: "stored-key")
        await model.waitForInitialLoad()

        XCTAssertEqual(model.currentAPIKey, "stored-key")
        XCTAssertEqual(model.draftAPIKey, "stored-key")
        model.checkConnection()
        await waitForConnectionState(.success, model: model)
        let call = await checker.recordedCall()
        XCTAssertEqual(call?.apiKey, "stored-key")
        XCTAssertEqual(call?.model, "corrected/model")
    }

    func testInitialAndDiscardLoadsSurviveUnrelatedDraftEditsForSameOrigin() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let credentials = ControlledSettingsCredentials()
        let checker = RecordingConnectionChecker()
        let model = SettingsViewModel(store: store, credentials: credentials,
                                      connectionChecker: checker,
                                      loginItem: LoginItemController(service: FakeSettingsLoginItemService()))
        for read in 0..<2 {
            await credentials.waitForReads(read + 1)
            model.draftModel = "edited/model"
            model.draftPartialPreviewEnabled = true
            model.draftProviderURL = "https://liteapi.gotacat.dev/v1"
            await credentials.finishRead(read, key: "fresh-key")
            await model.waitForInitialLoad()

            XCTAssertEqual(model.draftAPIKey, "fresh-key")
            XCTAssertEqual(model.currentAPIKey, "fresh-key")
            XCTAssertEqual(model.draftModel, "edited/model")
            XCTAssertTrue(model.draftPartialPreviewEnabled)
            XCTAssertEqual(store.model, SettingsStore.defaultModel)
            XCTAssertFalse(store.partialPreviewEnabled)
            model.checkConnection()
            await waitForConnectionState(.success, model: model)
            let call = await checker.recordedCall()
            XCTAssertEqual(call?.url.absoluteString, "https://liteapi.gotacat.dev/v1")
            XCTAssertEqual(call?.apiKey, "fresh-key")
            if read == 0 { model.discardDraftChanges() }
        }
    }

    func testPendingCredentialLoadDoesNotRestoreExplicitlyClearedDraftKey() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = ControlledSettingsCredentials()
        let model = SettingsViewModel(store: SettingsStore(defaults: defaults), credentials: credentials,
                                      connectionChecker: RecordingConnectionChecker(),
                                      loginItem: LoginItemController(service: FakeSettingsLoginItemService()))
        await credentials.waitForReads(1)
        model.draftAPIKey = ""
        await credentials.finishRead(0, key: "stored-key")
        await model.waitForInitialLoad()

        XCTAssertEqual(model.draftAPIKey, "")
        XCTAssertEqual(model.currentAPIKey, "stored-key")
    }

    func testPendingCredentialLoadDoesNotFillKeyIntoDifferentProviderOrigin() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = ControlledSettingsCredentials()
        let checker = RecordingConnectionChecker()
        let model = SettingsViewModel(store: SettingsStore(defaults: defaults), credentials: credentials,
                                      connectionChecker: checker,
                                      loginItem: LoginItemController(service: FakeSettingsLoginItemService()))
        await credentials.waitForReads(1)
        model.draftProviderURL = "https://other.example/v1"
        await credentials.finishRead(0, key: "original-key")
        await model.waitForInitialLoad()

        XCTAssertEqual(model.draftAPIKey, "")
        XCTAssertEqual(model.currentAPIKey, "original-key")
        model.checkConnection()
        await waitForConnectionState(.success, model: model)
        let call = await checker.recordedCall()
        XCTAssertEqual(call?.url.absoluteString, "https://other.example/v1")
        XCTAssertEqual(call?.apiKey, "")
    }

    func testSameGenerationSaveAllowsCloseOnlyAfterSuccess() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = SettingsViewModel(store: SettingsStore(defaults: defaults), credentials: MemoryCredentialStore(),
                                      connectionChecker: RecordingConnectionChecker(),
                                      loginItem: LoginItemController(service: FakeSettingsLoginItemService()))
        await model.waitForInitialLoad()
        model.draftAPIKey = "saved-key"
        let close = await model.save()
        XCTAssertTrue(close)
        XCTAssertEqual(model.saveState, .success)
    }

    func testShutdownAndCancellationWaitForStartedSaveSnapshotApplication() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let credentials = ControlledSettingsCredentials()
        let model = SettingsViewModel(store: store, credentials: credentials,
                                      connectionChecker: RecordingConnectionChecker(),
                                      loginItem: LoginItemController(service: FakeSettingsLoginItemService()))
        await credentials.waitForReads(1)
        await credentials.finishRead(0, key: nil)
        await model.waitForInitialLoad()
        model.draftModel = "saved/model"
        model.draftAPIKey = "saved-key"
        let save = Task { await model.save() }
        await credentials.waitForWrite()
        save.cancel()
        model.beginShutdown()
        var waiting = false
        var finished = false
        let flush = Task { waiting = true; await model.flushStartedSave(); finished = true }
        while !waiting { await Task.yield() }
        XCTAssertFalse(finished)
        await credentials.finishWrite()
        let close = await save.value
        await flush.value
        XCTAssertFalse(close)
        XCTAssertEqual(store.model, "saved/model")
        XCTAssertEqual(model.currentAPIKey, "saved-key")
        XCTAssertTrue(finished)
    }

    func testDiscardInvalidatesStillPendingInitialLoad() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = ControlledSettingsCredentials()
        let model = SettingsViewModel(store: SettingsStore(defaults: defaults), credentials: credentials,
                                      connectionChecker: RecordingConnectionChecker(),
                                      loginItem: LoginItemController(service: FakeSettingsLoginItemService()))
        await credentials.waitForReads(1)
        model.discardDraftChanges()
        await credentials.waitForReads(2)
        await credentials.finishRead(0, key: "obsolete")
        await credentials.finishRead(1, key: "fresh")
        await model.waitForInitialLoad()
        XCTAssertEqual(model.draftAPIKey, "fresh")
        XCTAssertEqual(model.currentAPIKey, "fresh")
    }

    func testReadOnlySaveCannotApplyAfterShutdownOrCancellation() async {
        for shutdown in [true, false] {
            let (defaults, suiteName) = makeDefaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let store = SettingsStore(defaults: defaults)
            let credentials = ControlledSettingsCredentials()
            let model = SettingsViewModel(store: store, credentials: credentials,
                                          connectionChecker: RecordingConnectionChecker(),
                                          loginItem: LoginItemController(service: FakeSettingsLoginItemService()))
            await credentials.waitForReads(1)
            await credentials.finishRead(0, key: "original-key")
            await model.waitForInitialLoad()
            model.draftProviderURL = "https://liteapi.gotacat.dev/v1"
            model.draftModel = "unstarted/model"
            model.draftAPIKey = ""
            let save = Task { await model.save() }
            await credentials.waitForReads(2)
            XCTAssertTrue(model.isSaving)
            if shutdown {
                model.beginShutdown()
                // No backend write started: this returns while the read is blocked.
                await model.flushStartedSave()
                XCTAssertTrue(model.isSaving)
            } else {
                save.cancel()
            }
            await credentials.finishRead(1, key: "late-key")
            let close = await save.value
            XCTAssertFalse(close)
            XCTAssertEqual(store.providerURLString, SettingsStore.defaultProviderURLString)
            XCTAssertEqual(store.model, SettingsStore.defaultModel)
            XCTAssertEqual(model.currentAPIKey, "original-key")
            XCTAssertEqual(model.draftProviderURL, "https://liteapi.gotacat.dev/v1")
            XCTAssertEqual(model.draftModel, "unstarted/model")
            XCTAssertEqual(model.draftAPIKey, "")
            XCTAssertNotEqual(model.saveState, .success)
            XCTAssertFalse(model.isSaving)
        }
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

private actor MemoryCredentialStore: AsyncCredentialStoring {
    private var key: String?
    private var origin: String?

    func saveAPIKey(_ apiKey: String, for providerURL: URL, operation: CredentialWriteOperation) throws {
        operation.markStarted()
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

    func deleteAPIKey(operation: CredentialWriteOperation) throws {
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

private struct FailingSaveCredentialStore: AsyncCredentialStoring {
    func saveAPIKey(_ apiKey: String, for providerURL: URL, operation: CredentialWriteOperation) throws {
        throw APIError.transport(requestCode: "A1B2C3D4")
    }

    func apiKey(for providerURL: URL) throws -> String? {
        nil
    }

    func deleteAPIKey(operation: CredentialWriteOperation) throws {}
}

private struct SensitiveConnectionError: LocalizedError {
    var errorDescription: String? {
        "SECRET_API_KEY SECRET_SOURCE_TEXT"
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

private actor ControlledSettingsCredentials: AsyncCredentialStoring {
    private var reads: [CheckedContinuation<String?, any Error>] = []
    private var write: CheckedContinuation<Void, any Error>?
    private(set) var deletes = 0
    func apiKey(for providerURL: URL) async throws -> String? {
        try await withCheckedThrowingContinuation { reads.append($0) }
    }
    func saveAPIKey(_ apiKey: String, for providerURL: URL, operation: CredentialWriteOperation) async throws {
        operation.markStarted()
        try await withCheckedThrowingContinuation { write = $0 }
    }
    func deleteAPIKey(operation: CredentialWriteOperation) async throws { deletes += 1 }
    func waitForReads(_ count: Int) async {
        for _ in 0..<500 { if reads.count == count { return }; await Task.yield() }
        XCTFail("Expected reads: \(count)")
    }
    func waitForWrite() async {
        for _ in 0..<500 { if write != nil { return }; await Task.yield() }
        XCTFail("Expected write")
    }
    func finishRead(_ index: Int, key: String?) { reads[index].resume(returning: key) }
    func finishWrite() { write?.resume(); write = nil }
}
