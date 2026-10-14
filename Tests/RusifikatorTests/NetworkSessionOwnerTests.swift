import Foundation
import XCTest
@testable import Rusifikator

@MainActor
final class NetworkSessionOwnerTests: XCTestCase {
    func testReuseNormalizesOriginButSeparatesPortsAndTimeoutPolicies() async throws {
        let owner = NetworkSessionOwner()
        let first = try await owner.acquire(origin: origin("https://EXAMPLE.com"), timeout: 90)
        let same = try await owner.acquire(origin: origin("https://example.com:443/v1"), timeout: 90)
        let check = try await owner.acquire(origin: origin("https://example.com"), timeout: 30)
        let port = try await owner.acquire(origin: origin("https://example.com:8443"), timeout: 90)
        XCTAssertTrue(first.session === same.session)
        XCTAssertFalse(first.session === check.session)
        XCTAssertFalse(first.session === port.session)
        first.release(); same.release(); check.release(); port.release()
        owner.close()
        await owner.drain()
    }

    func testFifthOriginWaitsWithoutInvalidatingActiveLeasesAndCanBeCancelled() async throws {
        let owner = NetworkSessionOwner()
        var leases: [NetworkSessionOwner.Lease] = []
        for host in ["one", "two", "three", "four"] {
            leases.append(try await owner.acquire(origin: origin("https://\(host).invalid"), timeout: 90))
        }
        let fifth = Task {
            try await owner.acquire(origin: self.origin("https://five.invalid"), timeout: 90)
        }
        fifth.cancel()
        do {
            _ = try await fifth.value
            XCTFail("Cancelled admission must fail")
        } catch { XCTAssertEqual(error as? APIError, .cancelled) }
        let firstAgain = try await owner.acquire(origin: origin("https://one.invalid"), timeout: 90)
        XCTAssertTrue(firstAgain.session === leases[0].session)
        firstAgain.release()
        let replacement = Task {
            try await owner.acquire(origin: self.origin("https://five.invalid"), timeout: 90)
        }
        leases.removeLast().release()
        let admitted = try await replacement.value
        let stillFirst = try await owner.acquire(origin: origin("https://one.invalid"), timeout: 90)
        XCTAssertTrue(stillFirst.session === leases[0].session)
        stillFirst.release(); admitted.release()
        leases.forEach { $0.release() }
        owner.close()
        await owner.drain()
    }

    func testReplacementWaitsForRealSessionInvalidationCallback() async throws {
        let owner = NetworkSessionOwner()
        var leases: [NetworkSessionOwner.Lease] = []
        for host in ["one", "two", "three", "four"] {
            leases.append(try await owner.acquire(origin: origin("https://\(host).invalid"), timeout: 90))
        }
        let retiring = leases.removeFirst()
        let callbackQueue = try XCTUnwrap(retiring.session.delegateQueue.underlyingQueue)
        let allowed = LockedPermission()
        callbackQueue.suspend()
        defer { if !allowed.value { callbackQueue.resume() }; owner.close() }
        retiring.release()
        let started = expectation(description: "Replacement admission started")
        let premature = expectation(description: "Replacement cannot precede real invalidation callback")
        premature.isInverted = true
        let replacement = Task {
            started.fulfill()
            let lease = try await owner.acquire(origin: self.origin("https://five.invalid"), timeout: 90)
            if !allowed.value { premature.fulfill() }
            return lease
        }
        await fulfillment(of: [started], timeout: 2)
        await fulfillment(of: [premature], timeout: 0.05)
        allowed.allow()
        callbackQueue.resume()
        let admitted = try await replacement.value
        XCTAssertFalse(admitted.session === retiring.session)
        admitted.release()
        leases.forEach { $0.release() }
        owner.close()
        await owner.drain()
    }

    func testDrainWaitsForRealSessionInvalidationRatherThanOnlyReleasedLease() async throws {
        let owner = NetworkSessionOwner()
        let lease = try await owner.acquire(origin: origin("https://one.invalid"), timeout: 90)
        let callbackQueue = try XCTUnwrap(lease.session.delegateQueue.underlyingQueue)
        let allowed = LockedPermission()
        callbackQueue.suspend()
        defer { if !allowed.value { callbackQueue.resume() }; owner.close() }
        owner.close()
        lease.release()
        let premature = expectation(description: "Drain cannot precede real invalidation callback")
        premature.isInverted = true
        let drain = Task {
            await owner.drain()
            if !allowed.value { premature.fulfill() }
        }
        await fulfillment(of: [premature], timeout: 0.05)
        allowed.allow()
        callbackQueue.resume()
        await drain.value
    }

