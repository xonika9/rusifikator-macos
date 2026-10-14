import Foundation

/// Owns at most four ephemeral sessions. Request delegates own their own data,
/// credentials and cancellation; a session is never invalidated by one request.
final class NetworkSessionOwner: @unchecked Sendable {
    fileprivate struct Key: Hashable {
        let origin: String
        let timeout: TimeInterval
    }

    /// A retiring session keeps its slot until Foundation confirms invalidation.
    private final class SessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
        private weak var owner: NetworkSessionOwner?
        private let key: Key

        init(owner: NetworkSessionOwner, key: Key) {
            self.owner = owner
            self.key = key
        }

        func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
            owner?.invalidated(key, session: session)
        }
    }

    private struct Entry {
        let session: URLSession
        var active: Int
        var lastUsed: UInt64
        var isRetiring = false
    }

    private struct Admission {
        let id: UUID
        let key: Key
        let continuation: CheckedContinuation<Lease, Error>
    }

    final class Lease: @unchecked Sendable {
        let session: URLSession
        private let owner: NetworkSessionOwner
        private let key: Key
        private let lock = NSLock()
        private var released = false

        fileprivate init(session: URLSession, owner: NetworkSessionOwner, key: Key) {
            self.session = session
            self.owner = owner
            self.key = key
        }

        func dataTask(with request: URLRequest, delegate: any URLSessionTaskDelegate) throws -> URLSessionDataTask {
            try owner.dataTask(with: request, delegate: delegate, key: key, session: session)
        }

        func release() {
            let shouldRelease = lock.withLock {
                guard !released else { return false }
                released = true
                return true
            }
            if shouldRelease { owner.release(key) }
        }

        deinit { release() }
    }

    private let lock = NSLock()
    private let protocolClasses: [AnyClass]?
    private var entries: [Key: Entry] = [:]
    private var admissions: [Admission] = []
    private var sequence: UInt64 = 0
    private var isClosing = false
    private var drainContinuations: [CheckedContinuation<Void, Never>] = []

    init(protocolClasses: [AnyClass]? = nil) {
        self.protocolClasses = protocolClasses
    }

    func acquire(origin: ProviderOrigin, timeout: TimeInterval) async throws -> Lease {
        let key = Key(origin: origin.canonicalString, timeout: timeout)
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var retired: URLSession?
                let result: Result<Lease, Error>? = lock.withLock {
                    guard !isClosing, !Task.isCancelled else {
                        return .failure(APIError.cancelled)
                    }
                    if let lease = admit(key, retired: &retired) {
                        return .success(lease)
                    }
                    admissions.append(Admission(id: id, key: key, continuation: continuation))
                    return nil
                }
                retired?.finishTasksAndInvalidate()
                if let result { continuation.resume(with: result) }
            }
        } onCancel: {
            self.cancelAdmission(id)
        }
    }

    /// Prevents new work immediately, cancels active tasks, then waits for their
    /// task and invalidation callbacks to release every live session slot.
    func close() {
        let resources = lock.withLock { () -> ([URLSession], [Admission], [CheckedContinuation<Void, Never>]) in
            isClosing = true
            let sessions = entries.values.map(\.session)
            for key in entries.keys { entries[key]!.isRetiring = true }
            let waiting = admissions
            admissions.removeAll()
            let drains = takeDrainsIfEmpty()
            return (sessions, waiting, drains)
        }
        resources.0.forEach { $0.invalidateAndCancel() }
        resources.1.forEach { $0.continuation.resume(throwing: APIError.cancelled) }
        resources.2.forEach { $0.resume() }
    }

    func drain() async {
        await withCheckedContinuation { continuation in
            let done = lock.withLock {
                if entries.isEmpty { return true }
                drainContinuations.append(continuation)
                return false
            }
            if done { continuation.resume() }
        }
    }

    // Called only with the owner lock held. No callbacks execute under the lock.
    private func admit(_ key: Key, retired: inout URLSession?) -> Lease? {
        if entries[key]?.isRetiring == true { return nil }
        if entries[key] == nil {
            if entries.count == 4 {
                guard let oldest = entries.filter({ $0.value.active == 0 && !$0.value.isRetiring })
                    .min(by: { $0.value.lastUsed < $1.value.lastUsed }) else { return nil }
                entries[oldest.key]!.isRetiring = true
                retired = oldest.value.session
                return nil
            }
            let session = URLSession(configuration: OpenAICompatibleClient.makeConfiguration(
                timeoutInterval: key.timeout,
                protocolClasses: protocolClasses
            ), delegate: SessionDelegate(owner: self, key: key), delegateQueue: nil)
            entries[key] = Entry(session: session, active: 0, lastUsed: 0)
        }
        sequence &+= 1
        entries[key]!.active += 1
        entries[key]!.lastUsed = sequence
        return Lease(session: entries[key]!.session, owner: self, key: key)
    }

    private func dataTask(
        with request: URLRequest,
        delegate: any URLSessionTaskDelegate,
        key: Key,
        session: URLSession
    ) throws -> URLSessionDataTask {
        try lock.withLock {
            guard !isClosing, entries[key]?.isRetiring == false,
                  entries[key]?.session === session else { throw APIError.cancelled }
            let task = session.dataTask(with: request)
            task.delegate = delegate
            return task
        }
    }

    private func cancelAdmission(_ id: UUID) {
        let admission = lock.withLock { () -> Admission? in
            guard let index = admissions.firstIndex(where: { $0.id == id }) else { return nil }
            return admissions.remove(at: index)
        }
        admission?.continuation.resume(throwing: APIError.cancelled)
    }

    private func release(_ key: Key) {
        let work = lock.withLock { () -> ([URLSession], [(Admission, Lease)]) in
            guard var entry = entries[key] else { return ([], []) }
            entry.active -= 1
            entries[key] = entry
            return admitPending()
        }
        perform(work)
    }

    private func invalidated(_ key: Key, session: URLSession) {
        let resources = lock.withLock { () -> (([URLSession], [(Admission, Lease)]), [CheckedContinuation<Void, Never>]) in
            guard entries[key]?.session === session else { return (([], []), []) }
            entries.removeValue(forKey: key)
            return (admitPending(), takeDrainsIfEmpty())
        }
        perform(resources.0)
        resources.1.forEach { $0.resume() }
    }

    // Caller holds the lock. Retiring entries still consume their live slot.
    private func admitPending() -> ([URLSession], [(Admission, Lease)]) {
        guard !isClosing else { return ([], []) }
        var resumed: [(Admission, Lease)] = []
        var retired: [URLSession] = []
        var pending: [Admission] = []
        for admission in admissions {
            var old: URLSession?
            if let lease = admit(admission.key, retired: &old) {
                resumed.append((admission, lease))
            } else {
                pending.append(admission)
            }
            if let old { retired.append(old) }
        }
        admissions = pending
        return (retired, resumed)
    }

    private func perform(_ work: ([URLSession], [(Admission, Lease)])) {
        work.0.forEach { $0.finishTasksAndInvalidate() }
        work.1.forEach { $0.0.continuation.resume(returning: $0.1) }
    }

    private func takeDrainsIfEmpty() -> [CheckedContinuation<Void, Never>] {
        guard entries.isEmpty else { return [] }
        let drains = drainContinuations
        drainContinuations.removeAll()
        return drains
    }

    deinit { entries.values.forEach { $0.session.invalidateAndCancel() } }
}
