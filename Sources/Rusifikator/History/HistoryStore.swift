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

@Observable
@MainActor
final class HistoryStore: HistoryRecording {
    static let maximumEntryCount = 5

    private(set) var entries: [HistoryEntry]
    private(set) var isLoading = true

    @ObservationIgnored
    private let persistence: HistoryPersistence

    @ObservationIgnored
    private var initialLoadTask: Task<Void, Never>?

    @ObservationIgnored
    private var persistenceGeneration = 0

    @ObservationIgnored
    private var pendingPersistenceTask: Task<Void, Never>?

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let resolvedFileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.persistence = HistoryPersistence(
            fileURL: resolvedFileURL
        )
        self.entries = []
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
        persistenceGeneration += 1
        let generation = persistenceGeneration
        pendingPersistenceTask?.cancel()
        pendingPersistenceTask = nil

        try await persistence.persist([], generation: generation)
        guard persistenceGeneration == generation else {
            return
        }
        entries.removeAll()
    }

    func flushPendingPersistence() async {
        await initialLoadTask?.value
        await pendingPersistenceTask?.value
    }

    func waitForInitialLoad() async {
        await initialLoadTask?.value
    }

    private func persistInBackground() {
        persistenceGeneration += 1
        let generation = persistenceGeneration
        let snapshot = entries
        let persistence = persistence
        pendingPersistenceTask = Task {
            try? await persistence.persist(
                snapshot,
                generation: generation
            )
        }
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

private actor HistoryPersistence {
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
