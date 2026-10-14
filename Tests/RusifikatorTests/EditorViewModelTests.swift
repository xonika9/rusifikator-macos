import Foundation
import XCTest
@testable import Rusifikator

@MainActor
final class EditorViewModelTests: XCTestCase {
    private let baseURL = URL(string: "https://example.com")!

    func testInitialAndWhitespaceOnlySourceStayEmptyAndCannotSubmit() {
        let client = ControlledEditorAPIClient()
        let model = makeModel(client: client)

        XCTAssertEqual(model.state, .empty)
        XCTAssertFalse(model.canSubmit)
        XCTAssertFalse(model.canCancel)
        XCTAssertFalse(model.canCopy)

        model.source = " \n\t "
        model.submit(
            baseURL: baseURL,
            model: "model",
            credentials: ImmediateEditorCredentials(key: "key"),
            systemPrompt: "system"
        )

        XCTAssertEqual(model.state, .empty)
        XCTAssertFalse(model.canSubmit)
    }

    func testSourceTransitionsBetweenEmptyAndReady() {
        let model = makeModel(client: ControlledEditorAPIClient())

        model.source = "Расшифровка"
        XCTAssertEqual(model.state, .ready)
        XCTAssertTrue(model.canSubmit)

        model.source = ""
        XCTAssertEqual(model.state, .empty)
        XCTAssertFalse(model.canSubmit)
    }

