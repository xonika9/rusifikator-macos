import Foundation

/// One delivery task per request, with a latest-value slot instead of one task
/// per delta. The first delivery is prompt; subsequent deliveries use 100ms.
final class PreviewPublication: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: String?
    private var delivery: Task<Void, Never>?
    private var closed = false
    private let clock: any NetworkClock
    private let publish: @MainActor @Sendable (String) -> Void

    init(clock: any NetworkClock = ContinuousNetworkClock(), publish: @escaping @MainActor @Sendable (String) -> Void) {
        self.clock = clock
        self.publish = publish
    }

    func receive(_ text: String) {
        lock.withLock {
            guard !closed else { return }
            latest = text
            guard delivery == nil else { return }
            delivery = Task { @MainActor [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    guard self.deliverLatest() else { break }
                    do { try await self.clock.sleep(until: self.clock.now.advanced(by: .milliseconds(100))) }
                    catch { break }
                    let hasMore = self.lock.withLock { () -> Bool in
                        if self.latest != nil && !self.closed { return true }
                        self.delivery = nil
                        return false
                    }
                    if !hasMore { return }
                }
                self.lock.withLock { self.delivery = nil }
            }
        }
    }

    @MainActor
    private func deliverLatest() -> Bool {
        let value = lock.withLock { () -> String? in
            guard !closed else { return nil }
            let value = latest
            latest = nil
            return value
        }
        guard let value else { return false }
        publish(value)
        return true
    }

    func cancel() {
        let task = lock.withLock { () -> Task<Void, Never>? in
            closed = true
            latest = nil
            let task = delivery
            delivery = nil
            return task
        }
        task?.cancel()
    }
}
