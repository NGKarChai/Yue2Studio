import Foundation
import SQLite3

public struct GenerationRecord: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let genreTags: String
    public let lyrics: String
    public let temperature: Double
    public let topP: Double
    public let cfgScale: Double
    public let maxTokens: Int
    public let seed: Int
    public let audioPath: String
    public let durationSeconds: Double
    public let status: String
    public let createdAt: String

    public init(
        id: String = UUID().uuidString,
        title: String,
        genreTags: String,
        lyrics: String,
        temperature: Double,
        topP: Double,
        cfgScale: Double,
        maxTokens: Int,
        seed: Int,
        audioPath: String,
        durationSeconds: Double,
        status: String = "completed",
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.title = title
        self.genreTags = genreTags
        self.lyrics = lyrics
        self.temperature = temperature
        self.topP = topP
        self.cfgScale = cfgScale
        self.maxTokens = maxTokens
        self.seed = seed
        self.audioPath = audioPath
        self.durationSeconds = durationSeconds
        self.status = status
        self.createdAt = createdAt
    }
}

public final class GenerationRepository: Sendable {
    private let db: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.db = database
    }

    public func insert(record: GenerationRecord) throws {
        let stmt = try db.prepare(sql: """
            INSERT INTO generation_history (
                id, title, genre_tags, lyrics, temperature, top_p, cfg_scale, max_tokens, seed, audio_path, duration_seconds, status, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """)
        defer { stmt.reset() }

        try stmt.bind(index: 1, value: record.id)
        try stmt.bind(index: 2, value: record.title)
        try stmt.bind(index: 3, value: record.genreTags)
        try stmt.bind(index: 4, value: record.lyrics)
        try stmt.bind(index: 5, value: record.temperature)
        try stmt.bind(index: 6, value: record.topP)
        try stmt.bind(index: 7, value: record.cfgScale)
        try stmt.bind(index: 8, value: Int64(record.maxTokens))
        try stmt.bind(index: 9, value: Int64(record.seed))
        try stmt.bind(index: 10, value: record.audioPath)
        try stmt.bind(index: 11, value: record.durationSeconds)
        try stmt.bind(index: 12, value: record.status)
        try stmt.bind(index: 13, value: record.createdAt)
        stmt.step()
    }

    public func getAll() -> [GenerationRecord] {
        var results: [GenerationRecord] = []
        do {
            let stmt = try db.prepare(sql: """
                SELECT id, title, genre_tags, lyrics, temperature, top_p, cfg_scale, max_tokens, seed, audio_path, duration_seconds, status, created_at
                FROM generation_history ORDER BY created_at DESC;
            """)
            defer { stmt.reset() }

            while stmt.step() == SQLITE_ROW {
                guard
                    let id = stmt.columnString(index: 0),
                    let title = stmt.columnString(index: 1),
                    let tags = stmt.columnString(index: 2),
                    let lyrics = stmt.columnString(index: 3),
                    let audioPath = stmt.columnString(index: 9),
                    let status = stmt.columnString(index: 11),
                    let createdAt = stmt.columnString(index: 12)
                else { continue }

                let temp = stmt.columnDouble(index: 4)
                let topP = stmt.columnDouble(index: 5)
                let cfg = stmt.columnDouble(index: 6)
                let maxTokens = Int(stmt.columnInt64(index: 7))
                let seed = Int(stmt.columnInt64(index: 8))
                let duration = stmt.columnDouble(index: 10)

                let record = GenerationRecord(
                    id: id,
                    title: title,
                    genreTags: tags,
                    lyrics: lyrics,
                    temperature: temp,
                    topP: topP,
                    cfgScale: cfg,
                    maxTokens: maxTokens,
                    seed: seed,
                    audioPath: audioPath,
                    durationSeconds: duration,
                    status: status,
                    createdAt: createdAt
                )
                results.append(record)
            }
        } catch {
            print("[GenerationRepository] Fetch error: \(error)")
        }
        return results
    }

    public func delete(id: String) {
        do {
            let stmt = try db.prepare(sql: "DELETE FROM generation_history WHERE id = ?;")
            defer { stmt.reset() }
            try stmt.bind(index: 1, value: id)
            stmt.step()
        } catch {
            print("[GenerationRepository] Delete error: \(error)")
        }
    }
}
