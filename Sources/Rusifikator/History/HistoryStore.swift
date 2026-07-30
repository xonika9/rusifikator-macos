import Foundation
import Observation

struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let source: String
    let result: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        source: String,
        result: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.result = result
        self.createdAt = createdAt
    }
}

@MainActor
protocol HistoryRecording: AnyObject {
    func record(source: String, result: String)
}

protocol HistoryPersisting: Sendable {
    func load(maximumEntryCount: Int) async -> [HistoryEntry]
    func persist(_ entries: [HistoryEntry], generation: Int) async throws
}

@Observable
@MainActor
final class HistoryStore: HistoryRecording {
    static let maximumEntryCount = 5

    private enum PersistenceOutcome: Equatable, Sendable {
        case success
        case failure
    }

    private enum RetryIntent {
        case persist(snapshot: [HistoryEntry])
        case clearInitial(
            snapshot: [HistoryEntry],
            clearedEntryIDs: Set<HistoryEntry.ID>
        )
        case clearCorrective(snapshot: [HistoryEntry])
    }

    private struct TrackedOperation {
        let id: Int
        let task: Task<PersistenceOutcome, Never>
    }

    private(set) var entries: [HistoryEntry]
    private(set) var isLoading = true
    private(set) var persistenceErrorMessage: String?
    private(set) var isRetryingPersistence = false

    @ObservationIgnored
    private let persistence: any HistoryPersisting

    @ObservationIgnored
    private var initialLoadTask: Task<Void, Never>?

    @ObservationIgnored
    private var persistenceGeneration = 0

    @ObservationIgnored
    private var pendingPersistenceTask: Task<PersistenceOutcome, Never>?

    @ObservationIgnored
    private var retryIntent: RetryIntent?

    @ObservationIgnored
    private var activeClearOperation: TrackedOperation?

    @ObservationIgnored
    private var activeRetryOperation: TrackedOperation?

    @ObservationIgnored
    private var nextOperationID = 0

