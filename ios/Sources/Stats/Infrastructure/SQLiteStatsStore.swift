import Foundation
import MatchesPublished
import SQLiteSupport
import StatsApplication

/// Stats' tables on the device database (spec 013). Stats never reads Matches' or Players' tables.
///
/// - `stats_match_events`: every published match event taken in, keyed by event id (idempotent).
/// - `stats_match_checkpoints`: the highest Matches stream version taken in per match (catch-up).
/// - `stats_match_records`: the folded `MatchRecord` per match as versioned JSON, with the columns
///   History sorts and filters on.
/// - `stats_players`: names, colours, archived, removed and merges from the player events.
public final class SQLiteStatsStore: StatsStore {
    static let migrations: [(id: String, sql: String)] = [
        ("stats.001.match-records", """
            CREATE TABLE stats_match_events (
                event_id       TEXT    PRIMARY KEY NOT NULL,
                match_id       TEXT    NOT NULL,
                stream_version INTEGER NOT NULL,
                origin_device  TEXT    NOT NULL,
                type           TEXT    NOT NULL,
                schema_version INTEGER NOT NULL,
                payload        BLOB    NOT NULL,
                occurred_at    REAL    NOT NULL
            );
            CREATE INDEX stats_match_events_match ON stats_match_events (match_id, stream_version);
            CREATE TABLE stats_match_checkpoints (
                match_id TEXT    PRIMARY KEY NOT NULL,
                version  INTEGER NOT NULL
            );
            CREATE TABLE stats_match_records (
                match_id       TEXT    PRIMARY KEY NOT NULL,
                status         TEXT    NOT NULL,
                started_at     REAL    NOT NULL,
                schema_version INTEGER NOT NULL,
                record         BLOB    NOT NULL
            );
            CREATE INDEX stats_match_records_started ON stats_match_records (started_at);
            CREATE TABLE stats_players (
                player_id   TEXT    PRIMARY KEY NOT NULL,
                name        TEXT    NOT NULL,
                colour      TEXT    NOT NULL,
                archived    INTEGER NOT NULL,
                removed     INTEGER NOT NULL,
                merged_into TEXT
            );
            """),
    ]

    private let db: SQLiteDatabase

    public init(db: SQLiteDatabase) throws {
        self.db = db
        try db.migrate(Self.migrations)
    }

    public func inTransaction<T>(_ body: () throws -> T) throws -> T { try db.transaction(body) }

    // MARK: Event log

    public func append(_ e: MatchEventPublished) throws -> Bool {
        if try !db.query("SELECT 1 AS x FROM stats_match_events WHERE event_id = ?", [e.eventId]).isEmpty { return false }
        try db.execute("""
            INSERT INTO stats_match_events
                (event_id, match_id, stream_version, origin_device, type, schema_version, payload, occurred_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, [e.eventId, e.matchId, e.streamVersion, e.originDevice, e.type, e.schemaVersion, e.payload, e.occurredAt])
        return true
    }

    public func events(of match: UUID) throws -> [MatchEventPublished] {
        try db.query("""
            SELECT event_id, stream_version, origin_device, type, schema_version, payload, occurred_at
            FROM stats_match_events WHERE match_id = ? ORDER BY stream_version
            """, [match]
        ).map { row in
            guard let id = row.uuid("event_id"), let version = row.int("stream_version"),
                  let device = row.uuid("origin_device"), let type = row.string("type"),
                  let schema = row.int("schema_version"), let payload = row.data("payload"),
                  let at = row.date("occurred_at")
            else { throw SQLiteError(code: -1, message: "Malformed stats event row for match \(match)") }
            return MatchEventPublished(
                matchId: match, eventId: id, originDevice: device, streamVersion: version,
                type: type, schemaVersion: schema, payload: payload, occurredAt: at)
        }
    }

    public func loggedMatches() throws -> [UUID] {
        try db.query("SELECT DISTINCT match_id FROM stats_match_events").compactMap { $0.uuid("match_id") }
    }

    public func checkpoints() throws -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for row in try db.query("SELECT match_id, version FROM stats_match_checkpoints") {
            if let id = row.uuid("match_id"), let v = row.int("version") { result[id] = v }
        }
        return result
    }

    public func setCheckpoint(_ match: UUID, version: Int) throws {
        try db.execute("""
            INSERT INTO stats_match_checkpoints (match_id, version) VALUES (?, ?)
            ON CONFLICT (match_id) DO UPDATE SET version = excluded.version
            """, [match, version])
    }

    // MARK: Records

    private static let recordSchemaVersion = 1

    public func save(_ record: MatchRecord) throws {
        try db.execute("""
            INSERT INTO stats_match_records (match_id, status, started_at, schema_version, record) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT (match_id) DO UPDATE SET
                status = excluded.status, started_at = excluded.started_at,
                schema_version = excluded.schema_version, record = excluded.record
            """, [record.id, record.status.rawValue, record.startedAt, Self.recordSchemaVersion, try Self.encoder.encode(record)])
    }

    public func deleteRecord(_ match: UUID) throws {
        try db.execute("DELETE FROM stats_match_records WHERE match_id = ?", [match])
    }

    public func deleteAllRecords() throws {
        try db.execute("DELETE FROM stats_match_records")
    }

    /// Records written by an older record schema are skipped; `rebuildAll` re-folds them from the log.
    public func allRecords() throws -> [MatchRecord] {
        try db.query("SELECT record FROM stats_match_records WHERE schema_version = ? ORDER BY started_at DESC",
                     [Self.recordSchemaVersion])
            .compactMap { $0.data("record") }
            .map { try Self.decoder.decode(MatchRecord.self, from: $0) }
    }

    // MARK: Players

    public func save(_ p: StatsPlayer) throws {
        try db.execute("""
            INSERT INTO stats_players (player_id, name, colour, archived, removed, merged_into) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT (player_id) DO UPDATE SET
                name = excluded.name, colour = excluded.colour, archived = excluded.archived,
                removed = excluded.removed, merged_into = excluded.merged_into
            """, [p.id, p.name, p.colour, p.isArchived, p.isRemoved, p.mergedInto])
    }

    public func allPlayers() throws -> [StatsPlayer] {
        try db.query("SELECT player_id, name, colour, archived, removed, merged_into FROM stats_players").compactMap { row in
            guard let id = row.uuid("player_id"), let name = row.string("name"), let colour = row.string("colour") else { return nil }
            return StatsPlayer(id: id, name: name, colour: colour, isArchived: row.int("archived") == 1,
                               isRemoved: row.int("removed") == 1, mergedInto: row.uuid("merged_into"))
        }
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = .sortedKeys
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}