    func testClosingRejectsNewAdmissionAndDrainsExistingLeases() async throws {
        let owner = NetworkSessionOwner()
        let lease = try await owner.acquire(origin: origin("https://example.com"), timeout: 90)
        owner.close()
        XCTAssertThrowsError(try lease.dataTask(
            with: URLRequest(url: URL(string: "https://example.com")!),
            delegate: NeverStartedDelegate()
        )) { XCTAssertEqual($0 as? APIError, .cancelled) }
        do {
            _ = try await owner.acquire(origin: origin("https://example.com"), timeout: 90)
            XCTFail("Closed owner must reject a new request")
        } catch { XCTAssertEqual(error as? APIError, .cancelled) }
        lease.release()
        await owner.drain()
    }

    func testCancellingEditorRequestLeavesParallelConnectionCheckAndFollowingRequestIndependent() async throws {
        let owner = NetworkSessionOwner(protocolClasses: [ControlledNetworkProtocol.self])
        let events = NetworkEvents()
        let client = OpenAICompatibleClient(sessionOwner: owner, diagnosticSink: { events.append($0) })
        let startedA = expectation(description: "Editor request delivered")
        let startedB = expectation(description: "Connection check delivered")
        ControlledNetworkProtocol.prepare { request in
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer first" {
                startedA.fulfill()
            } else { startedB.fulfill() }
        }
        defer { ControlledNetworkProtocol.reset(); owner.close() }
        let aID = UUID()
        let a = Task {
            try await client.clean(text: "A", baseURL: URL(string: "https://synthetic.invalid")!, model: "model", apiKey: "first", systemPrompt: "SYSTEM", requestID: aID)
        }
        let b = Task {
            try await client.checkConnection(baseURL: URL(string: "https://synthetic.invalid")!, model: "model", apiKey: "second", systemPrompt: "SYSTEM")
        }
        await fulfillment(of: [startedA, startedB], timeout: 2)
        a.cancel()
        do {
            _ = try await a.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertEqual(error as? APIError, .cancelled) }
        ControlledNetworkProtocol.complete(authorization: "Bearer second", content: "Checked")
        try await b.value
        let startedC = expectation(description: "Following rotated key delivered")
        ControlledNetworkProtocol.onStart = { _ in startedC.fulfill() }
        let c = Task {
            try await client.clean(text: "C", baseURL: URL(string: "https://synthetic.invalid")!, model: "model", apiKey: "third", systemPrompt: "SYSTEM")
        }
        await fulfillment(of: [startedC], timeout: 2)
        ControlledNetworkProtocol.complete(authorization: "Bearer third", content: "Final C")
        let value = try await c.value
        XCTAssertEqual(value, "Final C")
        let requests = ControlledNetworkProtocol.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(Set(requests.compactMap { $0.value(forHTTPHeaderField: "Authorization") }), ["Bearer first", "Bearer second", "Bearer third"])
        XCTAssertTrue(events.values.contains { if case .response = $0 { return true }; return false })
        XCTAssertTrue(events.values.contains { if case .completed = $0 { return true }; return false })
        XCTAssertTrue(events.values.contains { if case .metrics = $0 { return true }; return false })
        owner.close()
        await owner.drain()
    }

    func testCancellingRequestDoesNotInvalidateAnotherTaskOnTheSameSession() async throws {
        let owner = NetworkSessionOwner(protocolClasses: [ControlledNetworkProtocol.self])
        let events = NetworkEvents()
        let client = OpenAICompatibleClient(sessionOwner: owner, diagnosticSink: { events.append($0) })
        let startedA = expectation(description: "Editor request delivered")
        let startedB = expectation(description: "Connection check delivered")
        ControlledNetworkProtocol.prepare { request in
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer first" {
                startedA.fulfill()
            } else { startedB.fulfill() }
        }
        defer { ControlledNetworkProtocol.reset(); owner.close() }
        let aID = UUID()
        let a = Task {
            try await client.clean(text: "A", baseURL: URL(string: "https://synthetic.invalid")!, model: "model", apiKey: "first", systemPrompt: "SYSTEM", requestID: aID)
        }
        let b = Task {
            try await client.clean(text: "B", baseURL: URL(string: "https://synthetic.invalid")!, model: "model", apiKey: "second", systemPrompt: "SYSTEM")
        }
        await fulfillment(of: [startedA, startedB], timeout: 2)
        a.cancel()
        do {
            _ = try await a.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertEqual(error as? APIError, .cancelled) }
        ControlledNetworkProtocol.complete(authorization: "Bearer second", content: "Checked")
        let bValue = try await b.value
        XCTAssertEqual(bValue, "Checked")
        XCTAssertEqual(ControlledNetworkProtocol.requests.count, 2)
        owner.close()
        await owner.drain()
    }

    func testOwnerCloseCancelsActiveTransportAndReleasesItsDelegate() async throws {
        let owner = NetworkSessionOwner(protocolClasses: [ControlledNetworkProtocol.self])
        let client = OpenAICompatibleClient(sessionOwner: owner, diagnosticSink: { _ in })
        let started = expectation(description: "Active transport")
        ControlledNetworkProtocol.prepare { _ in started.fulfill() }
        defer { ControlledNetworkProtocol.reset() }
        let task = Task {
            try await client.clean(text: "A", baseURL: URL(string: "https://synthetic.invalid")!, model: "model", apiKey: "synthetic", systemPrompt: "SYSTEM")
        }
        await fulfillment(of: [started], timeout: 2)
        owner.close()
        do {
            _ = try await task.value
            XCTFail("Closing owner must cancel active transport")
        } catch { XCTAssertEqual(error as? APIError, .cancelled) }
        await owner.drain()
        XCTAssertEqual(ControlledNetworkProtocol.stoppedCount, 1)
    }

    func testAbsoluteDeadlineIncludesAdmissionAndDoesNotDispatchAfterTimeout() async throws {
        let owner = NetworkSessionOwner(protocolClasses: [ControlledNetworkProtocol.self])
        var leases: [NetworkSessionOwner.Lease] = []
        for host in ["one", "two", "three", "four"] {
            leases.append(try await owner.acquire(origin: origin("https://\(host).invalid"), timeout: 90))
        }
        let clock = ManualNetworkClock()
        let timerStarted = expectation(description: "Logical deadline installed")
        clock.onSleep = { timerStarted.fulfill() }
        ControlledNetworkProtocol.prepare { _ in XCTFail("Admission must not issue a POST") }
        defer { ControlledNetworkProtocol.reset(); owner.close() }
        let client = OpenAICompatibleClient(sessionOwner: owner, clock: clock, diagnosticSink: { _ in })
        let id = UUID(uuidString: "A1B2C3D4-1111-2222-3333-444455556666")!
        let task = Task {
            try await client.clean(text: "A", baseURL: URL(string: "https://synthetic.invalid")!, model: "model", apiKey: "synthetic", systemPrompt: "SYSTEM", requestID: id)
        }
        await fulfillment(of: [timerStarted], timeout: 2)
        clock.advance(by: .seconds(90))
        do {
            _ = try await task.value
            XCTFail("Admission consumes the logical deadline")
        } catch { XCTAssertEqual(error as? APIError, .clientTimeout(seconds: 90, requestCode: "A1B2C3D4")) }
        leases.forEach { $0.release() }
        XCTAssertEqual(ControlledNetworkProtocol.requests.count, 0)
        owner.close()
        await owner.drain()
    }

    func testFragmentsDoNotRestartAbsoluteDeadline() async throws {
        let owner = NetworkSessionOwner(protocolClasses: [ControlledNetworkProtocol.self])
        let clock = ManualNetworkClock()
        let started = expectation(description: "POST delivered")
        let timer = expectation(description: "Deadline installed")
        clock.onSleep = { timer.fulfill() }
        ControlledNetworkProtocol.prepare { _ in started.fulfill() }
        defer { ControlledNetworkProtocol.reset(); owner.close() }
        let client = OpenAICompatibleClient(sessionOwner: owner, clock: clock, diagnosticSink: { _ in })
        let lease = try await owner.acquire(origin: origin("https://synthetic.invalid"), timeout: 90)
        defer { lease.release() }
        let id = UUID(uuidString: "A1B2C3D4-1111-2222-3333-444455556666")!
        let task = Task {
            try await client.clean(text: "A", baseURL: URL(string: "https://synthetic.invalid")!, model: "model", apiKey: "synthetic", systemPrompt: "SYSTEM", requestID: id)
        }
        await fulfillment(of: [started, timer], timeout: 2)
        ControlledNetworkProtocol.beginResponse(authorization: "Bearer synthetic")
        for fragment in 1...9 {
            ControlledNetworkProtocol.fragment(authorization: "Bearer synthetic", bytes: Data(repeating: 0x20, count: 65_536))
            let limit = ContinuousClock.now.advanced(by: .seconds(2))
            var received = false
            while ContinuousClock.now < limit {
                let tasks = await lease.session.allTasks
                if tasks.contains(where: { $0.countOfBytesReceived >= Int64(fragment * 65_536) }) {
                    received = true
                    break
                }
                await Task.yield()
            }
            XCTAssertTrue(received, "Actual task must receive fragment before clock advances")
            clock.advance(by: .seconds(10))
        }
        do {
            _ = try await task.value
            XCTFail("Continuous data must not renew the deadline")
        } catch { XCTAssertEqual(error as? APIError, .clientTimeout(seconds: 90, requestCode: "A1B2C3D4")) }
        lease.release()
        owner.close()
        await owner.drain()
        XCTAssertEqual(ControlledNetworkProtocol.requests.count, 1)
    }

    func testTLSRetryPauseAndSecondAttemptShareTheOriginalMonotonicDeadline() async throws {
        let owner = NetworkSessionOwner(protocolClasses: [ControlledNetworkProtocol.self])
        let clock = ManualNetworkClock()
        let sleeps = expectation(description: "Deadline and half-second retry pause installed")
        sleeps.expectedFulfillmentCount = 2
        clock.onSleep = { sleeps.fulfill() }
        let first = expectation(description: "First attempt")
        let second = expectation(description: "Second attempt")
        ControlledNetworkProtocol.prepare { _ in
            if ControlledNetworkProtocol.requests.count == 1 { first.fulfill() }
            else { second.fulfill() }
        }
        defer { ControlledNetworkProtocol.reset(); owner.close() }
        let client = OpenAICompatibleClient(sessionOwner: owner, clock: clock, diagnosticSink: { _ in })
        let id = UUID(uuidString: "A1B2C3D4-1111-2222-3333-444455556666")!
        let task = Task {
            try await client.clean(text: "A", baseURL: URL(string: "https://synthetic.invalid")!, model: "model", apiKey: "synthetic", systemPrompt: "SYSTEM", requestID: id)
        }
        await fulfillment(of: [first], timeout: 2)
        ControlledNetworkProtocol.fail(authorization: "Bearer synthetic", error: URLError(.secureConnectionFailed))
        await fulfillment(of: [sleeps], timeout: 2)
        XCTAssertEqual(ControlledNetworkProtocol.requests.count, 1)
        clock.advance(by: .milliseconds(500))
        await fulfillment(of: [second], timeout: 2)
        clock.advance(by: .milliseconds(89_500))
        do {
            _ = try await task.value
            XCTFail("Second attempt must use original deadline")
        } catch { XCTAssertEqual(error as? APIError, .clientTimeout(seconds: 90, requestCode: "A1B2C3D4")) }
        XCTAssertEqual(ControlledNetworkProtocol.requests.count, 2)
        owner.close()
        await owner.drain()
    }

    func testTLSFailureAfterDataNeverRepeatsPost() async throws {
        let owner = NetworkSessionOwner(protocolClasses: [ControlledNetworkProtocol.self])
        let started = expectation(description: "POST delivered")
        ControlledNetworkProtocol.prepare { _ in started.fulfill() }
        defer { ControlledNetworkProtocol.reset(); owner.close() }
        let client = OpenAICompatibleClient(sessionOwner: owner, diagnosticSink: { _ in })
        let lease = try await owner.acquire(origin: origin("https://synthetic.invalid"), timeout: 90)
        defer { lease.release() }
        let task = Task {
            try await client.clean(text: "A", baseURL: URL(string: "https://synthetic.invalid")!, model: "model", apiKey: "synthetic", systemPrompt: "SYSTEM")
        }
        await fulfillment(of: [started], timeout: 2)
        ControlledNetworkProtocol.beginResponse(authorization: "Bearer synthetic")
        ControlledNetworkProtocol.fragment(authorization: "Bearer synthetic", bytes: Data(repeating: 0x20, count: 65_536))
        let limit = ContinuousClock.now.advanced(by: .seconds(2))
        var received = false
        while ContinuousClock.now < limit {
            let tasks = await lease.session.allTasks
            if tasks.contains(where: { $0.countOfBytesReceived > 0 }) { received = true; break }
            await Task.yield()
        }
        XCTAssertTrue(received, "Actual task must have received data before TLS failure")
        ControlledNetworkProtocol.onStart = { _ in
            XCTFail("A received body must not retry")
            ControlledNetworkProtocol.complete(authorization: "Bearer synthetic", content: "Unexpected retry")
        }
        ControlledNetworkProtocol.fail(authorization: "Bearer synthetic", error: URLError(.secureConnectionFailed))
        do {
            _ = try await task.value
            XCTFail("Expected transport failure")
        } catch let APIError.transport(requestCode) { XCTAssertEqual(requestCode.count, 8) }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(ControlledNetworkProtocol.requests.count, 1)
        lease.release()
        owner.close()
        await owner.drain()
    }

    private func origin(_ url: String) throws -> ProviderOrigin {
        try ProviderOrigin(url: XCTUnwrap(URL(string: url)))
    }
}

