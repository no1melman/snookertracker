import Foundation
import SQLite3

/// A failure reported by SQLite. `code` is the extended result code.
public struct SQLiteError: Error, CustomStringConvertible, Sendable {
    public let code: Int32
    public let message: String

    public init(code: Int32, message: String) {
        self.code = code
        self.message = message
    }

    public var isConstraintViolation: Bool { code & 0xFF == SQLITE_CONSTRAINT }

    public var description: String { "SQLite error \(code): \(message)" }
}

/// A value bound to, or read from, a statement.
public enum SQLiteValue: Hashable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

public protocol SQLiteBindable {
    var sqliteValue: SQLiteValue { get }
}

extension Int: SQLiteBindable { public var sqliteValue: SQLiteValue { .integer(Int64(self)) } }
extension Int64: SQLiteBindable { public var sqliteValue: SQLiteValue { .integer(self) } }
extension Bool: SQLiteBindable { public var sqliteValue: SQLiteValue { .integer(self ? 1 : 0) } }
extension Double: SQLiteBindable { public var sqliteValue: SQLiteValue { .real(self) } }
extension String: SQLiteBindable { public var sqliteValue: SQLiteValue { .text(self) } }
extension Data: SQLiteBindable { public var sqliteValue: SQLiteValue { .blob(self) } }
extension UUID: SQLiteBindable { public var sqliteValue: SQLiteValue { .text(uuidString) } }
/// Dates are stored as seconds since 1970 (REAL), so ordering in SQL is chronological.
extension Date: SQLiteBindable { public var sqliteValue: SQLiteValue { .real(timeIntervalSince1970) } }
extension SQLiteValue: SQLiteBindable { public var sqliteValue: SQLiteValue { self } }
extension Optional: SQLiteBindable where Wrapped: SQLiteBindable {
    public var sqliteValue: SQLiteValue { self?.sqliteValue ?? .null }
}

/// One result row, read by column name.
public struct SQLiteRow: Sendable {
    let values: [String: SQLiteValue]

    public subscript(_ column: String) -> SQLiteValue { values[column] ?? .null }

    public func int(_ column: String) -> Int? {
        if case .integer(let v) = self[column] { return Int(v) }
        return nil
    }

    public func double(_ column: String) -> Double? {
        switch self[column] {
        case .real(let v): v
        case .integer(let v): Double(v)
        default: nil
        }
    }

    public func string(_ column: String) -> String? {
        if case .text(let v) = self[column] { return v }
        return nil
    }

    public func data(_ column: String) -> Data? {
        switch self[column] {
        case .blob(let v): v
        case .text(let v): Data(v.utf8)
        default: nil
        }
    }

    public func date(_ column: String) -> Date? { double(column).map(Date.init(timeIntervalSince1970:)) }
    public func uuid(_ column: String) -> UUID? { string(column).flatMap(UUID.init(uuidString:)) }
}

/// One SQLite connection. Every call is serialised by a recursive lock, so a `transaction` can
/// call `execute`/`query` freely and the object can be shared across isolation domains.
public final class SQLiteDatabase: @unchecked Sendable {
    private let handle: OpaquePointer
    private let lock = NSRecursiveLock()

