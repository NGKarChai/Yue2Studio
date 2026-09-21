import Foundation
import SQLite3

public struct ModelItem: Identifiable, Sendable {
    public let id: String
    public let stage: String
    public let name: String
    public let repoId: String
    public let localPath: String
    public var status: String
    public let sizeBytes: Int64
    public let sha256: String

    public var isDownloaded: Bool {
        return status == "ready" || status == "downloaded"
    }
}

public final class ModelRegistryRepository: Sendable {
    private let db: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.db = database
    }

    public func getAll() -> [ModelItem] {
        var results: [ModelItem] = []
        do {
            let stmt = try db.prepare(sql: """
                SELECT id, stage, name, repo_id, local_path, status, size_bytes, sha256
                FROM model_registry ORDER BY stage ASC;
            """)
            defer { stmt.reset() }

            while stmt.step() == SQLITE_ROW {
                guard
                    let id = stmt.columnString(index: 0),
                    let stage = stmt.columnString(index: 1),
                    let name = stmt.columnString(index: 2),
                    let repoId = stmt.columnString(index: 3),
                    let localPath = stmt.columnString(index: 4),
                    let status = stmt.columnString(index: 5),
                    let sha256 = stmt.columnString(index: 7)
                else { continue }

                let sizeBytes = stmt.columnInt64(index: 6)

                results.append(ModelItem(
                    id: id,
                    stage: stage,
                    name: name,
                    repoId: repoId,
                    localPath: localPath,
                    status: status,
                    sizeBytes: sizeBytes,
                    sha256: sha256
                ))
            }
        } catch {
            print("[ModelRegistryRepository] Fetch error: \(error)")
        }
        return results
    }

    public func updateStatus(id: String, status: String) {
        do {
            let stmt = try db.prepare(sql: "UPDATE model_registry SET status = ? WHERE id = ?;")
            defer { stmt.reset() }
            try stmt.bind(index: 1, value: status)
            try stmt.bind(index: 2, value: id)
            stmt.step()
        } catch {
            print("[ModelRegistryRepository] Update error: \(error)")
        }
    }
}
