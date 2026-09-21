import Foundation
import SQLite3

public struct PresetGenre: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let tags: String
    public let description: String
}

public struct PresetLyric: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let lyrics: String
}

public final class PresetRepository: Sendable {
    private let db: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.db = database
    }

    public func getGenres() -> [PresetGenre] {
        var results: [PresetGenre] = []
        do {
            let stmt = try db.prepare(sql: "SELECT id, name, tags, description FROM preset_genres ORDER BY name ASC;")
            defer { stmt.reset() }
            while stmt.step() == SQLITE_ROW {
                guard
                    let id = stmt.columnString(index: 0),
                    let name = stmt.columnString(index: 1),
                    let tags = stmt.columnString(index: 2),
                    let description = stmt.columnString(index: 3)
                else { continue }
                results.append(PresetGenre(id: id, name: name, tags: tags, description: description))
            }
        } catch {
            print("[PresetRepository] Get genres error: \(error)")
        }
        return results
    }

    public func getLyrics() -> [PresetLyric] {
        var results: [PresetLyric] = []
        do {
            let stmt = try db.prepare(sql: "SELECT id, title, lyrics FROM preset_lyrics ORDER BY title ASC;")
            defer { stmt.reset() }
            while stmt.step() == SQLITE_ROW {
                guard
                    let id = stmt.columnString(index: 0),
                    let title = stmt.columnString(index: 1),
                    let lyrics = stmt.columnString(index: 2)
                else { continue }
                results.append(PresetLyric(id: id, title: title, lyrics: lyrics))
            }
        } catch {
            print("[PresetRepository] Get lyrics error: \(error)")
        }
        return results
    }
}
