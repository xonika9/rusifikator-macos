import AppKit
import SwiftUI
import XCTest
@testable import Rusifikator

@MainActor
final class EditorResultSurfaceTests: XCTestCase {
    func testCompletionKeepsTextPositionAndScrollWhileEnablingFinalSelection() async throws {
        _ = NSApplication.shared
        let api = ResultSurfaceAPI()
        let credentials = ResultSurfaceCredentials()
        let clipboard = ResultSurfaceClipboard()
        let history = HistoryStore(persistence: ResultSurfaceHistory())
        let defaultsName = "rusifikator-result-surface-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        let settings = SettingsViewModel(
            store: SettingsStore(defaults: defaults), credentials: credentials,
            loginItem: LoginItemController(service: ResultSurfaceLoginItem())
        )
        let editor = EditorViewModel(apiClient: api, credentials: credentials, clipboard: clipboard, history: history)
        let host = NSHostingView(rootView: EditorView(
            editor: editor, history: history, settings: settings, openHistory: {}, openSettings: {}
        ))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 500),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer {
            editor.cancel()
            settings.beginShutdown()
            window.contentView = nil
            defaults.removePersistentDomain(forName: defaultsName)
            Task { await api.finish("") }
        }
        await history.waitForInitialLoad()
        await settings.waitForInitialLoad()
        let body = (1...60).map { "Синтетическая строка \($0) для проверки результата." }.joined(separator: "\n")
        editor.source = "Вымышленный исходник"
        editor.submit(baseURL: URL(string: "https://fixture.invalid")!, model: "fixture", partialPreviewEnabled: true)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await api.isWaiting) && ContinuousClock.now < deadline { await Task.yield() }
        let waiting = await api.isWaiting
        XCTAssertTrue(waiting)
        await api.preview(body)
        let preview = try await waitForText(body, in: host)
        let previewScroll = try XCTUnwrap(preview.enclosingScrollView)
        let viewport = previewScroll.contentView.bounds.size
        XCTAssertFalse(preview.isSelectable)
        _ = window.makeFirstResponder(preview)
        XCTAssertFalse(window.firstResponder === preview, "Preview must not receive keyboard text actions")
        editor.copyResult()
        XCTAssertTrue(clipboard.values.isEmpty)
        XCTAssertTrue(history.entries.isEmpty)
        previewScroll.contentView.scroll(to: NSPoint(x: 0, y: 100))
        previewScroll.reflectScrolledClipView(previewScroll.contentView)
        let origin = previewScroll.contentView.bounds.origin
        let top = preview.convert(preview.textContainerOrigin, to: host)
        XCTAssertGreaterThan(origin.y, 0, "Fixture must actually scroll before completion")

        let confirmed = body + "\nПодтверждённое окончание."
        await api.finish(confirmed)
        try await waitUntil(in: host) { editor.state == .success && self.textViews(in: host).contains { $0.string == confirmed && $0.isSelectable } }
        let final = try XCTUnwrap(textViews(in: host).first { $0.string == confirmed })
        let finalScroll = try XCTUnwrap(final.enclosingScrollView)
        XCTAssertEqual(finalScroll.contentView.bounds.size, viewport, "Completion must not enlarge the text viewport")
        XCTAssertEqual(finalScroll.contentView.bounds.origin.y, origin.y, accuracy: 0.5, "Completion must retain the reader's scroll position")
        let finalTop = final.convert(final.textContainerOrigin, to: host)
        XCTAssertEqual(finalTop.x, top.x, accuracy: 0.5)
        XCTAssertEqual(finalTop.y, top.y, accuracy: 0.5, "Removing status must not move the text's starting position")
        XCTAssertTrue(window.makeFirstResponder(final))
        editor.copyResult()
        XCTAssertEqual(clipboard.values, [confirmed])
        XCTAssertEqual(history.entries.count, 1)
        await history.flushPendingPersistence()
    }

    private func textViews(in view: NSView) -> [NSTextView] {
        (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap { textViews(in: $0) }
    }

    private func waitForText(_ text: String, in host: NSView) async throws -> NSTextView {
        try await waitUntil(in: host) { self.textViews(in: host).contains { $0.string == text } }
        return try XCTUnwrap(textViews(in: host).first { $0.string == text })
    }

    private func waitUntil(in host: NSView, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        repeat {
            host.layoutSubtreeIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        } while ContinuousClock.now < deadline
        XCTFail("Native result surface did not reach the expected state")
        throw CancellationError()
    }
}

private actor ResultSurfaceAPI: EditorAPIClient {
    private var continuation: CheckedContinuation<String, any Error>?
    private var deliver: (@Sendable (String) -> Void)?
    var isWaiting: Bool { continuation != nil }
    func clean(_ request: EditorRequest) async throws -> String { try await clean(request, onPreview: { _ in }) }
    func clean(_ request: EditorRequest, onPreview: @escaping @Sendable (String) -> Void) async throws -> String {
        deliver = onPreview
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func preview(_ text: String) { deliver?(text) }
    func finish(_ text: String) {
        continuation?.resume(returning: text)
        continuation = nil
        deliver = nil
    }
}

private struct ResultSurfaceCredentials: AsyncCredentialStoring {
    func apiKey(for providerURL: URL) async throws -> String? { "synthetic" }
    func saveAPIKey(_ apiKey: String, for providerURL: URL, operation: CredentialWriteOperation) async throws {}
    func deleteAPIKey(operation: CredentialWriteOperation) async throws {}
}
private struct ResultSurfaceHistory: HistoryPersisting {
    func load(maximumEntryCount: Int) async -> [HistoryEntry] { [] }
    func persist(_ entries: [HistoryEntry], generation: Int) async throws {}
}
@MainActor private final class ResultSurfaceClipboard: ClipboardService {
    var values: [String] = []
    func copy(_ text: String) { values.append(text) }
}
@MainActor private final class ResultSurfaceLoginItem: LoginItemServicing {
    var status: LoginItemController.Status { .unavailable }
    func register() throws {}
    func unregister() throws {}
    func openSystemSettings() {}
}
