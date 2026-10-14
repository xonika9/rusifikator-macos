import AppKit
import XCTest
import SwiftUI
@testable import Rusifikator

@MainActor
final class AppLaunchTests: XCTestCase {
    func testLaunchKeepsModelsAvailableWithoutCreatingPopoverContent() throws {
        let delegate = makeDelegate()
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer { delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }

        XCTAssertNil(try popover(of: delegate).contentViewController)
        XCTAssertEqual(delegate.editor.state, .empty)
        XCTAssertEqual(delegate.settings.currentAPIKey, "")
        XCTAssertNotNil(SingleInstanceGate.shared.onActivationRequest)
    }

    func testFirstSettingsOpeningCreatesAndRetainsOneNativeRootAcrossAllEntrances() throws {
        let app = NSApplication.shared
        let delegate = makeDelegate()
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let popover = try popover(of: delegate)
        defer {
            popover.performClose(nil)
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        XCTAssertNil(popover.contentViewController)
        delegate.openSettings()
        let controller = try XCTUnwrap(popover.contentViewController)
        guard case .settings = delegate.coordinator.page else { return XCTFail("Settings must be the first page") }
        XCTAssertEqual(popover.contentSize, NSSize(width: 420, height: 500))
        XCTAssertTrue(controller is NSHostingController<PopoverRootView>)
        delegate.editor.source = "Синтетический текст"
        popover.performClose(nil)
        XCTAssertTrue(delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false))
        XCTAssertTrue(popover.contentViewController === controller)
        guard case .editor = delegate.coordinator.page else { return XCTFail("Reopen must show the editor") }
        SingleInstanceGate.shared.onActivationRequest?()
        XCTAssertTrue(popover.contentViewController === controller)
        XCTAssertEqual(delegate.editor.source, "Синтетический текст")
        delegate.perform(NSSelectorFromString("statusItemClicked:"), with: nil)
        XCTAssertTrue(popover.contentViewController === controller)
    }

    func testClickReopenAndSecondaryActivationCanEachCreateTheFirstRoot() throws {
        for entrance in [0, 1, 2] {
            let delegate = makeDelegate()
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            let popover = try popover(of: delegate)
            XCTAssertNil(popover.contentViewController)
            if entrance == 0 { delegate.perform(NSSelectorFromString("statusItemClicked:"), with: nil) }
            else if entrance == 1 { SingleInstanceGate.shared.onActivationRequest?() }
            else { _ = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false) }
            XCTAssertNotNil(popover.contentViewController)
            guard case .editor = delegate.coordinator.page else { return XCTFail("Activation must open editor") }
            popover.performClose(nil)
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
    }

