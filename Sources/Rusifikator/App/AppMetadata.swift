import Foundation

enum AppMetadata {
    static var menuHeader: String {
        menuHeader(info: Bundle.main.infoDictionary ?? [:])
    }

    /// User-facing version, for example `1.0`.
    static var displayVersion: String {
        displayVersion(info: Bundle.main.infoDictionary ?? [:])
    }

    /// SemVer version the update channel compares, for example `1.0.0`.
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

        if let build, !build.isEmpty, !isCanonicalExpansion(of: version, build: build) {
            return "Русификатор \(version) (\(build))"
        }
        return "Русификатор \(version)"
    }

    /// `1.0` and `1.0.0` name the same release: the first is what the owner
    /// says, the second is what SemVer tooling needs. Only a build number that
    /// carries extra information is worth showing next to the version.
    private static func isCanonicalExpansion(of version: String, build: String) -> Bool {
        guard let versionNumbers = normalizedComponents(version),
              let buildNumbers = normalizedComponents(build)
        else {
            return false
        }
        return versionNumbers == buildNumbers
    }

    private static func normalizedComponents(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 3 else {
            return nil
        }

        var numbers: [Int] = []
        for part in parts {
            guard let number = Int(part) else {
                return nil
            }
            numbers.append(number)
        }
        while numbers.count < 3 {
            numbers.append(0)
        }
        return numbers
    }
}
