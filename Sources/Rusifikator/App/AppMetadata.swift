import Foundation

enum AppMetadata {
    static var menuHeader: String {
        menuHeader(info: Bundle.main.infoDictionary ?? [:])
    }

    static func menuHeader(info: [String: Any]) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String

        if let build, !build.isEmpty, build != version {
            return "Русификатор \(version) (\(build))"
        }
        return "Русификатор \(version)"
    }
}
