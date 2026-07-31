import Foundation

/// What the settings screen tells the owner about updates.
enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(version: String)
    case failed(String)
}

/// Everything the view model needs from an update mechanism. Keeping it this
/// narrow lets the visible behaviour be tested without a live feed.
@MainActor
protocol UpdateChecking: AnyObject {
    var canCheckForUpdates: Bool { get }
    func checkForUpdates()
}

/// Reports from the update mechanism, already reduced to values that are safe
/// to carry across isolation boundaries.
enum UpdateReport: Equatable, Sendable {
    case foundUpdate(version: String)
    case noUpdateFound
    case cancelledByUser
    case failed(message: String)
}
