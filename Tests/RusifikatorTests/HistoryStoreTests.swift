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

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("RusifikatorTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("history.json")
    }
}
