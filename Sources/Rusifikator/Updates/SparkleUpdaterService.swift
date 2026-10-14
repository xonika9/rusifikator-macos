import AppKit
import Foundation
import Sparkle

/// Bridges Sparkle to the application. Sparkle owns the download, the
/// authenticity check and the installation; this type only starts checks and
/// translates Sparkle's reports into the states shown in settings.
@MainActor
final class SparkleUpdaterService: UpdateStarting {
    private let controller: SPUStandardUpdaterController
    private let bridge: SparkleDelegateBridge
    private let report: (UpdateReport) -> Void
    private var availabilityObservation: NSKeyValueObservation?
    private var started = false

    init(report: @escaping (UpdateReport) -> Void) {
        self.report = report
        bridge = SparkleDelegateBridge(report: report)
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: bridge,
            userDriverDelegate: bridge
        )
    }

    func start() throws {
        guard !started else { return }
        try controller.updater.start()
        started = true
        availabilityObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let available = updater.canCheckForUpdates
            Task { @MainActor [weak self] in
                self?.report(.availabilityChanged(available))
            }
        }
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        // A menu-bar application has no window to show the update panel over,
        // so it has to come forward on its own.
        NSApplication.shared.activate()
        controller.updater.checkForUpdates()
    }
}

/// Sparkle reports progress through Objective-C delegate protocols. This type
/// receives those callbacks and reduces them to the small set of outcomes the
/// settings screen understands.
@MainActor
private final class SparkleDelegateBridge: NSObject, SPUUpdaterDelegate,
    SPUStandardUserDriverDelegate
{
    private let report: (UpdateReport) -> Void

    init(report: @escaping (UpdateReport) -> Void) {
        self.report = report
        super.init()
    }

    // Scheduled background checks must not steal focus from whatever the owner
    // is doing; only an explicitly requested check opens a window immediately.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        report(.foundUpdate(version: item.displayVersionString))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        report(.noUpdateFound)
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        guard let error = error as NSError? else {
            return
        }
        report(UpdateErrorMapping.report(forErrorCode: error.code))
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        report(UpdateErrorMapping.report(forErrorCode: (error as NSError).code))
    }
}
