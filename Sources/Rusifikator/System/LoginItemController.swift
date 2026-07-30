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

    var status: LoginItemController.Status {
        switch service.status {
        case .notRegistered:
            .disabled
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        @unknown default:
            .unavailable
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