    convenience init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let resolvedFileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.init(
            persistence: HistoryPersistence(fileURL: resolvedFileURL)
        )
    }

    init(persistence: any HistoryPersisting) {
        self.persistence = persistence
        self.entries = []
        startInitialLoad()
    }

    private func startInitialLoad() {
        initialLoadTask = Task { [weak self] in
            guard let self else {
                return
            }
            let loaded = await persistence.load(
                maximumEntryCount: Self.maximumEntryCount
            )
            let pendingEntries = entries
            entries = Self.mergedEntries(
                pendingEntries,
                loaded
            )
            isLoading = false
            if !pendingEntries.isEmpty {
                persistInBackground()
            }
        }
    }

    func record(source: String, result: String) {
        record(source: source, result: result, createdAt: Date())
    }

    func record(
        source: String,
        result: String,
        createdAt: Date
    ) {
        entries.insert(
            HistoryEntry(
                source: source,
                result: result,
                createdAt: createdAt
            ),
            at: 0
        )
        if entries.count > Self.maximumEntryCount {
            entries.removeLast(entries.count - Self.maximumEntryCount)
        }
        if !isLoading {
            persistInBackground()
        }
    }

    func clear() async throws {
        await initialLoadTask?.value
        while true {
            if let activeClearOperation {
                guard await activeClearOperation.task.value == .success else {
                    throw HistoryStoreError.persistenceFailed
                }
                return
            }
            if let activeRetryOperation {
                _ = await activeRetryOperation.task.value
                continue
            }

            let clearedEntryIDs = Set(entries.map(\.id))
            let operation = startClearOperation(clearedEntryIDs: clearedEntryIDs)
            let outcome = await operation.task.value
            guard outcome == .success else {
                throw HistoryStoreError.persistenceFailed
            }
            return
        }
    }

    func flushPendingPersistence() async {
        await initialLoadTask?.value
        while true {
            if let clearTask = activeClearOperation?.task {
                _ = await clearTask.value
                continue
            }
            if let retryTask = activeRetryOperation?.task {
                _ = await retryTask.value
                continue
            }

            let generation = persistenceGeneration
            let task = pendingPersistenceTask
            _ = await task?.value
            guard activeClearOperation == nil,
                  activeRetryOperation == nil,
                  generation == persistenceGeneration
            else {
                continue
            }
            return
        }
    }

    func waitForInitialLoad() async {
        await initialLoadTask?.value
    }

    func retryPersistence() {
        guard !isLoading,
              let retryIntent,
              pendingPersistenceTask == nil,
              activeClearOperation == nil,
              activeRetryOperation == nil
        else {
            return
        }
        isRetryingPersistence = true
        nextOperationID += 1
        let operationID = nextOperationID
        let task = Task { [weak self] in
            guard let self else {
                return PersistenceOutcome.failure
            }
            let outcome = await self.performRetry(retryIntent)
            self.finishRetryOperation(id: operationID)
            return outcome
        }
        activeRetryOperation = TrackedOperation(id: operationID, task: task)
    }

    private func persistInBackground() {
        persistenceGeneration += 1
        let generation = persistenceGeneration
        startPersistence(
            entries,
            generation: generation,
            managesFailureState: true
        )
    }

    @discardableResult
    private func startPersistence(
        _ snapshot: [HistoryEntry],
        generation: Int,
        managesFailureState: Bool
    ) -> Task<PersistenceOutcome, Never> {
        let persistence = persistence
        let task = Task { [weak self] in
            let outcome: PersistenceOutcome
            do {
                try await persistence.persist(
                    snapshot,
                    generation: generation
                )
                outcome = .success
            } catch {
                outcome = .failure
            }
            self?.finishPersistence(
                outcome,
                generation: generation,
                snapshot: snapshot,
                managesFailureState: managesFailureState
            )
            return outcome
        }
        pendingPersistenceTask = task
        return task
    }

    private func finishPersistence(
        _ outcome: PersistenceOutcome,
        generation: Int,
        snapshot: [HistoryEntry],
        managesFailureState: Bool
    ) {
        guard generation == persistenceGeneration else {
            return
        }
        pendingPersistenceTask = nil
        guard managesFailureState else {
            return
        }
        switch outcome {
        case .success:
            if !hasPendingClearRetry {
                clearPersistenceFailure()
            }
        case .failure:
            if !hasPendingClearRetry {
                markPersistenceFailure(.persist(snapshot: snapshot))
            }
        }
    }

    private var hasPendingClearRetry: Bool {
        switch retryIntent {
        case .clearInitial, .clearCorrective:
            true
        case .persist, nil:
            false
        }
    }

    private func startClearOperation(
        clearedEntryIDs: Set<HistoryEntry.ID>
    ) -> TrackedOperation {
        nextOperationID += 1
        let operationID = nextOperationID
        let task = Task { [weak self] in
            guard let self else {
                return PersistenceOutcome.failure
            }
            let outcome = await self.performClear(
                initialSnapshot: [],
                clearedEntryIDs: clearedEntryIDs
            )
            self.finishClearOperation(id: operationID)
            return outcome
        }
        let operation = TrackedOperation(id: operationID, task: task)
        activeClearOperation = operation
        return operation
    }

    private func finishClearOperation(id: Int) {
        guard activeClearOperation?.id == id else {
            return
        }
        activeClearOperation = nil
    }

    private func finishRetryOperation(id: Int) {
        guard activeRetryOperation?.id == id else {
            return
        }
        activeRetryOperation = nil
        isRetryingPersistence = false
    }

    private func performRetry(_ intent: RetryIntent) async -> PersistenceOutcome {
        switch intent {
        case let .persist(snapshot):
            return await performPersistenceRetry(initialSnapshot: snapshot)

        case let .clearInitial(snapshot, clearedEntryIDs):
            return await performClear(
                initialSnapshot: snapshot,
                clearedEntryIDs: clearedEntryIDs
            )

        case let .clearCorrective(snapshot):
            return await performClearCorrection(initialSnapshot: snapshot)
        }
    }

    private func performPersistenceRetry(
        initialSnapshot: [HistoryEntry]
    ) async -> PersistenceOutcome {
        await performConvergingWrite(initialSnapshot: initialSnapshot) {
            .persist(snapshot: $0)
        }
    }

    private func performClear(
        initialSnapshot: [HistoryEntry],
        clearedEntryIDs: Set<HistoryEntry.ID>
    ) async -> PersistenceOutcome {
        let (outcome, generation) = await performManagedWrite(initialSnapshot)
        guard outcome == .success else {
            if generation == persistenceGeneration {
                markPersistenceFailure(
                    .clearInitial(
                        snapshot: initialSnapshot,
                        clearedEntryIDs: clearedEntryIDs
                    )
                )
            }
            return .failure
        }

        entries.removeAll { clearedEntryIDs.contains($0.id) }
        guard generation != persistenceGeneration || !entries.isEmpty else {
            clearPersistenceFailure()
            return .success
        }
        return await performClearCorrection(initialSnapshot: entries)
    }

    private func performClearCorrection(
        initialSnapshot: [HistoryEntry]
    ) async -> PersistenceOutcome {
        await performConvergingWrite(initialSnapshot: initialSnapshot) {
            .clearCorrective(snapshot: $0)
        }
    }

    private func performConvergingWrite(
        initialSnapshot: [HistoryEntry],
        retryIntent: ([HistoryEntry]) -> RetryIntent
    ) async -> PersistenceOutcome {
        var snapshot = initialSnapshot
        while true {
            let (outcome, generation) = await performManagedWrite(snapshot)
            guard outcome == .success else {
                if generation == persistenceGeneration {
                    markPersistenceFailure(retryIntent(snapshot))
                }
                return .failure
            }
            guard generation != persistenceGeneration || snapshot != entries else {
                clearPersistenceFailure()
                return .success
            }
            snapshot = entries
        }
    }

    private func performManagedWrite(
        _ snapshot: [HistoryEntry]
    ) async -> (PersistenceOutcome, Int) {
        persistenceGeneration += 1
        let generation = persistenceGeneration
        pendingPersistenceTask?.cancel()
        let outcome = await startPersistence(
            snapshot,
            generation: generation,
            managesFailureState: false
        ).value
        return (outcome, generation)
    }

    private func markPersistenceFailure(_ intent: RetryIntent) {
        retryIntent = intent
        persistenceErrorMessage =
            "Не удалось сохранить изменения истории. Проверь доступ к диску и повтори сохранение."
    }

    private func clearPersistenceFailure() {
        retryIntent = nil
        persistenceErrorMessage = nil
    }

    private static func mergedEntries(
        _ first: [HistoryEntry],
        _ second: [HistoryEntry]
    ) -> [HistoryEntry] {
        var seen = Set<HistoryEntry.ID>()
        return Array(
            (first + second)
                .sorted { $0.createdAt > $1.createdAt }
                .filter { seen.insert($0.id).inserted }
                .prefix(maximumEntryCount)
        )
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("Rusifikator", isDirectory: true)
            .appendingPathComponent("history.json")
    }
}

private enum HistoryStoreError: LocalizedError {
    case persistenceFailed

    var errorDescription: String? {
        "Не удалось сохранить историю на диске."
    }
}

private actor HistoryPersistence: HistoryPersisting {
    private let fileURL: URL
    private let fileManager = FileManager.default
    private var latestGeneration = 0

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load(maximumEntryCount: Int) -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(
                  [HistoryEntry].self,
                  from: data
              )
        else {
            return []
        }
        return Array(decoded.prefix(maximumEntryCount))
    }

    func persist(
        _ entries: [HistoryEntry],
        generation: Int
    ) throws {
        try Task.checkCancellation()
        guard generation >= latestGeneration else {
            return
        }
        latestGeneration = generation

        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )

        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