    func testUpdaterStartsInFirstScheduledStageWithoutOpeningWindow() throws {
        let scheduler = LaunchScheduler()
        let service = LaunchUpdater()
        var created = 0
        let delegate = makeDelegate(makeUpdater: { _ in created += 1; return service }, scheduler: scheduler)
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer { delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
        XCTAssertEqual(created, 0)
        XCTAssertEqual(service.startCount, 0)
        XCTAssertEqual(delegate.updates.state, .preparing)
        XCTAssertFalse(delegate.updates.canCheck)
        delegate.updates.checkForUpdates()
        XCTAssertEqual(delegate.updates.state, .preparing)
        XCTAssertNil(try popover(of: delegate).contentViewController)
        scheduler.run()
        XCTAssertEqual(created, 1)
        XCTAssertEqual(service.startCount, 1)
        XCTAssertEqual(delegate.updates.state, .idle)
        XCTAssertTrue(delegate.updates.isAvailable)
        XCTAssertNil(try popover(of: delegate).contentViewController)
        delegate.openSettings()
        delegate.openSettings()
        SingleInstanceGate.shared.onActivationRequest?()
        scheduler.run()
        XCTAssertEqual(service.startCount, 1)
        XCTAssertEqual(created, 1)
        XCTAssertEqual(service.checkCount, 0)
        try popover(of: delegate).performClose(nil)
    }

    func testDefaultSchedulerStartsAfterLaunchWithoutWindow() async throws {
        var created = 0
        let service = LaunchUpdater()
        let delegate = makeDelegate(makeUpdater: { _ in created += 1; return service })
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        XCTAssertEqual(created, 0)
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while created == 0 && ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertEqual(created, 1)
        XCTAssertEqual(service.startCount, 1)
        XCTAssertTrue(delegate.updates.isAvailable)
        XCTAssertNil(try popover(of: delegate).contentViewController)
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    func testTerminationCancelsPendingUpdaterEvenIfSchedulerDeliversLate() async {
        let scheduler = LaunchScheduler()
        var created = 0
        let replied = expectation(description: "Termination reply received by isolated sink")
        var replies = 0
        var writeCompleted = false
        let premature = expectation(description: "Reply must wait for pending history write")
        premature.isInverted = true
        let persistence = TerminationHistory()
        let history = HistoryStore(persistence: persistence)
        await history.waitForInitialLoad()
        history.record(source: "synthetic", result: "synthetic")
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await persistence.isWriting) && ContinuousClock.now < deadline { await Task.yield() }
        let writing = await persistence.isWriting
        XCTAssertTrue(writing)
        let delegate = makeDelegate(makeUpdater: { _ in created += 1; return LaunchUpdater() },
                                    scheduler: scheduler, history: history,
                                    replyToTermination: { sender, allowed in
            XCTAssertTrue(sender === NSApplication.shared)
            XCTAssertTrue(allowed)
            replies += 1
            if !writeCompleted { premature.fulfill() }
            replied.fulfill()
        })
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateLater)
        scheduler.run()
        XCTAssertEqual(created, 0)
        XCTAssertFalse(delegate.updates.isAvailable)
        XCTAssertTrue(delegate.editor.isShuttingDown)
        await fulfillment(of: [premature], timeout: 0.05)
        XCTAssertEqual(replies, 0, "Reply must await the pending history write")
        writeCompleted = true
        await persistence.complete()
        await fulfillment(of: [replied], timeout: 2)
        XCTAssertEqual(replies, 1)
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    func testStartupFailureNeverAttachesCheckerOrExposesErrorDetail() {
        let scheduler = LaunchScheduler()
        let service = LaunchUpdater()
        service.startFails = true
        let delegate = makeDelegate(makeUpdater: { _ in service }, scheduler: scheduler)
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        scheduler.run()
        XCTAssertEqual(service.startCount, 1)
        XCTAssertFalse(delegate.updates.isAvailable)
        XCTAssertFalse(delegate.updates.canCheck)
        XCTAssertEqual(delegate.updates.state, .failed("Не удалось подготовить обновления. Перезапусти приложение."))
        delegate.updates.checkForUpdates()
        XCTAssertEqual(delegate.updates.state, .failed("Не удалось подготовить обновления. Перезапусти приложение."))
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    // Inspect the actual native object without shipping a testing-only accessor.
    private func popover(of delegate: AppDelegate) throws -> NSPopover {
        try XCTUnwrap(Mirror(reflecting: delegate).children.first { $0.label == "popover" }?.value as? NSPopover)
    }

    private func makeDelegate(
        makeUpdater: @escaping (@escaping (UpdateReport) -> Void) -> any UpdateStarting = { _ in LaunchUpdater() },
        scheduler: LaunchScheduler? = nil,
        history suppliedHistory: HistoryStore? = nil,
        replyToTermination: @escaping (NSApplication, Bool) -> Void = { _, _ in
            XCTFail("Unexpected termination reply")
        }
    ) -> AppDelegate {
        _ = NSApplication.shared
        let credentials = AsyncCredentialStore(makeStore: { LaunchCredentials() })
        let defaults = UserDefaults(suiteName: "rusifikator-launch-\(UUID().uuidString)")!
        let history = suppliedHistory ?? HistoryStore(persistence: LaunchHistory())
        let settingsStore = SettingsStore(defaults: defaults)
        let loginItem = LoginItemController(service: LaunchLoginItem())
        if let scheduler {
            return AppDelegate(
                credentials: credentials,
                history: history,
                settingsStore: settingsStore,
                loginItem: loginItem,
                makeUpdater: makeUpdater,
                scheduleUpdater: scheduler.schedule,
                replyToTermination: replyToTermination
            )
        }
        return AppDelegate(
            credentials: credentials,
            history: history,
            settingsStore: settingsStore,
            loginItem: loginItem,
            makeUpdater: makeUpdater,
            replyToTermination: replyToTermination
        )
    }
}

private struct LaunchCredentials: CredentialStore {
    func apiKey(for providerURL: URL) throws -> String? { nil }
    func saveAPIKey(_ apiKey: String, for providerURL: URL) throws {}
    func deleteAPIKey() throws {}
}
private struct LaunchHistory: HistoryPersisting {
    func load(maximumEntryCount: Int) async -> [HistoryEntry] { [] }
    func persist(_ entries: [HistoryEntry], generation: Int) async throws {}
}
@MainActor private final class LaunchUpdater: UpdateStarting {
    var canCheckForUpdates = true
    var startCount = 0
    var checkCount = 0
    var startFails = false
    func start() throws {
        startCount += 1
        if startFails { throw NSError(domain: "SyntheticPrivateDetail", code: 42) }
    }
    func checkForUpdates() { checkCount += 1 }
}
@MainActor private final class LaunchLoginItem: LoginItemServicing {
    var status: LoginItemController.Status { .unavailable }
    func register() throws {}
    func unregister() throws {}
    func openSystemSettings() {}
}

@MainActor private final class LaunchScheduler {
    var operations: [@MainActor () -> Void] = []
    func schedule(_ operation: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        operations.append(operation)
        return Task {}
    }
    func run() {
        let pending = operations
        operations = []
        pending.forEach { $0() }
    }
}

private actor TerminationHistory: HistoryPersisting {
    private var continuation: CheckedContinuation<Void, Never>?
    var isWriting: Bool { continuation != nil }
    func load(maximumEntryCount: Int) async -> [HistoryEntry] { [] }
    func persist(_ entries: [HistoryEntry], generation: Int) async throws {
        await withCheckedContinuation { continuation = $0 }
    }
    func complete() {
        continuation?.resume()
        continuation = nil
    }
}
