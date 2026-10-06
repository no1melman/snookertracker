import Foundation
import SQLiteSupport
import StatsApplication
import StatsDomain

/// `SeriesSummaryLog` over the device's SQLite DB (spec 017): one row per series and month issued.
/// Rows outlive a deleted series harmlessly (its id is never reused).
public final class SQLiteSeriesSummaryLog: SeriesSummaryLog {
    static let migrations: [(id: String, sql: String)] = [
        ("stats.series.summary.001", """
            CREATE TABLE series_summaries_issued (
                series_id TEXT NOT NULL,
                month     TEXT NOT NULL,
                issued_at REAL NOT NULL,
                PRIMARY KEY (series_id, month)
            );
            """),
    ]

    private let db: SQLiteDatabase

    public init(db: SQLiteDatabase) throws {
        self.db = db
        try db.migrate(Self.migrations)
    }

    public func isIssued(_ series: SeriesId, _ month: Month) throws -> Bool {
        try !db.query("SELECT 1 FROM series_summaries_issued WHERE series_id = ? AND month = ?",
                      [series.value, month.description]).isEmpty
    }

    public func markIssued(_ series: SeriesId, _ month: Month, at: Date) throws {
        try db.execute("""
            INSERT INTO series_summaries_issued (series_id, month, issued_at) VALUES (?, ?, ?)
            ON CONFLICT (series_id, month) DO NOTHING
            """, [series.value, month.description, at])
    }
}
