import Dispatch
import Foundation
import Synchronization

protocol AsyncCredentialStoring: Sendable {
    func apiKey(for providerURL: URL) async throws -> String?
    func saveAPIKey(_ apiKey: String, for providerURL: URL, operation: CredentialWriteOperation) async throws
    func deleteAPIKey(operation: CredentialWriteOperation) async throws
}

/// Carries write admission across the backend and main-actor settings snapshot.
/// Shutdown waits for snapshot application only if its backend write started.
final class CredentialWriteOperation: Sendable {
    private let started = Mutex(false)
    var hasStarted: Bool { started.withLock { $0 } }
    func markStarted() { started.withLock { $0 = true } }
}

extension AsyncCredentialStoring {
    func saveAPIKey(_ apiKey: String, for providerURL: URL) async throws {
        try await saveAPIKey(apiKey, for: providerURL, operation: CredentialWriteOperation())
    }

    func deleteAPIKey() async throws {
        try await deleteAPIKey(operation: CredentialWriteOperation())
    }
}

/// The backend is created inside, and belongs exclusively to, this actor.
/// A dedicated serial queue keeps blocking Security calls off both the main
/// actor and Swift's cooperative pool. A whole rollback is one actor job.
actor AsyncCredentialStore: AsyncCredentialStoring {
    private final class Executor: SerialExecutor {
        let queue = DispatchQueue(label: "dev.gotacat.Rusifikator.credentials")

        func enqueue(_ job: consuming ExecutorJob) {
            let job = UnownedJob(job)
            queue.async { job.runSynchronously(on: self.asUnownedSerialExecutor()) }
        }
    }

    private struct Admission {
        var closed = false
        var startedWrites = 0
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private nonisolated let executor = Executor()
    private nonisolated let admission = Mutex(Admission())
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }
    private let store: any CredentialStore

    init(makeStore: @Sendable () -> any CredentialStore = { KeychainCredentialStore() }) {
        store = makeStore()
    }

    func apiKey(for providerURL: URL) throws -> String? {
        try Task.checkCancellation()
        guard admission.withLock({ !$0.closed }) else { throw CancellationError() }
        return try store.apiKey(for: providerURL)
    }

    func saveAPIKey(_ apiKey: String, for providerURL: URL, operation: CredentialWriteOperation) throws {
        try beginWrite(operation)
        defer { finishWrite() }
        try store.saveAPIKey(apiKey, for: providerURL)
    }

    func deleteAPIKey(operation: CredentialWriteOperation) throws {
        try beginWrite(operation)
        defer { finishWrite() }
        try store.deleteAPIKey()
    }

    /// Immediate admission barrier, even when the actor is in a blocked read.
    nonisolated func beginShutdown() {
        admission.withLock { $0.closed = true }
    }

    /// Does not queue behind reads and does not wait for unstarted writes.
    nonisolated func flushStartedWrites() async {
        await withCheckedContinuation { continuation in
            let finished = admission.withLock { state in
                if state.startedWrites == 0 { return true }
                state.waiters.append(continuation)
                return false
            }
            if finished { continuation.resume() }
        }
    }

    private func beginWrite(_ operation: CredentialWriteOperation) throws {
        try Task.checkCancellation()
        let admitted = admission.withLock { state in
            guard !state.closed else { return false }
            operation.markStarted()
            state.startedWrites += 1
            return true
        }
        guard admitted else { throw CancellationError() }
    }

    private func finishWrite() {
        let waiters = admission.withLock { state in
            state.startedWrites -= 1
            guard state.startedWrites == 0 else { return [CheckedContinuation<Void, Never>]() }
            let waiters = state.waiters
            state.waiters.removeAll()
            return waiters
        }
        for waiter in waiters { waiter.resume() }
    }
}
