import Darwin
import Foundation

/// Whole-file advisory lock used to claim the right to be the running copy of
/// the application. The kernel drops the lock when the owning process dies, so
/// a crash never leaves a stale claim that has to be cleaned up by hand.
final class InstanceLock {
    enum Failure: Error, Equatable {
        case unavailableLockFile
    }

    private let url: URL
    private let fileManager: FileManager
    private var descriptor: Int32 = -1

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    deinit {
        if descriptor >= 0 {
            close(descriptor)
        }
    }

    var isHeld: Bool {
        descriptor >= 0
    }

    /// Returns `true` when this lock now owns the file, `false` when another
    /// live owner already holds it. The check and the claim happen in a single
    /// kernel operation, so two copies starting at the same moment cannot both
    /// succeed.
    func acquire() throws -> Bool {
        guard descriptor < 0 else {
            return true
        }

        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let opened = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard opened >= 0 else {
            throw Failure.unavailableLockFile
        }

        if flock(opened, LOCK_EX | LOCK_NB) != 0 {
            close(opened)
            return false
        }

        descriptor = opened
        return true
    }

    func release() {
        guard descriptor >= 0 else {
            return
        }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }
}

/// Identity of the application for single-instance purposes. It is derived from
/// the bundle identifier rather than the process name or the path on disk, so
/// two copies of the same application started from different folders still
/// recognise each other, and an unrelated process that happens to share a name
/// does not.
enum InstanceIdentity {
    static let fallbackBundleIdentifier = "dev.gotacat.Rusifikator"

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? fallbackBundleIdentifier
    }

    static func lockURL(
        bundleIdentifier: String,
        fileManager: FileManager = .default
    ) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("Rusifikator", isDirectory: true)
            .appendingPathComponent("\(bundleIdentifier).instance.lock")
    }

    static func activationNotificationName(
        bundleIdentifier: String
    ) -> Notification.Name {
        Notification.Name("\(bundleIdentifier).activateRunningInstance")
    }
}

/// Message channel between a copy that is starting up and the copy that is
/// already running. Extracted as a protocol so the decision logic can be
/// exercised without touching the real per-session notification bus.
protocol InstanceActivationChannel: AnyObject {
    func observeActivationRequests(_ handler: @escaping @Sendable () -> Void)
    func postActivationRequest()
}

final class DistributedActivationChannel: InstanceActivationChannel {
    private let name: Notification.Name
    private let center: DistributedNotificationCenter
    private var observer: (any NSObjectProtocol)?

    init(
        name: Notification.Name,
        center: DistributedNotificationCenter = .default()
    ) {
        self.name = name
        self.center = center
    }

    deinit {
        if let observer {
            center.removeObserver(observer)
        }
    }

    func observeActivationRequests(_ handler: @escaping @Sendable () -> Void) {
        observer = center.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { _ in
            handler()
        }
    }

    func postActivationRequest() {
        center.postNotificationName(
            name,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}

/// Decides whether this copy of the application may continue starting up.
@MainActor
final class SingleInstanceGate {
    enum Claim: Equatable {
        /// This copy owns the session and must finish starting up.
        case primary
        /// Another copy owns the session; this one has asked it to come
        /// forward and must exit before it creates any working components.
        case secondary
    }

    /// A copy that loses the race may reach the notification bus before the
    /// winner has finished subscribing, so the request is repeated over a short
    /// window. Showing the window twice is harmless; missing it is not.
    static let activationAttempts = 4
    static let activationRetryDelay: Duration = .milliseconds(120)

    static let shared = SingleInstanceGate(
        bundleIdentifier: InstanceIdentity.bundleIdentifier
    )

    private let lock: InstanceLock
    private let channel: any InstanceActivationChannel
    private let sleep: @Sendable (Duration) -> Void

    private(set) var claim: Claim?

    /// Called on the running copy when another copy asks it to come forward.
    var onActivationRequest: (() -> Void)?

    convenience init(bundleIdentifier: String) {
        let name = InstanceIdentity.activationNotificationName(
            bundleIdentifier: bundleIdentifier
        )
        self.init(
            lock: InstanceLock(
                url: InstanceIdentity.lockURL(bundleIdentifier: bundleIdentifier)
            ),
            channel: DistributedActivationChannel(name: name)
        )
    }

    init(
        lock: InstanceLock,
        channel: any InstanceActivationChannel,
        sleep: @escaping @Sendable (Duration) -> Void = { duration in
            let nanoseconds = duration.components.seconds * 1_000_000_000
                + duration.components.attoseconds / 1_000_000_000
            var request = timespec(
                tv_sec: Int(nanoseconds / 1_000_000_000),
                tv_nsec: Int(nanoseconds % 1_000_000_000)
            )
            nanosleep(&request, nil)
        }
    ) {
        self.lock = lock
        self.channel = channel
        self.sleep = sleep
    }

    /// Claims the session. On `.secondary` the caller must terminate without
    /// creating a status item, observers or network clients.
    @discardableResult
    func claimSession() -> Claim {
        if let claim {
            return claim
        }

        let acquired = (try? lock.acquire()) ?? false
        guard acquired else {
            requestActivationOfRunningInstance()
            claim = .secondary
            return .secondary
        }

        channel.observeActivationRequests { [weak self] in
            MainActor.assumeIsolated {
                self?.onActivationRequest?()
            }
        }
        claim = .primary
        return .primary
    }

    private func requestActivationOfRunningInstance() {
        for attempt in 0..<Self.activationAttempts {
            if attempt > 0 {
                sleep(Self.activationRetryDelay)
            }
            channel.postActivationRequest()
        }
    }
}
