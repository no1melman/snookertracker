import Foundation
import SQLiteSupport
import UpgradeApplication
import UpgradeDomain

/// The Upgrade table on the device's SQLite DB: the single cached edition row.
enum UpgradeSchema {
    static let migrations: [(id: String, sql: String)] = [
        ("upgrade.001.edition", """
            CREATE TABLE edition (
                id         INTEGER PRIMARY KEY CHECK (id = 1),
                status     TEXT NOT NULL,
                changed_at REAL NOT NULL
            );
            """),
    ]
}

/// `EditionStore` as the single `edition` row. No row yet means Free (`Edition.initial`).
public final class SQLiteEditionStore: EditionStore {
    private let db: SQLiteDatabase

    public init(db: SQLiteDatabase) throws {
        self.db = db
        try db.migrate(UpgradeSchema.migrations)
    }

    public func get() throws -> Edition {
        guard let row = try db.query("SELECT status FROM edition WHERE id = 1").first,
              let status = row.string("status").flatMap(EditionStatus.init(rawValue:))
        else { return .initial }
        return .reconstitute(status: status)
    }

    public func save(_ edition: Edition) throws {
        try db.execute("""
            INSERT INTO edition (id, status, changed_at) VALUES (1, ?, ?)
            ON CONFLICT (id) DO UPDATE SET status = excluded.status, changed_at = excluded.changed_at
            """, [edition.status.rawValue, Date()])
    }
}