    func testSubmitUsesImmutableSnapshotAndRejectsSecondSubmitWhileLoading() async {
        let client = ControlledEditorAPIClient()
        let model = makeModel(client: client)
        model.source = "Первый текст"

        model.submit(
            baseURL: baseURL,
            model: "first-model",
            partialPreviewEnabled: true,
            credentials: ImmediateEditorCredentials(key: "first-key"),
            systemPrompt: "first-system"
        )
        model.submit(
            baseURL: URL(string: "https://second.example")!,
            model: "second-model",
            credentials: ImmediateEditorCredentials(key: "second-key"),
            systemPrompt: "second-system"
        )

        await waitForCallCount(1, client: client)
        let calls = await client.recordedCalls()

        XCTAssertEqual(model.state, .loading)
        XCTAssertFalse(model.canSubmit)
        XCTAssertTrue(model.canCancel)
        XCTAssertFalse(model.isSourceEditable)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].source, "Первый текст")
        XCTAssertEqual(calls[0].baseURL, baseURL)
        XCTAssertEqual(calls[0].model, "first-model")
        XCTAssertTrue(calls[0].partialPreviewEnabled)
        XCTAssertEqual(calls[0].apiKey, "first-key")
        XCTAssertEqual(calls[0].systemPrompt, "first-system")

        await client.succeed(call: 0, with: "Готово")
        await waitForState(.success, model: model)
    }

    func testSuccessPublishesOnlyCurrentResult() async {
        let client = ControlledEditorAPIClient()
        let history = HistoryRecorderSpy()
        let model = makeModel(client: client, history: history)
        model.source = "Исходник"

        model.submit(
            baseURL: baseURL,
            model: "model",
            credentials: ImmediateEditorCredentials(key: "key"),
            systemPrompt: "system"
        )
        await waitForCallCount(1, client: client)
        await client.succeed(call: 0, with: "Готовый текст")
        await waitForState(.success, model: model)

        XCTAssertEqual(model.source, "Исходник")
        XCTAssertEqual(model.result, "Готовый текст")
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.canCopy)
        XCTAssertTrue(model.canSubmit)
        XCTAssertFalse(model.canCancel)
        XCTAssertTrue(model.isSourceEditable)
        XCTAssertEqual(history.entries, [
            .init(source: "Исходник", result: "Готовый текст")
        ])
    }

    func testErrorRetainsSourceAndEditingRemovesStaleError() async {
        let client = ControlledEditorAPIClient()
        let history = HistoryRecorderSpy()
        let model = makeModel(client: client, history: history)
        model.source = "Исходник"

        model.submit(
            baseURL: baseURL,
            model: "model",
            credentials: ImmediateEditorCredentials(key: "key"),
            systemPrompt: "system"
        )
        await waitForCallCount(1, client: client)
        await client.fail(call: 0, with: APIError.rateLimited)
        await waitForState(.error, model: model)

        XCTAssertEqual(model.source, "Исходник")
        XCTAssertEqual(
            model.errorMessage,
            APIError.rateLimited.localizedDescription
        )
        XCTAssertNil(model.result)
        XCTAssertTrue(model.canSubmit)
        XCTAssertTrue(history.entries.isEmpty)

        model.source = "Исправленный исходник"

        XCTAssertEqual(model.state, .ready)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.result)
    }

    func testUnknownLocalizedErrorDoesNotReachUserMessage() async {
        let client = ControlledEditorAPIClient()
        let model = makeModel(client: client)
        model.source = "Исходник"

        model.submit(
            baseURL: baseURL,
            model: "model",
            credentials: ImmediateEditorCredentials(key: "key"),
            systemPrompt: "system"
        )
        await waitForCallCount(1, client: client)
        await client.fail(call: 0, with: SecretLocalizedError())
        await waitForState(.error, model: model)

        XCTAssertEqual(
            model.errorMessage,
            "Не удалось обработать текст. Попробуй ещё раз."
        )
        XCTAssertFalse(model.errorMessage?.contains("must-not-leak") ?? true)
    }

    func testEditingAfterSuccessRemovesStaleResult() async {
        let client = ControlledEditorAPIClient()
        let model = makeModel(client: client)
        model.source = "Исходник"

        model.submit(
            baseURL: baseURL,
            model: "model",
            credentials: ImmediateEditorCredentials(key: "key"),
            systemPrompt: "system"
        )
        await waitForCallCount(1, client: client)
        await client.succeed(call: 0, with: "Результат")
        await waitForState(.success, model: model)

        model.source = "Новый исходник"

        XCTAssertEqual(model.state, .ready)
        XCTAssertNil(model.result)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.canCopy)
    }

    func testCancelRetainsSourceAndIgnoresLateSuccess() async {
        let client = ControlledEditorAPIClient()
        let history = HistoryRecorderSpy()
        let model = makeModel(client: client, history: history)
        model.source = "Не удалять"

        model.submit(
            baseURL: baseURL,
            model: "model",
            credentials: ImmediateEditorCredentials(key: "key"),
            systemPrompt: "system"
        )
        await waitForCallCount(1, client: client)
        model.cancel()

        XCTAssertEqual(model.state, .cancelled)
        XCTAssertEqual(model.source, "Не удалять")
        XCTAssertNil(model.result)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.canSubmit)

        await client.succeed(call: 0, with: "Запоздалый ответ")
        await Task.yield()

        XCTAssertEqual(model.state, .cancelled)
        XCTAssertNil(model.result)
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testClearDuringLoadingStaysCompletelyEmptyAfterLateResponse() async {
        let client = ControlledEditorAPIClient()
        let model = makeModel(client: client)
        model.source = "Секретный исходник"

        model.submit(
            baseURL: baseURL,
            model: "model",
            credentials: ImmediateEditorCredentials(key: "key"),
            systemPrompt: "system"
        )
        await waitForCallCount(1, client: client)
        model.clear()

        XCTAssertEqual(model.state, .empty)
        XCTAssertEqual(model.source, "")
        XCTAssertNil(model.result)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.copiedConfirmationVisible)

        await client.succeed(call: 0, with: "Запоздалый результат")
        await Task.yield()

        XCTAssertEqual(model.state, .empty)
        XCTAssertEqual(model.source, "")
        XCTAssertNil(model.result)
        XCTAssertNil(model.errorMessage)
    }

    func testRetryCreatesFreshIndependentRequest() async {
        let client = ControlledEditorAPIClient()
        let model = makeModel(client: client)
        model.source = "Первая версия"

        model.submit(
            baseURL: baseURL,
            model: "model-a",
            credentials: ImmediateEditorCredentials(key: "key-a"),
            systemPrompt: "system-a"
        )
        await waitForCallCount(1, client: client)
        await client.fail(
            call: 0,
            with: APIError.transport(requestCode: "A1B2C3D4")
        )
        await waitForState(.error, model: model)

        model.source = "Вторая версия"
        model.submit(
            baseURL: URL(string: "https://other.example/v1")!,
            model: "model-b",
            credentials: ImmediateEditorCredentials(key: "key-b"),
            systemPrompt: "system-b"
        )
        await waitForCallCount(2, client: client)
        await client.succeed(call: 1, with: "Второй результат")
        await waitForState(.success, model: model)

        let calls = await client.recordedCalls()
        XCTAssertEqual(calls.count, 2)
        XCTAssertNotEqual(calls[0].id, calls[1].id)
        XCTAssertEqual(calls.map(\.source), ["Первая версия", "Вторая версия"])
        XCTAssertEqual(calls[1].model, "model-b")
        XCTAssertEqual(model.result, "Второй результат")
        XCTAssertFalse(calls[1].source.contains("Первая версия"))
        XCTAssertFalse(calls[1].source.contains("Первый результат"))
    }

    func testLateFirstCallCannotOverwriteCompletedSecondCall() async {
        let client = ControlledEditorAPIClient()
        let model = makeModel(client: client)
        model.source = "Первый"

        model.submit(
            baseURL: baseURL,
            model: "model",
            credentials: ImmediateEditorCredentials(key: "key"),
            systemPrompt: "system"
        )
        await waitForCallCount(1, client: client)
        model.cancel()

        model.source = "Второй"
        model.submit(
            baseURL: baseURL,
            model: "model",
            credentials: ImmediateEditorCredentials(key: "key"),
            systemPrompt: "system"
        )
        await waitForCallCount(2, client: client)
        await client.succeed(call: 1, with: "Актуальный")
        await waitForState(.success, model: model)

        await client.succeed(call: 0, with: "Устаревший")
        await Task.yield()

        XCTAssertEqual(model.state, .success)
        XCTAssertEqual(model.source, "Второй")
        XCTAssertEqual(model.result, "Актуальный")
    }

    func testClearResetsSuccessAndCancelledStates() async {
        let client = ControlledEditorAPIClient()
        let model = makeModel(client: client)
        model.source = "Исходник"
        model.submit(
            baseURL: baseURL,
            model: "model",
            credentials: ImmediateEditorCredentials(key: "key"),
            systemPrompt: "system"
        )
        await waitForCallCount(1, client: client)
        await client.succeed(call: 0, with: "Результат")
        await waitForState(.success, model: model)

        model.clear()

        XCTAssertEqual(model.state, .empty)
        XCTAssertEqual(model.source, "")
        XCTAssertNil(model.result)
        XCTAssertNil(model.errorMessage)

        model.source = "Ещё исходник"
        model.submit(
            baseURL: baseURL,
            model: "model",
            credentials: ImmediateEditorCredentials(key: "key"),
            systemPrompt: "system"
        )
        await waitForCallCount(2, client: client)
        model.cancel()
        model.clear()

        XCTAssertEqual(model.state, .empty)
        XCTAssertEqual(model.source, "")

        await client.succeed(call: 1, with: "Запоздалый результат")
        await Task.yield()
        XCTAssertEqual(model.state, .empty)
    }

    func testCopyDelegatesToClipboardWithoutChangingEditorContent() async {
        let client = ControlledEditorAPIClient()
        let clipboard = ClipboardSpy()
        let model = makeModel(client: client, clipboard: clipboard)
        model.source = "Исходник"
        model.submit(
            baseURL: baseURL,
            model: "model",
            credentials: ImmediateEditorCredentials(key: "key"),
            systemPrompt: "system"
        )
        await waitForCallCount(1, client: client)
        await client.succeed(call: 0, with: "Скопировать")
        await waitForState(.success, model: model)

        model.copyResult()

        XCTAssertEqual(clipboard.copiedValues, ["Скопировать"])
        XCTAssertEqual(model.source, "Исходник")
        XCTAssertEqual(model.result, "Скопировать")
        XCTAssertEqual(model.state, .success)
        XCTAssertTrue(model.copiedConfirmationVisible)
    }

    // MARK: - Cleanup after two minutes of hidden time

    func testShortlyHiddenPopoverKeepsEditorContent() {
        let clock = TestClock()
        let model = makeModel(client: ControlledEditorAPIClient(), clock: clock)
        model.source = "Черновик"

        model.popoverDidHide()
        clock.advance(by: 119)
        model.popoverWillShow()

        XCTAssertEqual(model.source, "Черновик")
        XCTAssertEqual(model.state, .ready)
        XCTAssertFalse(model.idleResetIsPending)
    }

    func testTwoMinutesOfHiddenTimeClearEditorWithoutTouchingHistory() async {
        let client = ControlledEditorAPIClient()
        let history = HistoryRecorderSpy()
        let clock = TestClock()
        let clocked = makeModel(client: client, history: history, clock: clock)

        clocked.source = "Расшифровка"
        clocked.submit(
            baseURL: baseURL,
            model: "model",
            credentials: ImmediateEditorCredentials(key: "key"),
            systemPrompt: "system"
        )
        await waitForCallCount(1, client: client)
        await client.succeed(call: 0, with: "Результат")
        await waitForState(.success, model: clocked)
        clocked.copyResult()

        clocked.popoverDidHide()
        clock.advance(by: 120)
        clocked.popoverWillShow()

        XCTAssertEqual(clocked.source, "")
        XCTAssertNil(clocked.result)
        XCTAssertNil(clocked.errorMessage)
        XCTAssertFalse(clocked.copiedConfirmationVisible)
        XCTAssertEqual(clocked.state, .empty)
        XCTAssertEqual(
            history.entries,
            [.init(source: "Расшифровка", result: "Результат")]
        )
    }

    func testErrorAndCancelledMarkersAreClearedTogetherWithTheText() async {
        let client = ControlledEditorAPIClient()
        let clock = TestClock()
        let model = makeModel(client: client, clock: clock)
        model.source = "Исходник"
        model.submit(
            baseURL: baseURL,
            model: "model",
            credentials: ImmediateEditorCredentials(key: "key"),
            systemPrompt: "system"
        )
        await waitForCallCount(1, client: client)
        await client.fail(
            call: 0,
            with: APIError.transport(requestCode: "A1B2C3D4")
        )
        await waitForState(.error, model: model)

        model.popoverDidHide()
        clock.advance(by: 120)
        model.popoverWillShow()

        XCTAssertEqual(model.state, .empty)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.source, "")
    }

    func testVisiblePopoverIsNeverClearedNoMatterHowLongItStaysOpen() {
        let clock = TestClock()
        let model = makeModel(client: ControlledEditorAPIClient(), clock: clock)
        model.source = "Долгий черновик"

        model.popoverDidHide()
        clock.advance(by: 300)
        model.popoverWillShow()
        XCTAssertEqual(model.source, "")

        model.source = "Новый черновик"
        clock.advance(by: 3_600)

        XCTAssertEqual(model.source, "Новый черновик")
        XCTAssertEqual(model.state, .ready)
    }

    func testWaitingPeriodRestartsAfterEachClosing() {
        let clock = TestClock()
        let model = makeModel(client: ControlledEditorAPIClient(), clock: clock)
        model.source = "Черновик"

        model.popoverDidHide()
        clock.advance(by: 150)
        model.popoverWillShow()
        XCTAssertEqual(model.source, "")

        model.source = "Следующий черновик"
        model.popoverDidHide()
        clock.advance(by: 30)
        model.popoverWillShow()

        XCTAssertEqual(model.source, "Следующий черновик")
    }

    func testRunningRequestSurvivesTheCleanupAndStillReachesHistory() async {
        let client = ControlledEditorAPIClient()
        let history = HistoryRecorderSpy()
        let clock = TestClock()
        let model = makeModel(client: client, history: history, clock: clock)
        model.source = "Длинная расшифровка"
        model.submit(
            baseURL: baseURL,
            model: "model",
            credentials: ImmediateEditorCredentials(key: "key"),
            systemPrompt: "system"
        )
        await waitForCallCount(1, client: client)

        model.popoverDidHide()
        clock.advance(by: 120)
        model.popoverWillShow()

        // The request keeps running and the text stays until it is safe to drop.
        XCTAssertEqual(model.state, .loading)
        XCTAssertEqual(model.source, "Длинная расшифровка")
        XCTAssertTrue(model.idleResetIsPending)

        await client.succeed(call: 0, with: "Готовый текст")
        await waitForState(.success, model: model)
        XCTAssertEqual(
            history.entries,
            [.init(source: "Длинная расшифровка", result: "Готовый текст")]
        )

        // The postponed cleanup happens at the next opening, even a quick one.
        model.popoverDidHide()
        clock.advance(by: 1)
        model.popoverWillShow()

        XCTAssertEqual(model.source, "")
        XCTAssertEqual(model.state, .empty)
        XCTAssertFalse(model.idleResetIsPending)
        XCTAssertEqual(history.entries.count, 1)
    }

    func testManualClearDropsAPostponedCleanup() async {
        let client = ControlledEditorAPIClient()
        let clock = TestClock()
        let model = makeModel(client: client, clock: clock)
        model.source = "Расшифровка"
        model.submit(
            baseURL: baseURL,
            model: "model",
            credentials: ImmediateEditorCredentials(key: "key"),
            systemPrompt: "system"
        )
        await waitForCallCount(1, client: client)

        model.popoverDidHide()
        clock.advance(by: 120)
        model.popoverWillShow()
        XCTAssertTrue(model.idleResetIsPending)

        model.clear()
        XCTAssertFalse(model.idleResetIsPending)

        model.source = "Свежий черновик"
        model.popoverDidHide()
        clock.advance(by: 1)
        model.popoverWillShow()

        XCTAssertEqual(model.source, "Свежий черновик")
    }

    func testCancelledPreparationCannotSendAfterLateKeyAndNewRequest() async {
        let client = ControlledEditorAPIClient()
        let credentials = ControlledEditorCredentials()
        let model = EditorViewModel(apiClient: client, credentials: credentials, clipboard: ClipboardSpy())
        model.source = "A"
        model.submit(baseURL: baseURL, model: "model-a")
        XCTAssertEqual(model.loadingPhase, .preparingCredentials)
        XCTAssertFalse(model.canSubmit)
        XCTAssertTrue(model.canCancel)
        await credentials.waitForReads(1)
        model.cancel()
        model.source = "B"
        let secondURL = URL(string: "https://second.example")!
        model.submit(baseURL: secondURL, model: "model-b")
        await credentials.waitForReads(2)
        await credentials.complete(read: 0, key: "old")
        await credentials.complete(read: 1, key: "fresh")
        await waitForCallCount(1, client: client)
        let calls = await client.recordedCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.source, "B")
        XCTAssertEqual(calls.first?.model, "model-b")
        XCTAssertEqual(calls.first?.baseURL, secondURL)
        XCTAssertEqual(calls.first?.apiKey, "fresh")
        await client.succeed(call: 0, with: "B final")
        await waitForState(.success, model: model)
        XCTAssertEqual(model.result, "B final")
    }

    func testPreparationFreezesSourceAndSurvivesHiddenIdlePeriod() async {
        let client = ControlledEditorAPIClient()
        let credentials = ControlledEditorCredentials()
        let clock = TestClock()
        let model = EditorViewModel(apiClient: client, credentials: credentials, clipboard: ClipboardSpy(), now: { clock.now })
        model.source = "Frozen"
        model.submit(baseURL: baseURL, model: "frozen-model")
        await credentials.waitForReads(1)
        model.source = "Later"
        model.popoverDidHide()
        clock.advance(by: 121)
        model.popoverWillShow()
        XCTAssertEqual(model.state, .loading)
        XCTAssertEqual(model.loadingPhase, .preparingCredentials)
        await credentials.complete(read: 0, key: "fresh")
        await waitForCallCount(1, client: client)
        let calls = await client.recordedCalls()
        XCTAssertEqual(calls.first?.source, "Frozen")
        XCTAssertEqual(calls.first?.model, "frozen-model")
        await client.succeed(call: 0, with: "Final")
        await waitForState(.success, model: model)
    }

    func testShutdownDuringPreparationForbidsLatePostAndNewSubmit() async {
        let client = ControlledEditorAPIClient()
        let credentials = ControlledEditorCredentials()
        let model = EditorViewModel(apiClient: client, credentials: credentials, clipboard: ClipboardSpy())
        model.source = "A"
        model.submit(baseURL: baseURL, model: "model")
        await credentials.waitForReads(1)
        model.beginShutdown()
        XCTAssertFalse(model.canSubmit)
        model.submit(baseURL: baseURL, model: "new")
        await credentials.complete(read: 0, key: "late")
        for _ in 0..<20 { await Task.yield() }
        let calls = await client.recordedCalls()
        XCTAssertTrue(calls.isEmpty)
        let reads = await credentials.readCount
        XCTAssertEqual(reads, 1)
    }

    func testMissingOrFailedCredentialNeverReachesNetworkAndDoesNotExposeSecret() async {
        for credential in [FailedEditorCredentials(fail: false), FailedEditorCredentials(fail: true)] {
            let client = ControlledEditorAPIClient()
            let model = EditorViewModel(apiClient: client, credentials: credential, clipboard: ClipboardSpy())
            model.source = "Source"
            model.submit(baseURL: baseURL, model: "model")
            await waitForState(.error, model: model)
            let calls = await client.recordedCalls()
            XCTAssertTrue(calls.isEmpty)
            XCTAssertFalse(model.errorMessage?.contains("must-not-leak") ?? true)
        }
    }

    func testPreviewCannotCopyOrEnterHistoryAndConfirmedFinalIsSavedOnce() async {
        let client = ControlledEditorAPIClient()
        let history = HistoryRecorderSpy()
        let clipboard = ClipboardSpy()
        let model = makeModel(client: client, clipboard: clipboard, history: history)
        model.source = "Исходник"
        model.submit(baseURL: baseURL, model: "model", partialPreviewEnabled: true, credentials: ImmediateEditorCredentials(key: "key"))
        await waitForCallCount(1, client: client)
        await client.preview(call: 0, text: "сырой фрагмент")
        for _ in 0..<500 { if !model.previewText.isEmpty { break }; await Task.yield() }
        XCTAssertEqual(model.previewText, "сырой фрагмент")
        XCTAssertNil(model.result)
        XCTAssertFalse(model.canCopy)
        model.copyResult()
        XCTAssertTrue(clipboard.copiedValues.isEmpty)
        XCTAssertTrue(history.entries.isEmpty)
        for i in 0..<2000 { await client.preview(call: 0, text: "фрагмент \(i)") }
        await client.succeed(call: 0, with: "Полный результат")
        await waitForState(.success, model: model)
        XCTAssertEqual(model.previewText, "")
        XCTAssertEqual(model.result, "Полный результат")
        XCTAssertEqual(history.entries, [.init(source: "Исходник", result: "Полный результат")])
        XCTAssertTrue(model.canCopy)
    }

    func testCancelledPreviewAndLatePublicationCannotReplaceNewOperation() async {
        let client = ControlledEditorAPIClient()
        let model = makeModel(client: client)
        model.source = "A"
        model.submit(baseURL: baseURL, model: "A", partialPreviewEnabled: true, credentials: ImmediateEditorCredentials(key: "key"))
        await waitForCallCount(1, client: client)
        await client.preview(call: 0, text: "A")
        model.cancel()
        model.source = "B"
        model.submit(baseURL: baseURL, model: "B", partialPreviewEnabled: true, credentials: ImmediateEditorCredentials(key: "key"))
        await waitForCallCount(2, client: client)
        await client.preview(call: 0, text: "late A")
        await client.succeed(call: 0, with: "late final A")
        await client.preview(call: 1, text: "B")
        for _ in 0..<500 { if model.previewText == "B" { break }; await Task.yield() }
        XCTAssertEqual(model.previewText, "B")
        XCTAssertNil(model.result)
        await client.fail(call: 1, with: APIError.invalidStreamingResponse)
        await waitForState(.error, model: model)
        XCTAssertEqual(model.previewText, "")
        XCTAssertNil(model.result)
    }

    private func makeModel(
        client: ControlledEditorAPIClient,
        clipboard: ClipboardSpy = ClipboardSpy(),
        history: (any HistoryRecording)? = nil,
        clock: TestClock? = nil
    ) -> EditorViewModel {
        let clock = clock ?? TestClock()
        return EditorViewModel(
            apiClient: client,
            clipboard: clipboard,
            history: history,
            now: { clock.now }
        )
    }

    private func waitForCallCount(
        _ expectedCount: Int,
        client: ControlledEditorAPIClient
    ) async {
        for _ in 0..<200 {
            if await client.recordedCalls().count == expectedCount {
                return
            }
            await Task.yield()
        }
        XCTFail("Expected \(expectedCount) API calls")
    }

    private func waitForState(
        _ expectedState: EditorState,
        model: EditorViewModel
    ) async {
        for _ in 0..<200 {
            if model.state == expectedState {
                return
            }
            await Task.yield()
        }
        XCTFail("Expected state \(expectedState), got \(model.state)")
    }
}

