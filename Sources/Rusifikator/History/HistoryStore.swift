import Foundation
import Observation

@MainActor
struct HistoryEntry: Codable, Equatable, Identifiable {
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

@Observable
@MainActor
final class HistoryStore: HistoryRecording {
    static let maximumEntryCount = 5

    private(set) var entries: [HistoryEntry]

    @ObservationIgnored
    private let fileURL: URL

    @ObservationIgnored
    private let fileManager: FileManager

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.entries = Self.loadEntries(
            from: self.fileURL,
            fileManager: fileManager
        )
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
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func persist() {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // History is best-effort and must never block text processing.
        }
    }

    private static func loadEntries(
        from fileURL: URL,
        fileManager: FileManager
    ) -> [HistoryEntry] {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(
                  [HistoryEntry].self,
                  from: data
              )
        else {
            return []
        }
        return Array(decoded.prefix(maximumEntryCount))
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
