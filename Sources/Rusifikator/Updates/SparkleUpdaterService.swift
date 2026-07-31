import AppKit
import Foundation
import Sparkle

/// Bridges Sparkle to the application. Sparkle owns the download, the
/// authenticity check and the installation; this type only starts checks and
/// translates Sparkle's reports into the states shown in settings.
@MainActor
final class SparkleUpdaterService: UpdateChecking {
    private let controller: SPUStandardUpdaterController
    private let bridge: SparkleDelegateBridge

    init(report: @escaping (UpdateReport) -> Void) {
        bridge = SparkleDelegateBridge(report: report)
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: bridge,
            userDriverDelegate: bridge
        )
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