private actor ControlledEditorAPIClient: EditorAPIClient {
    private var calls: [EditorRequest] = []
    private var previews: [@Sendable (String) -> Void] = []
    private var continuations: [
        CheckedContinuation<String, any Error>
    ] = []

    func clean(_ request: EditorRequest) async throws -> String {
        calls.append(request)
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func clean(_ request: EditorRequest, onPreview: @escaping @Sendable (String) -> Void) async throws -> String {
        previews.append(onPreview)
        return try await clean(request)
    }

    func preview(call index: Int, text: String) { previews[index](text) }

    func recordedCalls() -> [EditorRequest] {
        calls
    }

    func succeed(call index: Int, with value: String) {
        continuations[index].resume(returning: value)
    }

    func fail(call index: Int, with error: any Error) {
        continuations[index].resume(throwing: error)
    }
}

/// Wall clock under test control, so the waiting period can be exercised
/// without waiting and independently of any running timer.
private final class TestClock: @unchecked Sendable {
    private let mutex = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date {
        mutex.lock()
        defer { mutex.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        mutex.lock()
        current = current.addingTimeInterval(seconds)
        mutex.unlock()
    }
}

private struct SecretLocalizedError: LocalizedError {
    var errorDescription: String? {
        "must-not-leak"
    }
}

@MainActor
private final class ClipboardSpy: ClipboardService {
    private(set) var copiedValues: [String] = []

    func copy(_ string: String) {
        copiedValues.append(string)
    }
}

@MainActor
private final class HistoryRecorderSpy: HistoryRecording {
    struct Entry: Equatable {
        let source: String
        let result: String
    }

    private(set) var entries: [Entry] = []

    func record(source: String, result: String) {
        entries.append(.init(source: source, result: result))
    }
}

private struct ImmediateEditorCredentials: AsyncCredentialStoring {
    let key: String
    func apiKey(for providerURL: URL) async throws -> String? { key }
    func saveAPIKey(_ apiKey: String, for providerURL: URL, operation: CredentialWriteOperation) async throws {}
    func deleteAPIKey(operation: CredentialWriteOperation) async throws {}
}

private actor ControlledEditorCredentials: AsyncCredentialStoring {
    private var continuations: [CheckedContinuation<String?, any Error>] = []
    var readCount: Int { continuations.count }
    func apiKey(for providerURL: URL) async throws -> String? {
        try await withCheckedThrowingContinuation { continuations.append($0) }
    }
    func waitForReads(_ count: Int) async {
        for _ in 0..<500 {
            if continuations.count == count { return }
            await Task.yield()
        }
        XCTFail("Expected credential reads: \(count)")
    }
    func complete(read: Int, key: String) { continuations[read].resume(returning: key) }
    func saveAPIKey(_ apiKey: String, for providerURL: URL, operation: CredentialWriteOperation) async throws {}
    func deleteAPIKey(operation: CredentialWriteOperation) async throws {}
}

private struct FailedEditorCredentials: AsyncCredentialStoring {
    let fail: Bool
    func apiKey(for providerURL: URL) async throws -> String? {
        if fail { throw SecretLocalizedError() }
        return nil
    }
    func saveAPIKey(_ apiKey: String, for providerURL: URL, operation: CredentialWriteOperation) async throws {}
    func deleteAPIKey(operation: CredentialWriteOperation) async throws {}
}
