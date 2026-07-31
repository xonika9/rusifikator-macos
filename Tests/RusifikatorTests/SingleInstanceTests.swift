import Darwin
import Foundation
import XCTest
@testable import Rusifikator

final class InstanceLockTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rusifikator-lock-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private var lockURL: URL {
        directory.appendingPathComponent("instance.lock")
    }

    func testSecondClaimIsRefusedWhileTheFirstIsHeld() throws {
        let first = InstanceLock(url: lockURL)
        let second = InstanceLock(url: lockURL)

        XCTAssertTrue(try first.acquire())
        XCTAssertFalse(try second.acquire())
        XCTAssertTrue(first.isHeld)
        XCTAssertFalse(second.isHeld)

        first.release()
        XCTAssertTrue(try second.acquire())
        second.release()
    }

    func testConcurrentStartupLetsExactlyOneClaimSucceed() throws {
        let attempts = 32
        let url = lockURL
        // Create the directory once so the race is only about the lock itself.
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let results = Results()
        let locks = (0..<attempts).map { _ in InstanceLock(url: url) }

        DispatchQueue.concurrentPerform(iterations: attempts) { index in
            let acquired = (try? locks[index].acquire()) ?? false
            results.record(acquired)
        }

        XCTAssertEqual(results.successCount, 1)
        locks.forEach { $0.release() }
    }

    func testAbnormalTerminationLeavesNoStaleClaim() throws {
        var crashed: InstanceLock? = InstanceLock(url: lockURL)
        XCTAssertTrue(try XCTUnwrap(crashed).acquire())

        let follower = InstanceLock(url: lockURL)
        XCTAssertFalse(try follower.acquire())

        // Dropping the owner without releasing models a process that died
        // without cleaning up: the kernel drops the lock with the descriptor.
        crashed = nil

        XCTAssertTrue(try follower.acquire())
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockURL.path))
        follower.release()
    }

    func testKilledProcessReleasesTheClaimWithoutManualCleanup() throws {
        guard let python = Self.pythonExecutable else {
            throw XCTSkip("python3 is unavailable, cross-process check skipped")
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = python
        process.arguments = [
            "-c",
            """
            import fcntl, sys, time
            handle = open(sys.argv[1], 'a+')
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            print('locked', flush=True)
            time.sleep(120)
            """,
            lockURL.path
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        XCTAssertTrue(
            Self.waitForLockedMarker(on: pipe),
            "The helper process never took the lock"
        )

        let lock = InstanceLock(url: lockURL)
        XCTAssertFalse(try lock.acquire())

        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()

        var acquired = false
        for _ in 0..<100 where !acquired {
            acquired = (try? lock.acquire()) ?? false
            if !acquired {
                usleep(50_000)
            }
        }
        XCTAssertTrue(acquired, "A killed owner must not leave a stale claim")
        lock.release()
    }

    private static var pythonExecutable: URL? {
        for path in ["/usr/bin/python3", "/opt/homebrew/bin/python3"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static func waitForLockedMarker(on pipe: Pipe) -> Bool {
        let handle = pipe.fileHandleForReading
        var collected = Data()
        let deadline = Date().addingTimeInterval(20)

        while Date() < deadline {
            let chunk = handle.availableData
            if chunk.isEmpty {
                usleep(50_000)
                continue
            }
            collected.append(chunk)
            if String(decoding: collected, as: UTF8.self).contains("locked") {
                return true
            }
        }
        return false
    }
}

private final class Results: @unchecked Sendable {
    private let mutex = NSLock()
    private var successes = 0

    func record(_ acquired: Bool) {
        guard acquired else {
            return
        }
        mutex.lock()
        successes += 1
        mutex.unlock()
    }

    var successCount: Int {
        mutex.lock()
        defer { mutex.unlock() }
        return successes
    }
}

final class InstanceIdentityTests: XCTestCase {
    func testIdentityFollowsTheBundleAndNotTheLocationOnDisk() {
        let first = InstanceIdentity.lockURL(
            bundleIdentifier: "dev.gotacat.Rusifikator"
        )
        let second = InstanceIdentity.lockURL(
            bundleIdentifier: "dev.gotacat.Rusifikator"
        )
        let other = InstanceIdentity.lockURL(
            bundleIdentifier: "dev.gotacat.SomethingElse"
        )

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, other)
        XCTAssertTrue(first.path.contains("dev.gotacat.Rusifikator"))
    }

    func testActivationChannelIsScopedToTheBundleIdentifier() {
        XCTAssertEqual(
            InstanceIdentity.activationNotificationName(
                bundleIdentifier: "dev.gotacat.Rusifikator"
            ),
            Notification.Name("dev.gotacat.Rusifikator.activateRunningInstance")
        )
    }
}

@MainActor
final class SingleInstanceGateTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rusifikator-gate-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func testFirstCopyBecomesPrimaryAndListensForActivation() {
        let channel = ActivationChannelSpy()
        let gate = makeGate(channel: channel)

        XCTAssertEqual(gate.claimSession(), .primary)
        XCTAssertEqual(channel.postedRequests, 0)
        XCTAssertTrue(channel.isObserving)

        var activations = 0
        gate.onActivationRequest = { activations += 1 }
        channel.deliverActivationRequest()

        XCTAssertEqual(activations, 1)
    }

    func testSecondCopyAsksTheRunningOneToComeForwardAndGivesUp() {
        let primaryChannel = ActivationChannelSpy()
        let primary = makeGate(channel: primaryChannel)
        XCTAssertEqual(primary.claimSession(), .primary)

        let secondaryChannel = ActivationChannelSpy()
        let secondary = makeGate(channel: secondaryChannel)

        XCTAssertEqual(secondary.claimSession(), .secondary)
        XCTAssertEqual(
            secondaryChannel.postedRequests,
            SingleInstanceGate.activationAttempts
        )
        XCTAssertFalse(
            secondaryChannel.isObserving,
            "A copy that is about to exit must not register observers"
        )
    }

    func testClaimIsStableWhenAskedAgain() {
        let channel = ActivationChannelSpy()
        let gate = makeGate(channel: channel)

        XCTAssertEqual(gate.claimSession(), .primary)
        XCTAssertEqual(gate.claimSession(), .primary)
        XCTAssertTrue(channel.observerCount == 1)
    }

    private func makeGate(channel: ActivationChannelSpy) -> SingleInstanceGate {
        SingleInstanceGate(
            lock: InstanceLock(
                url: directory.appendingPathComponent("instance.lock")
            ),
            channel: channel,
            sleep: { _ in }
        )
    }
}

private final class ActivationChannelSpy: InstanceActivationChannel,
    @unchecked Sendable
{
    private let mutex = NSLock()
    private var handlers: [() -> Void] = []
    private var posted = 0

    var isObserving: Bool {
        observerCount > 0
    }

    var observerCount: Int {
        mutex.lock()
        defer { mutex.unlock() }
        return handlers.count
    }

    var postedRequests: Int {
        mutex.lock()
        defer { mutex.unlock() }
        return posted
    }

    func observeActivationRequests(_ handler: @escaping @Sendable () -> Void) {
        mutex.lock()
        handlers.append(handler)
        mutex.unlock()
    }

    func postActivationRequest() {
        mutex.lock()
        posted += 1
        mutex.unlock()
    }

    func deliverActivationRequest() {
        mutex.lock()
        let current = handlers
        mutex.unlock()
        current.forEach { $0() }
    }
}
