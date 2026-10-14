import Foundation
import Synchronization
import XCTest
@testable import Rusifikator

@MainActor
final class AsyncCredentialStoreTests: XCTestCase {
    private let original = URL(string: "https://original.example")!
    private let replacement = URL(string: "https://replacement.example")!

    func testBlockedBackendLeavesMainActorResponsiveAndCancelledQueuedReadNeverRuns() async throws {
        let gate = CredentialBackendGate()
        let backend = ControlledKeychainBackend(readGate: gate)
        let owner = makeOwner(backend)
        let first = Task { try await owner.apiKey(for: original) }
        await gate.waitForEntry()
        XCTAssertFalse(backend.readOnMain.withLock { $0 })
        // This assertion executes on the main actor while the backend is blocked.
        XCTAssertEqual(backend.reads.withLock { $0 }, 1)
        let cancelled = Task { try await owner.apiKey(for: original) }
        cancelled.cancel()
        gate.release()
        _ = try await first.value
        do { _ = try await cancelled.value; XCTFail("Cancelled read ran") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(backend.reads.withLock { $0 }, 1)
    }

    func testRollbackAndFollowingReadObserveWholeKeyOriginPair() async throws {
        let gate = CredentialBackendGate()
        let backend = ControlledKeychainBackend(originGate: gate, failOrigin: true)
        backend.seed(key: "old", origin: original.absoluteString)
        let owner = makeOwner(backend)
        let write = Task { try await owner.saveAPIKey("new", for: replacement) }
        await gate.waitForEntry()
        let read = Task { try await owner.apiKey(for: original) }
        gate.release()
        do { try await write.value; XCTFail("Expected injected origin failure") }
        catch { XCTAssertEqual(error as? ControlledKeychainBackend.Failure, .injected) }
        let key = try await read.value
        XCTAssertEqual(key, "old")
        do { _ = try await owner.apiKey(for: replacement); XCTFail("Origin changed") }
        catch { XCTAssertEqual(error as? CredentialStoreError, .providerOriginMismatch) }
    }

    func testShutdownIsImmediateDuringBlockedReadAndRejectsUnstartedWrite() async throws {
        let gate = CredentialBackendGate()
        let backend = ControlledKeychainBackend(readGate: gate)
        let owner = makeOwner(backend)
        let read = Task { try await owner.apiKey(for: original) }
        await gate.waitForEntry()
        let write = Task { try await owner.saveAPIKey("unstarted", for: original) }
        owner.beginShutdown()
        await owner.flushStartedWrites()
        // The read is still blocked: shutdown did not wait for it.
        XCTAssertEqual(backend.writes.withLock { $0 }, 0)
        gate.release()
        _ = try await read.value
        do { try await write.value; XCTFail("Shutdown admitted queued write") }
        catch { XCTAssertTrue(error is CancellationError) }
        do { _ = try await owner.apiKey(for: original); XCTFail("Shutdown admitted read") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(backend.reads.withLock { $0 }, 1)
        XCTAssertEqual(backend.writes.withLock { $0 }, 0)
    }

    func testShutdownWaitsForStartedWriteAndPreservesItsResult() async throws {
        let gate = CredentialBackendGate()
        let backend = ControlledKeychainBackend(originGate: gate)
        let owner = makeOwner(backend)
        let write = Task { try await owner.saveAPIKey("saved", for: original) }
        await gate.waitForEntry()
        owner.beginShutdown()
        var started = false
        var finished = false
        let flush = Task { started = true; await owner.flushStartedWrites(); finished = true }
        while !started { await Task.yield() }
        XCTAssertFalse(finished)
        gate.release()
        try await write.value
        await flush.value
        XCTAssertTrue(finished)
        XCTAssertEqual(backend.values.withLock { $0["key"] }, Data("saved".utf8))
        XCTAssertEqual(backend.values.withLock { $0["origin"] }, Data(original.absoluteString.utf8))
    }

    func testFreshReadAfterReplacementAndDelete() async throws {
        let owner = makeOwner(ControlledKeychainBackend())
        try await owner.saveAPIKey("first", for: original)
        let first = try await owner.apiKey(for: original)
        XCTAssertEqual(first, "first")
        try await owner.saveAPIKey("second", for: original)
        let second = try await owner.apiKey(for: original)
        XCTAssertEqual(second, "second")
        try await owner.deleteAPIKey()
        let deleted = try await owner.apiKey(for: original)
        XCTAssertNil(deleted)
    }

    private func makeOwner(_ backend: ControlledKeychainBackend) -> AsyncCredentialStore {
        AsyncCredentialStore {
            KeychainCredentialStore(service: "synthetic", apiKeyAccount: "key", originAccount: "origin", backend: backend)
        }
    }
}

private final class CredentialBackendGate: Sendable {
    private struct State {
        var entered = false
        var waiter: CheckedContinuation<Void, Never>?
    }
    private let state = Mutex(State())
    private let semaphore = DispatchSemaphore(value: 0)

    func block() {
        let waiter = state.withLock { state in
            state.entered = true
            let waiter = state.waiter
            state.waiter = nil
            return waiter
        }
        waiter?.resume()
        // Deadline prevents a failed test from hanging the runner indefinitely.
        _ = semaphore.wait(timeout: .now() + 5)
    }

    func waitForEntry() async {
        await withCheckedContinuation { continuation in
            let entered = state.withLock { state in
                if state.entered { return true }
                state.waiter = continuation
                return false
            }
            if entered { continuation.resume() }
        }
    }

    func release() { semaphore.signal() }
}

private final class ControlledKeychainBackend: KeychainBackend, Sendable {
    enum Failure: Error { case injected }
    let values = Mutex<[String: Data]>([:])
    let reads = Mutex(0)
    let writes = Mutex(0)
    let readOnMain = Mutex(false)
    private let readGate: CredentialBackendGate?
    private let originGate: CredentialBackendGate?
    private let failOrigin: Mutex<Bool>
    private let gatedOrigin = Mutex(false)

    init(readGate: CredentialBackendGate? = nil, originGate: CredentialBackendGate? = nil, failOrigin: Bool = false) {
        self.readGate = readGate
        self.originGate = originGate
        self.failOrigin = Mutex(failOrigin)
    }

    func seed(key: String, origin: String) {
        values.withLock { $0 = ["key": Data(key.utf8), "origin": Data(origin.utf8)] }
    }

    func readValue(service: String, account: String) throws -> Data? {
        let count = reads.withLock { $0 += 1; return $0 }
        readOnMain.withLock { $0 = Thread.isMainThread }
        if count == 1 { readGate?.block() }
        return values.withLock { $0[account] }
    }

    func upsert(_ data: Data, service: String, account: String) throws {
        writes.withLock { $0 += 1 }
        if account == "origin" {
            let first = gatedOrigin.withLock { let first = !$0; $0 = true; return first }
            if first { originGate?.block() }
            let fail = failOrigin.withLock { let fail = $0; $0 = false; return fail }
            if fail { throw Failure.injected }
        }
        values.withLock { $0[account] = data }
    }

    func deleteValue(service: String, account: String) throws {
        _ = values.withLock { $0.removeValue(forKey: account) }
    }
}
