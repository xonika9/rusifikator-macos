import Foundation
import ServiceManagement

@MainActor
protocol LoginItemServicing: AnyObject {
    var status: LoginItemController.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
final class LoginItemController {
    enum Status: Equatable {
        case disabled
        case enabled
        case requiresApproval
        case unavailable
    }

    private let service: any LoginItemServicing

    init(service: any LoginItemServicing = MainAppLoginItemService()) {
        self.service = service
    }

    var status: Status {
        service.status
    }

    var isEnabled: Bool {
        status == .enabled
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard status != .enabled else { return }
            try service.register()
        } else {
            guard status != .disabled else { return }
            try service.unregister()
        }
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}

@MainActor
private final class MainAppLoginItemService: LoginItemServicing {
    private let service = SMAppService.mainApp
    private let fallback: LaunchAgentLoginItemService?

    init(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
        guard let executableURL = bundle.executableURL,
              bundle.bundleURL.standardizedFileURL.path.hasPrefix("/Applications/")
        else {
            fallback = nil
            return
        }
        let identifier = bundle.bundleIdentifier ?? "dev.gotacat.Rusifikator"
        let plistURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(identifier).plist")
        fallback = LaunchAgentLoginItemService(
            plistURL: plistURL,
            executableURL: executableURL,
            bundleIdentifier: identifier,
            fileManager: fileManager
        )
    }

    var status: LoginItemController.Status {
        switch service.status {
        case .notRegistered:
            .disabled
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            fallback?.status ?? .unavailable
        @unknown default:
            .unavailable
        }
    }

    func register() throws {
        if service.status == .notFound {
            guard let fallback else {
                throw LoginItemError.applicationMustBeInstalled
            }
            try fallback.register()
        } else {
            try service.register()
        }
    }

    func unregister() throws {
        if service.status == .notFound {
            try fallback?.unregister()
        } else {
            try service.unregister()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
final class LaunchAgentLoginItemService: LoginItemServicing {
    private let plistURL: URL
    private let executableURL: URL
    private let bundleIdentifier: String
    private let fileManager: FileManager

    init(
        plistURL: URL,
        executableURL: URL,
        bundleIdentifier: String,
        fileManager: FileManager = .default
    ) {
        self.plistURL = plistURL
        self.executableURL = executableURL
        self.bundleIdentifier = bundleIdentifier
        self.fileManager = fileManager
    }

    var status: LoginItemController.Status {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data,
                  format: nil
              ) as? [String: Any],
              plist["Label"] as? String == bundleIdentifier,
              plist["ProgramArguments"] as? [String] == [executableURL.path],
              plist["RunAtLoad"] as? Bool == true
        else {
            return .disabled
        }
        return .enabled
    }

    func register() throws {
        let definition: [String: Any] = [
            "Label": bundleIdentifier,
            "ProgramArguments": [executableURL.path],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: definition,
            format: .xml,
            options: 0
        )
        try fileManager.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: plistURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: plistURL.path
        )
    }

    func unregister() throws {
        do {
            try fileManager.removeItem(at: plistURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

private enum LoginItemError: LocalizedError {
    case applicationMustBeInstalled

    var errorDescription: String? {
        "Перемести Русификатор в папку «Программы» и открой его оттуда."
    }
}
