import Foundation
import XCTest
@testable import Rusifikator

final class SettingsStoreTests: XCTestCase {
    func testEmptyDefaultsUseProductDefaults() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.providerURLString, "https://liteapi.gotacat.dev/")
        XCTAssertEqual(store.model, "proxy/gpt-5.6-terra")
    }

    func testSettingsPersistAndResetWithoutTextFields() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)

        store.providerURLString = "https://example.com/api/"
        store.model = "example/model"

        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.providerURLString, "https://example.com/api/")
        XCTAssertEqual(restored.model, "example/model")
        XCTAssertNil(defaults.object(forKey: "sourceText"))
        XCTAssertNil(defaults.object(forKey: "resultText"))

        restored.reset()
        XCTAssertEqual(restored.providerURLString, "https://liteapi.gotacat.dev/")
        XCTAssertEqual(restored.model, "proxy/gpt-5.6-terra")
    }

    func testCanonicalHTTPSOriginDropsPathQueryAndDefaultPort() throws {
        let url = try XCTUnwrap(
            URL(string: "https://LITEAPI.GOTACAT.DEV:443/v1/?redirect=https://attacker.example")
        )

        XCTAssertEqual(
            try ProviderOrigin.canonicalString(for: url),
            "https://liteapi.gotacat.dev"
        )
    }

    func testCanonicalOriginRejectsNonHTTPSURL() throws {
        let url = try XCTUnwrap(URL(string: "http://liteapi.gotacat.dev/"))

        XCTAssertThrowsError(try ProviderOrigin.canonicalString(for: url)) { error in
            XCTAssertEqual(error as? ProviderOrigin.Error, .requiresHTTPS)
        }
    }

    @MainActor
    func testLoginItemControllerExposesStatusesAndActions() throws {
        let service = FakeLoginItemService(status: .requiresApproval)
        let controller = LoginItemController(service: service)

        XCTAssertEqual(controller.status, .requiresApproval)
        XCTAssertTrue(controller.requiresApproval)

        try controller.setEnabled(true)
        XCTAssertEqual(service.registerCallCount, 1)

        try controller.setEnabled(false)
        XCTAssertEqual(service.unregisterCallCount, 1)

        controller.openSystemSettings()
        XCTAssertEqual(service.openSettingsCallCount, 1)

        service.status = .enabled
        XCTAssertEqual(controller.status, .enabled)
        XCTAssertTrue(controller.isEnabled)

        try controller.setEnabled(true)
        XCTAssertEqual(service.registerCallCount, 1)

        service.status = .disabled
        try controller.setEnabled(false)
        XCTAssertEqual(service.unregisterCallCount, 1)
    }

    @MainActor
    func testLaunchAgentFallbackRegistersCurrentApplicationPath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let plistURL = directory.appendingPathComponent("login-item.plist")
        let executableURL = URL(fileURLWithPath: "/Applications/Rusifikator.app/Contents/MacOS/Rusifikator")
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = LaunchAgentLoginItemService(
            plistURL: plistURL,
            executableURL: executableURL,
            bundleIdentifier: "dev.gotacat.Rusifikator"
        )

        XCTAssertEqual(service.status, .disabled)

        try service.register()

        XCTAssertEqual(service.status, .enabled)
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )
        XCTAssertEqual(plist["Label"] as? String, "dev.gotacat.Rusifikator")
        XCTAssertEqual(
            plist["ProgramArguments"] as? [String],
            [executableURL.path]
        )
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist["LimitLoadToSessionType"] as? String, "Aqua")

        try service.unregister()

        XCTAssertEqual(service.status, .disabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "dev.gotacat.Rusifikator.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

@MainActor
private final class FakeLoginItemService: LoginItemServicing {
    var status: LoginItemController.Status
    var registerCallCount = 0
    var unregisterCallCount = 0
    var openSettingsCallCount = 0

    init(status: LoginItemController.Status) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
    }

    func unregister() throws {
        unregisterCallCount += 1
    }

    func openSystemSettings() {
        openSettingsCallCount += 1
    }
}