private final class NetworkEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [NetworkDiagnosticEvent] = []
    var values: [NetworkDiagnosticEvent] { lock.withLock { stored } }
    func append(_ value: NetworkDiagnosticEvent) { lock.withLock { stored.append(value) } }
}

private final class ControlledNetworkProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var active: [ControlledNetworkProtocol] = []
    nonisolated(unsafe) private static var storedRequests: [URLRequest] = []
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) -> Void)?
    nonisolated(unsafe) private static var stopped = 0
    static var requests: [URLRequest] { lock.withLock { storedRequests } }
    static var stoppedCount: Int { lock.withLock { stopped } }
    static var onStart: (@Sendable (URLRequest) -> Void)? {
        get { lock.withLock { handler } }
        set { lock.withLock { handler = newValue } }
    }
    static func prepare(_ handler: @escaping @Sendable (URLRequest) -> Void) {
        reset()
        onStart = handler
    }
    static func reset() { lock.withLock { active = []; storedRequests = []; handler = nil; stopped = 0 } }
    private static func target(_ authorization: String) -> ControlledNetworkProtocol? {
        let target = lock.withLock { active.first { $0.request.value(forHTTPHeaderField: "Authorization") == authorization } }
        if target == nil { XCTFail("Expected matching delivered request") }
        return target
    }
    static func beginResponse(authorization: String) {
        guard let target = target(authorization) else { return }
        target.client?.urlProtocol(target, didReceive: HTTPURLResponse(url: target.request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!, cacheStoragePolicy: .notAllowed)
    }
    static func fragment(authorization: String, bytes: Data) {
        guard let target = target(authorization) else { return }
        target.client?.urlProtocol(target, didLoad: bytes)
    }
    static func fail(authorization: String, error: URLError) {
        guard let target = target(authorization) else { return }
        target.client?.urlProtocol(target, didFailWithError: error)
        lock.withLock { active.removeAll { $0 === target } }
    }
    static func complete(authorization: String, content: String) {
        guard let target = target(authorization) else { return }
        target.client?.urlProtocol(target, didReceive: HTTPURLResponse(url: target.request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!, cacheStoragePolicy: .notAllowed)
        let response = Data("{\"choices\":[{\"message\":{\"content\":\"\(content)\"}}]}".utf8)
        target.client?.urlProtocol(target, didLoad: response)
        target.client?.urlProtocolDidFinishLoading(target)
        lock.withLock { active.removeAll { $0 === target } }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let callback = Self.lock.withLock {
            Self.active.append(self)
            Self.storedRequests.append(request)
            return Self.handler
        }
        callback?(request)
    }
    override func stopLoading() {
        Self.lock.withLock { Self.stopped += 1; Self.active.removeAll { $0 === self } }
    }
}

private final class ManualNetworkClock: NetworkClock, @unchecked Sendable {
    private struct Sleeper {
        let deadline: ContinuousClock.Instant
        let continuation: CheckedContinuation<Void, Error>
    }
    private let lock = NSLock()
    private var instant = ContinuousClock.now
    private var sleepers: [UUID: Sleeper] = [:]
    private var observer: (@Sendable () -> Void)?
    var now: ContinuousClock.Instant { lock.withLock { instant } }
    var onSleep: (@Sendable () -> Void)? {
        get { lock.withLock { observer } }
        set { lock.withLock { observer = newValue } }
    }
    func sleep(until deadline: ContinuousClock.Instant) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let result: Result<Void, Error>? = lock.withLock {
                    if Task.isCancelled { return .failure(CancellationError()) }
                    if instant >= deadline { return .success(()) }
                    sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return nil
                }
                if let result { continuation.resume(with: result) }
                else { onSleep?() }
            }
        } onCancel: {
            let sleeper = self.lock.withLock { self.sleepers.removeValue(forKey: id) }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }
    func advance(by duration: Duration) {
        let ready = lock.withLock {
            instant = instant.advanced(by: duration)
            let ready = sleepers.filter { $0.value.deadline <= instant }
            ready.keys.forEach { sleepers.removeValue(forKey: $0) }
            return Array(ready.values)
        }
        ready.forEach { $0.continuation.resume() }
    }
}

private final class NeverStartedDelegate: NSObject, URLSessionTaskDelegate {}

private final class LockedPermission: @unchecked Sendable {
    private let lock = NSLock()
    private var allowed = false
    var value: Bool { lock.withLock { allowed } }
    func allow() { lock.withLock { allowed = true } }
}
