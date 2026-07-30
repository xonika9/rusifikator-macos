import Foundation
import XCTest
@testable import Rusifikator

@MainActor
final class HistoryStoreTests: XCTestCase {
    func testRecordsOnlyFiveNewestEntriesAndPersistsThem() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = HistoryStore(fileURL: fileURL)

        for index in 1...6 {
            store.record(
                source: "Исходник \(index)",
                result: "Результат \(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        XCTAssertEqual(store.entries.map(\.source), [
            "Исходник 6",
            "Исходник 5",
            "Исходник 4",
            "Исходник 3",
            "Исходник 2"
        ])

        await store.flushPendingPersistence()
        let restored = HistoryStore(fileURL: fileURL)
        await restored.waitForInitialLoad()
        XCTAssertEqual(restored.entries, store.entries)
    }

    func testClearRemovesEntriesFromMemoryAndDisk() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = HistoryStore(fileURL: fileURL)
        store.record(source: "Исходник", result: "Результат")
        await store.flushPendingPersistence()

        try await store.clear()

        XCTAssertTrue(store.entries.isEmpty)
        let restored = HistoryStore(fileURL: fileURL)
        await restored.waitForInitialLoad()
        XCTAssertTrue(restored.entries.isEmpty)
    }

    func testCorruptedFileLoadsAsEmptyAndCanBeReplaced() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)

        let store = HistoryStore(fileURL: fileURL)

        XCTAssertTrue(store.entries.isEmpty)
        store.record(source: "Исходник", result: "Результат")
        await store.flushPendingPersistence()
        let restored = HistoryStore(fileURL: fileURL)
        await restored.waitForInitialLoad()
        XCTAssertEqual(
            restored.entries.map(\.source),
            ["Исходник"]
        )
    }

    func testClearFailureKeepsEntriesVisible() async throws {
        let fileURL = URL(fileURLWithPath: "/dev/null/history.json")
        let store = HistoryStore(fileURL: fileURL)
        store.record(source: "Исходник", result: "Результат")

        do {
            try await store.clear()
            XCTFail("Expected the disk write to fail")
        } catch {
            XCTAssertEqual(store.entries.map(\.source), ["Исходник"])
        }
    }

    func testRecordDuringInitialLoadMergesWithExistingHistory() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existing = HistoryEntry(
            source: "Старый исходник",
            result: "Старый результат",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        try JSONEncoder().encode([existing]).write(to: fileURL)

        let store = HistoryStore(fileURL: fileURL)
        store.record(
            source: "Новый исходник",
            result: "Новый результат",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        await store.flushPendingPersistence()

        XCTAssertEqual(
            store.entries.map(\.source),
            ["Новый исходник", "Старый исходник"]
        )
        let restored = HistoryStore(fileURL: fileURL)
        await restored.waitForInitialLoad()
        XCTAssertEqual(restored.entries, store.entries)
    }

    func testClearPreservesEntriesRecordedWhileDiskWriteIsPending() async throws {
        let oldEntry = HistoryEntry(
            source: "Старый исходник",
            result: "Старый результат",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let persistence = ControlledHistoryPersistence(entries: [oldEntry])
        await persistence.blockPersistCalls([1])
        let store = HistoryStore(persistence: persistence)
        await store.waitForInitialLoad()

        let clearTask = Task {
            try await store.clear()
        }
        await persistence.waitForPersistCallCount(1)
        store.record(
            source: "Новый исходник",
            result: "Новый результат",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        await persistence.releasePersistCall(1)
        try await clearTask.value
        await store.flushPendingPersistence()

        XCTAssertEqual(store.entries.map(\.source), ["Новый исходник"])
        let persistedSources = await persistence.persistedEntries().map(\.source)
        XCTAssertEqual(persistedSources, ["Новый исходник"])
    }

    func testFlushWaitsForTaskThatReplacesPendingPersistence() async {
        let persistence = ControlledHistoryPersistence()
        await persistence.blockPersistCalls([1, 2])
        let store = HistoryStore(persistence: persistence)
        await store.waitForInitialLoad()

        store.record(source: "Первый", result: "Результат")
        await persistence.waitForPersistCallCount(1)

        let flushCompleted = expectation(description: "Flush completed")
        let flushTask = Task {
            await store.flushPendingPersistence()
            flushCompleted.fulfill()
        }
        await Task.yield()

        store.record(source: "Второй", result: "Результат")
        await persistence.waitForPersistCallCount(2)
        await persistence.releasePersistCall(1)

        let earlyResult = await XCTWaiter().fulfillment(
            of: [flushCompleted],
            timeout: 0.05
        )
        XCTAssertEqual(earlyResult, .timedOut)

        await persistence.releasePersistCall(2)
        await flushTask.value
    }

    func testFailedClearRetryPersistsEmptySnapshotAndCompletesClear() async {
        let oldEntry = HistoryEntry(
            source: "Старый исходник",
            result: "Старый результат",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let persistence = ControlledHistoryPersistence(entries: [oldEntry])
        await persistence.failPersistCalls([1])
        let store = HistoryStore(persistence: persistence)
        await store.waitForInitialLoad()

        do {
            try await store.clear()
            XCTFail("Expected the clear write to fail")
        } catch {
            XCTAssertEqual(store.entries, [oldEntry])
        }

        await persistence.blockPersistCalls([2])
        store.retryPersistence()
        await persistence.waitForPersistCallCount(2)

        XCTAssertTrue(store.isRetryingPersistence)
        let retrySnapshot = await persistence.persistedSnapshot(forCall: 2)
        XCTAssertEqual(retrySnapshot, [])

        await persistence.releasePersistCall(2)
        await store.flushPendingPersistence()

        XCTAssertFalse(store.isRetryingPersistence)
        XCTAssertNil(store.persistenceErrorMessage)
        XCTAssertTrue(store.entries.isEmpty)
        let persistedEntries = await persistence.persistedEntries()
        XCTAssertTrue(persistedEntries.isEmpty)
    }

    func testSuccessfulRecordPersistencePreservesFailedClearRetry() async {
        let oldEntry = HistoryEntry(
            source: "Старый исходник",
            result: "Старый результат",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let persistence = ControlledHistoryPersistence(entries: [oldEntry])
        await persistence.failPersistCalls([1])
        let store = HistoryStore(persistence: persistence)
        await store.waitForInitialLoad()

        do {
            try await store.clear()
            XCTFail("Expected the clear write to fail")
        } catch {
            XCTAssertEqual(store.entries, [oldEntry])
        }

        store.record(
            source: "Новый исходник",
            result: "Новый результат",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        await store.flushPendingPersistence()
        XCTAssertNotNil(store.persistenceErrorMessage)

        store.retryPersistence()
        await store.flushPendingPersistence()

        XCTAssertEqual(store.entries.map(\.source), ["Новый исходник"])
        let persistedSources = await persistence.persistedEntries().map(\.source)
        XCTAssertEqual(persistedSources, ["Новый исходник"])
        XCTAssertNil(store.persistenceErrorMessage)
    }

    func testConcurrentClearCallsShareOnePersistenceOperation() async throws {
        let persistence = ControlledHistoryPersistence()
        await persistence.blockPersistCalls([2])
        let store = HistoryStore(persistence: persistence)
        await store.waitForInitialLoad()
        store.record(source: "Исходник", result: "Результат")
        await store.flushPendingPersistence()

        let firstClear = Task { try await store.clear() }
        await persistence.waitForPersistCallCount(2)
        let secondClear = Task { try await store.clear() }
        await Task.yield()

        let callCountWhileBlocked = await persistence.persistCallCount()
        XCTAssertEqual(callCountWhileBlocked, 2)
        await persistence.releasePersistCall(2)
        try await firstClear.value
        try await secondClear.value

        let finalCallCount = await persistence.persistCallCount()
        XCTAssertEqual(finalCallCount, 2)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testRetryInFlightIsDeduplicatedAndExposesEveryTransition() async {
        let persistence = ControlledHistoryPersistence()
        await persistence.failPersistCalls([1, 2])
        let store = HistoryStore(persistence: persistence)
        await store.waitForInitialLoad()

        store.record(source: "Исходник", result: "Результат")
        await store.flushPendingPersistence()

        XCTAssertNotNil(store.persistenceErrorMessage)

        await persistence.blockPersistCalls([2])
        store.retryPersistence()
        store.retryPersistence()
        await persistence.waitForPersistCallCount(2)

        XCTAssertTrue(store.isRetryingPersistence)
        let callCountDuringRetry = await persistence.persistCallCount()
        XCTAssertEqual(callCountDuringRetry, 2)

        await persistence.releasePersistCall(2)
        await store.flushPendingPersistence()

        XCTAssertFalse(store.isRetryingPersistence)
        XCTAssertNotNil(store.persistenceErrorMessage)

        store.retryPersistence()
        await store.flushPendingPersistence()

        XCTAssertFalse(store.isRetryingPersistence)
        XCTAssertNil(store.persistenceErrorMessage)
        let persistedSources = await persistence.persistedEntries().map(\.source)
        XCTAssertEqual(persistedSources, ["Исходник"])
    }

    func testFlushWaitsWhileClearOwesCorrectivePersistence() async throws {
        let oldEntry = HistoryEntry(
            source: "Старый исходник",
            result: "Старый результат",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let persistence = ControlledHistoryPersistence(entries: [oldEntry])
        await persistence.blockPersistCalls([1, 3])
        let store = HistoryStore(persistence: persistence)
        await store.waitForInitialLoad()

        let clearTask = Task {
            try await store.clear()
        }
        await persistence.waitForPersistCallCount(1)

        store.record(
            source: "Новый исходник",
            result: "Новый результат",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        await persistence.waitForPersistCallCount(2)

        let flushCompleted = expectation(description: "Flush completed")
        let flushTask = Task {
            await store.flushPendingPersistence()
            flushCompleted.fulfill()
        }

        await persistence.releasePersistCall(1)
        await persistence.waitForPersistCallCount(3)

        let earlyResult = await XCTWaiter().fulfillment(
            of: [flushCompleted],
            timeout: 0.05
        )
        XCTAssertEqual(earlyResult, .timedOut)

        await persistence.releasePersistCall(3)
        try await clearTask.value
        await flushTask.value

        XCTAssertEqual(store.entries.map(\.source), ["Новый исходник"])
        let persistedSources = await persistence.persistedEntries().map(\.source)
        XCTAssertEqual(persistedSources, ["Новый исходник"])
    }

    func testCorrectiveClearFailureThrowsAndRetriesExactSnapshot() async {
        let oldEntry = HistoryEntry(
            source: "Старый исходник",
            result: "Старый результат",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let persistence = ControlledHistoryPersistence(entries: [oldEntry])
        await persistence.blockPersistCalls([1])
        await persistence.failPersistCalls([3])
        let store = HistoryStore(persistence: persistence)
        await store.waitForInitialLoad()

        let clearTask = Task {
            try await store.clear()
        }
        await persistence.waitForPersistCallCount(1)
        store.record(
            source: "Новый исходник",
            result: "Новый результат",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        await persistence.waitForPersistCallCount(2)
        await persistence.releasePersistCall(1)

        do {
            try await clearTask.value
            XCTFail("Expected the corrective write to fail")
        } catch {
            XCTAssertEqual(store.entries.map(\.source), ["Новый исходник"])
            XCTAssertNotNil(store.persistenceErrorMessage)
        }

        await persistence.blockPersistCalls([4])
        store.retryPersistence()
        await persistence.waitForPersistCallCount(4)

        XCTAssertTrue(store.isRetryingPersistence)
        let retrySources = await persistence.persistedSnapshot(forCall: 4).map(\.source)
        XCTAssertEqual(retrySources, ["Новый исходник"])

        await persistence.releasePersistCall(4)
        await store.flushPendingPersistence()

        XCTAssertFalse(store.isRetryingPersistence)
        XCTAssertNil(store.persistenceErrorMessage)
        XCTAssertEqual(store.entries.map(\.source), ["Новый исходник"])
        let persistedSources = await persistence.persistedEntries().map(\.source)
        XCTAssertEqual(persistedSources, ["Новый исходник"])
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("RusifikatorTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("history.json")
    }

}

private actor ControlledHistoryPersistence: HistoryPersisting {
    private var entries: [HistoryEntry]
    private var latestGeneration = 0
    private var persistCalls = 0
    private var blockedCalls: Set<Int> = []
    private var failingCalls: Set<Int> = []
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var callCountWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var snapshotsByCall: [Int: [HistoryEntry]] = [:]

    init(entries: [HistoryEntry] = []) {
        self.entries = entries
    }

    func blockPersistCalls(_ calls: Set<Int>) {
        blockedCalls = calls
    }

    func failPersistCalls(_ calls: Set<Int>) {
        failingCalls = calls
    }

    func waitForPersistCallCount(_ expected: Int) async {
        guard persistCalls < expected else {
            return
        }
        await withCheckedContinuation { continuation in
            callCountWaiters[expected, default: []].append(continuation)
        }
    }

    func load(maximumEntryCount: Int) -> [HistoryEntry] {
        Array(entries.prefix(maximumEntryCount))
    }

    func persist(
        _ entries: [HistoryEntry],
        generation: Int
    ) async throws {
        persistCalls += 1
        let call = persistCalls
        snapshotsByCall[call] = entries
        resumeCallCountWaiters()
        if blockedCalls.contains(call) {
            await withCheckedContinuation { continuation in
                continuations[call] = continuation
            }
        }
        guard generation >= latestGeneration else {
            return
        }
        latestGeneration = generation
        if failingCalls.remove(call) != nil {
            throw ControlledPersistenceError.writeFailed
        }
        self.entries = entries
    }

    func releasePersistCall(_ call: Int) {
        blockedCalls.remove(call)
        continuations.removeValue(forKey: call)?.resume()
    }

    func persistedEntries() -> [HistoryEntry] {
        entries
    }

    func persistCallCount() -> Int {
        persistCalls
    }

    func persistedSnapshot(forCall call: Int) -> [HistoryEntry] {
        snapshotsByCall[call] ?? []
    }

    private func resumeCallCountWaiters() {
        let reachedCounts = callCountWaiters.keys.filter { $0 <= persistCalls }
        for count in reachedCounts {
            callCountWaiters.removeValue(forKey: count)?.forEach {
                $0.resume()
            }
        }
    }
}

private enum ControlledPersistenceError: Error {
    case writeFailed
}
