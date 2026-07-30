import Foundation
import XCTest
@testable import Rusifikator

@MainActor
final class HistoryStoreTests: XCTestCase {
    func testRecordsOnlyFiveNewestEntriesAndPersistsThem() throws {
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

        let restored = HistoryStore(fileURL: fileURL)
        XCTAssertEqual(restored.entries, store.entries)
    }

    func testClearRemovesEntriesFromMemoryAndDisk() throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = HistoryStore(fileURL: fileURL)
        store.record(source: "Исходник", result: "Результат")

        store.clear()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(HistoryStore(fileURL: fileURL).entries.isEmpty)
    }

    func testCorruptedFileLoadsAsEmptyAndCanBeReplaced() throws {
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
        XCTAssertEqual(
            HistoryStore(fileURL: fileURL).entries.map(\.source),
            ["Исходник"]
        )
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("RusifikatorTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("history.json")
    }
}
