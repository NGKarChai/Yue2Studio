import Foundation
import SQLite3

public final class SQLiteDatabase: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()
    public let path: String

    public init(path: String) throws {
        self.path = path
        let parentDir = (path as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: parentDir) {
            try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        }

        var dbPointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &dbPointer, flags, nil) != SQLITE_OK {
            let errorMsg = dbPointer != nil ? String(cString: sqlite3_errmsg(dbPointer)) : "Unknown SQLite error"
            if let dbPointer = dbPointer {
                sqlite3_close(dbPointer)
            }
            throw NSError(domain: "SQLiteDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        self.db = dbPointer

        // Enable WAL mode for high performance concurrent reading
        try execute(sql: "PRAGMA journal_mode = WAL;")
        try execute(sql: "PRAGMA foreign_keys = ON;")
    }

    deinit {
        lock.lock()
        defer { lock.unlock() }
        if let db = db {
            sqlite3_close_v2(db)
        }
    }

    public func execute(sql: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let msg = errorMessage != nil ? String(cString: errorMessage!) : "Unknown error executing SQL"
            sqlite3_free(errorMessage)
            throw NSError(domain: "SQLiteDatabase", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    public func prepare(sql: String) throws -> SQLiteStatement {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            let msg = db != nil ? String(cString: sqlite3_errmsg(db)) : "Failed to prepare statement"
            throw NSError(domain: "SQLiteDatabase", code: 3, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return SQLiteStatement(statement: statement!, dbLock: lock)
    }

    public func transaction<T>(_ block: () throws -> T) throws -> T {
        try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            let result = try block()
            try execute(sql: "COMMIT TRANSACTION;")
            return result
        } catch {
            try? execute(sql: "ROLLBACK TRANSACTION;")
            throw error
        }
    }
}

public final class SQLiteStatement {
    private let statement: OpaquePointer
    private let dbLock: NSLock

    fileprivate init(statement: OpaquePointer, dbLock: NSLock) {
        self.statement = statement
        self.dbLock = dbLock
    }

    deinit {
        sqlite3_finalize(statement)
    }

    public func bind(index: Int32, value: String) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        if sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, transient) != SQLITE_OK {
            throw NSError(domain: "SQLiteStatement", code: 4, userInfo: [NSLocalizedDescriptionKey: "Error binding text"])
        }
    }

    public func bind(index: Int32, value: Int64) throws {
        if sqlite3_bind_int64(statement, index, value) != SQLITE_OK {
            throw NSError(domain: "SQLiteStatement", code: 4, userInfo: [NSLocalizedDescriptionKey: "Error binding int64"])
        }
    }

    public func bind(index: Int32, value: Double) throws {
        if sqlite3_bind_double(statement, index, value) != SQLITE_OK {
            throw NSError(domain: "SQLiteStatement", code: 4, userInfo: [NSLocalizedDescriptionKey: "Error binding double"])
        }
    }

    public func bindNull(index: Int32) throws {
        if sqlite3_bind_null(statement, index) != SQLITE_OK {
            throw NSError(domain: "SQLiteStatement", code: 4, userInfo: [NSLocalizedDescriptionKey: "Error binding null"])
        }
    }

    @discardableResult
    public func step() -> Int32 {
        return sqlite3_step(statement)
    }

    public func reset() {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
    }

    public func columnString(index: Int32) -> String? {
        guard let cStr = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cStr)
    }

    public func columnInt64(index: Int32) -> Int64 {
        return sqlite3_column_int64(statement, index)
    }

    public func columnDouble(index: Int32) -> Double {
        return sqlite3_column_double(statement, index)
    }
}
