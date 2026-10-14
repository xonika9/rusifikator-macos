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

    // Inspect the actual native object without shipping a testing-only accessor.
    private func popover(of delegate: AppDelegate) throws -> NSPopover {
        try XCTUnwrap(Mirror(reflecting: delegate).children.first { $0.label == "popover" }?.value as? NSPopover)
    }

    private func makeDelegate() -> AppDelegate {
        _ = NSApplication.shared
        let credentials = AsyncCredentialStore(makeStore: { LaunchCredentials() })
        let defaults = UserDefaults(suiteName: "rusifikator-launch-\(UUID().uuidString)")!
        return AppDelegate(
            credentials: credentials,
            history: HistoryStore(persistence: LaunchHistory()),
            settingsStore: SettingsStore(defaults: defaults),
            loginItem: LoginItemController(service: LaunchLoginItem()),
            makeUpdater: { _ in LaunchUpdater() }
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
@MainActor private final class LaunchUpdater: UpdateChecking {
    var canCheckForUpdates: Bool { false }
    func checkForUpdates() {}
}
@MainActor private final class LaunchLoginItem: LoginItemServicing {
    var status: LoginItemController.Status { .unavailable }
    func register() throws {}
    func unregister() throws {}
    func openSystemSettings() {}
}
