import Foundation
import SQLiteSupport
import StatsApplication
import StatsDomain

/// `SeriesRepository` and the `SeriesList` reader over the device's SQLite DB (spec 016).
///
/// `series` holds one row per series; `series_setups` its setups, keyed by the setup's identity
/// (`Setup.key`: players sorted, targets by value), with both players indexed for
/// `findContainingPlayer`. The setup itself is stored as JSON so targets keep their entered form.
/// Deleting a series removes its rows only: matches are never stored here.
public final class SQLiteSeriesRepository: SeriesRepository, SeriesListReader {
    static let migrations: [(id: String, sql: String)] = [
        ("stats.series.001", """
            CREATE TABLE series (
                series_id TEXT PRIMARY KEY NOT NULL,
                name      TEXT NOT NULL CHECK (length(trim(name)) > 0)
            );
            CREATE TABLE series_setups (
                series_id     TEXT    NOT NULL REFERENCES series (series_id) ON DELETE CASCADE,
                setup_key     TEXT    NOT NULL,
                first_player  TEXT    NOT NULL,
                second_player TEXT    NOT NULL,
                setup         BLOB    NOT NULL,
                position      INTEGER NOT NULL,
                PRIMARY KEY (series_id, setup_key)
            );
            CREATE INDEX series_setups_first ON series_setups (first_player);
            CREATE INDEX series_setups_second ON series_setups (second_player);
            """),
    ]

    private let db: SQLiteDatabase

    public init(db: SQLiteDatabase) throws {
        self.db = db
        try db.migrate(Self.migrations)
    }

    // MARK: SeriesRepository

    public func getById(_ id: SeriesId) throws -> Series? {
        try db.query("SELECT series_id, name FROM series WHERE series_id = ?", [id.value]).first.map(series)
    }

    public func save(_ series: Series) throws {
        try db.transaction {
            try db.execute("DELETE FROM series_setups WHERE series_id = ?", [series.id.value])
            if series.isDeleted {
                try db.execute("DELETE FROM series WHERE series_id = ?", [series.id.value])
                return
            }
            try db.execute("""
                INSERT INTO series (series_id, name) VALUES (?, ?)
                ON CONFLICT (series_id) DO UPDATE SET name = excluded.name
                """, [series.id.value, series.name.value])
            for (position, setup) in series.setups.enumerated() {
                try db.execute("""
                    INSERT INTO series_setups (series_id, setup_key, first_player, second_player, setup, position)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, [series.id.value, setup.key, setup.first, setup.second, try JSONEncoder().encode(setup), position])
            }
        }
    }

    public func findAll() throws -> [Series] {
        try db.query("SELECT series_id, name FROM series ORDER BY name COLLATE NOCASE, rowid").map(series)
    }

    public func findContainingPlayer(_ player: UUID) throws -> [Series] {
        try db.query("""
            SELECT series_id, name FROM series WHERE series_id IN (
                SELECT series_id FROM series_setups WHERE first_player = ? OR second_player = ?)
            ORDER BY rowid
            """, [player, player]).map(series)
    }

    // MARK: SeriesListReader

    public func seriesList() throws -> [SeriesListEntry] {
        try findAll().map { SeriesListEntry(id: $0.id.value, name: $0.name.value, setups: $0.setups) }
    }

    // MARK: Mapping

    private func series(_ row: SQLiteRow) throws -> Series {
        guard let rawId = row.string("series_id"), case .success(let id) = SeriesId.create(rawId),
              let rawName = row.string("name"), case .success(let name) = SeriesName.create(rawName)
        else { throw Self.malformed(row.string("series_id")) }
        let setups = try db.query(
            "SELECT setup FROM series_setups WHERE series_id = ? ORDER BY position", [id.value]
        ).map { r in
            guard let payload = r.data("setup") else { throw Self.malformed(rawId) }
            return try JSONDecoder().decode(Setup.self, from: payload)
        }
        return Series.restore(id: id, name: name, setups: setups)
    }

    private static func malformed(_ id: String?) -> SQLiteError {
        SQLiteError(code: -1, message: "Malformed series row \(id ?? "?")")
    }
}
