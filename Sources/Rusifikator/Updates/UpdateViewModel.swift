import Foundation
import Observation

@Observable
@MainActor
final class UpdateViewModel {
    private(set) var state: UpdateState = .idle

    /// Version the owner sees, for example `1.0`.
    let installedVersion: String

    /// Version the update channel compares, for example `1.0.0`.
    let canonicalVersion: String

    @ObservationIgnored
    private weak var checker: (any UpdateChecking)?

    init(
        installedVersion: String = AppMetadata.displayVersion,
        canonicalVersion: String = AppMetadata.canonicalVersion
    ) {
        self.installedVersion = installedVersion
        self.canonicalVersion = canonicalVersion
    }

    /// The update mechanism is attached after the application finishes
    /// launching, so the settings screen can exist before it.
    func attach(_ checker: any UpdateChecking) {
        self.checker = checker
    }

    var isAvailable: Bool {
        checker != nil
    }

    var canCheck: Bool {
        guard let checker else {
            return false
        }
        return state != .checking && checker.canCheckForUpdates
    }

    var installedVersionDescription: String {
        installedVersion == canonicalVersion
            ? "Установлена версия \(installedVersion)"
            : "Установлена версия \(installedVersion) (\(canonicalVersion))"
    }

    func checkForUpdates() {
        guard let checker, canCheck else {
            if checker == nil {
                state = .failed("Обновления недоступны в этой сборке.")
            }
            return
        }

        state = .checking
        checker.checkForUpdates()
    }

    func handle(_ report: UpdateReport) {
        switch report {
        case let .foundUpdate(version):
            state = .available(version: version)
        case .noUpdateFound:
            state = .upToDate
        case .cancelledByUser:
            state = .idle
        case let .failed(message):
            state = .failed(message)
        }
    }
}