    /// Opens (creating if needed) the database file at `url`, in WAL mode.
    public convenience init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try self.init(path: url.path)
    }

    /// A private in-memory database (tests, previews).
    public static func inMemory() throws -> SQLiteDatabase { try SQLiteDatabase(path: ":memory:") }

    private init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open \(path)"
            if let db { sqlite3_close(db) }
            throw SQLiteError(code: rc, message: message)
        }
        handle = db
        sqlite3_extended_result_codes(db, 1)
        sqlite3_busy_timeout(db, 2_000)
        try execute("PRAGMA journal_mode = WAL")
        // WAL + NORMAL survives the app being killed; only a power loss can drop the last commit.
        try execute("PRAGMA synchronous = NORMAL")
        try execute("PRAGMA foreign_keys = ON")
        try execute("CREATE TABLE IF NOT EXISTS schema_migrations (id TEXT PRIMARY KEY NOT NULL, applied_at REAL NOT NULL)")
    }

    deinit { sqlite3_close_v2(handle) }

    // MARK: Statements

    /// Runs one or more statements with optional bindings (bindings apply to a single statement).
    public func execute(_ sql: String, _ arguments: [any SQLiteBindable] = []) throws {
        try lock.withLock {
            if arguments.isEmpty {
                var error: UnsafeMutablePointer<CChar>?
                let rc = sqlite3_exec(handle, sql, nil, nil, &error)
                if rc != SQLITE_OK {
                    let message = error.map { String(cString: $0) } ?? lastMessage
                    sqlite3_free(error)
                    throw SQLiteError(code: sqlite3_extended_errcode(handle), message: message)
                }
                return
            }
            try withStatement(sql, arguments) { stmt in
                while try step(stmt) {}
            }
        }
    }

    /// Runs a query and returns every row.
    public func query(_ sql: String, _ arguments: [any SQLiteBindable] = []) throws -> [SQLiteRow] {
        try lock.withLock {
            try withStatement(sql, arguments) { stmt in
                var rows: [SQLiteRow] = []
                while try step(stmt) { rows.append(row(stmt)) }
                return rows
            }
        }
    }

    /// Runs `body` in one `BEGIN IMMEDIATE` transaction: all of it commits, or none of it.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try lock.withLock {
            try execute("BEGIN IMMEDIATE")
            do {
                let result = try body()
                try execute("COMMIT")
                return result
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    /// Applies each migration once, in order, recording its id. Each context passes its own ids.
    public func migrate(_ migrations: [(id: String, sql: String)]) throws {
        try transaction {
            let applied = Set(try query("SELECT id FROM schema_migrations").compactMap { $0.string("id") })
            for migration in migrations where !applied.contains(migration.id) {
                try execute(migration.sql)
                try execute("INSERT INTO schema_migrations (id, applied_at) VALUES (?, ?)", [migration.id, Date()])
            }
        }
    }

    // MARK: Plumbing

    private var lastMessage: String { String(cString: sqlite3_errmsg(handle)) }

    private func withStatement<T>(_ sql: String, _ arguments: [any SQLiteBindable], _ body: (OpaquePointer) throws -> T) throws -> T {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw SQLiteError(code: sqlite3_extended_errcode(handle), message: lastMessage)
        }
        defer { sqlite3_finalize(stmt) }
        for (i, argument) in arguments.enumerated() {
            try bind(argument.sqliteValue, at: Int32(i + 1), in: stmt)
        }
        return try body(stmt)
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func bind(_ value: SQLiteValue, at index: Int32, in stmt: OpaquePointer) throws {
        let rc: Int32 = switch value {
        case .null: sqlite3_bind_null(stmt, index)
        case .integer(let v): sqlite3_bind_int64(stmt, index, v)
        case .real(let v): sqlite3_bind_double(stmt, index, v)
        case .text(let v): sqlite3_bind_text(stmt, index, v, -1, Self.transient)
        case .blob(let v): v.withUnsafeBytes { sqlite3_bind_blob(stmt, index, $0.baseAddress, Int32($0.count), Self.transient) }
        }
        guard rc == SQLITE_OK else { throw SQLiteError(code: rc, message: lastMessage) }
    }

    /// true while there is a row to read.
    private func step(_ stmt: OpaquePointer) throws -> Bool {
        switch sqlite3_step(stmt) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw SQLiteError(code: sqlite3_extended_errcode(handle), message: lastMessage)
        }
    }

    private func row(_ stmt: OpaquePointer) -> SQLiteRow {
        var values: [String: SQLiteValue] = [:]
        for i in 0..<sqlite3_column_count(stmt) {
            let name = String(cString: sqlite3_column_name(stmt, i))
            values[name] = switch sqlite3_column_type(stmt, i) {
            case SQLITE_INTEGER: .integer(sqlite3_column_int64(stmt, i))
            case SQLITE_FLOAT: .real(sqlite3_column_double(stmt, i))
            case SQLITE_TEXT: .text(String(cString: sqlite3_column_text(stmt, i)))
            case SQLITE_BLOB:
                .blob(sqlite3_column_blob(stmt, i).map { Data(bytes: $0, count: Int(sqlite3_column_bytes(stmt, i))) } ?? Data())
            default: .null
            }
        }
        return SQLiteRow(values: values)
    }
}

/// The per-device identity used to stamp events (origin device), created on first use.
public enum DeviceIdentity {
    public static func id(in db: SQLiteDatabase) throws -> UUID {
        try db.transaction {
            try db.execute("CREATE TABLE IF NOT EXISTS device (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)")
            if let existing = try db.query("SELECT value FROM device WHERE key = 'id'").first?.uuid("value") {
                return existing
            }
            let id = UUID()
            try db.execute("INSERT INTO device (key, value) VALUES ('id', ?)", [id])
            return id
        }
    }
}
