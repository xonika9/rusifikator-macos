import Foundation

enum AppMetadata {
    static var menuHeader: String {
        menuHeader(info: Bundle.main.infoDictionary ?? [:])
    }

    /// User-facing version, for example `26.11.22.1`.
    static var displayVersion: String {
        displayVersion(info: Bundle.main.infoDictionary ?? [:])
    }

    /// Version the update channel compares. Releases keep it equal to the
    /// user-facing one.
    static var canonicalVersion: String {
        canonicalVersion(info: Bundle.main.infoDictionary ?? [:])
    }

    static func displayVersion(info: [String: Any]) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        return version.isEmpty ? "—" : version
    }

    static func canonicalVersion(info: [String: Any]) -> String {
        let build = info["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? displayVersion(info: info) : build
    }

    static func menuHeader(info: [String: Any]) -> String {
        let version = displayVersion(info: info)
        let build = info["CFBundleVersion"] as? String

        if let build, !build.isEmpty, build != version {
            return "Русификатор \(version) (\(build))"
        }
        return "Русификатор \(version)"
    }
}
