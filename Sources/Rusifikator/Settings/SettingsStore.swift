import Foundation

final class SettingsStore {
    static let defaultProviderURLString = "https://liteapi.gotacat.dev/"
    static let defaultModel = "proxy/gpt-5.6-terra"

    private enum Key {
        static let providerURL = "dev.gotacat.Rusifikator.providerURL"
        static let model = "dev.gotacat.Rusifikator.model"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var providerURLString: String {
        get {
            defaults.string(forKey: Key.providerURL)
                ?? Self.defaultProviderURLString
        }
        set {
            defaults.set(newValue, forKey: Key.providerURL)
        }
    }

    var model: String {
        get {
            defaults.string(forKey: Key.model)
                ?? Self.defaultModel
        }
        set {
            defaults.set(newValue, forKey: Key.model)
        }
    }

    func reset() {
        defaults.removeObject(forKey: Key.providerURL)
        defaults.removeObject(forKey: Key.model)
    }
}

enum ProviderOrigin {
    enum Error: Swift.Error, Equatable {
        case requiresHTTPS
        case missingHost
        case credentialsNotAllowed
    }

    static func canonicalString(for url: URL) throws -> String {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            throw Error.missingHost
        }
        guard components.scheme?.lowercased() == "https" else {
            throw Error.requiresHTTPS
        }
        guard components.user == nil, components.password == nil else {
            throw Error.credentialsNotAllowed
        }
        guard let host = components.host?.lowercased(), !host.isEmpty else {
            throw Error.missingHost
        }

        let renderedHost = host.contains(":") ? "[\(host)]" : host
        if let port = components.port, port != 443 {
            return "https://\(renderedHost):\(port)"
        }
        return "https://\(renderedHost)"
    }
}
