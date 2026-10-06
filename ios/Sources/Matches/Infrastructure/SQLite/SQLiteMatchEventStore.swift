import Foundation
import MatchesApplication
import MatchesDomain
import SQLiteSupport

/// The match event store (spec 006): append-only, one stream per match, on the device's SQLite DB.
///
/// - `match_events`: every event ever recorded. `UNIQUE(stream_id, version)` plus a version check in
///   the append transaction give optimistic concurrency. Each event carries its own id and origin
///   device (no single-writer assumption) and a versioned wire format (`MatchEventWire`).
/// - `match_streams`: one row per stream with its current version and what `findLive` /
///   `findByPlayer` filter on. Written in the same transaction as the events; derived data only.
public final class SQLiteMatchEventStore: Sendable {
    /// What the stream index records about a match, updated on every append.
    public struct StreamSummary: Sendable {
        public let startedAt: Date
        public let players: [String]
        public let status: String
        public let isLive: Bool

        public init(startedAt: Date, players: [String], status: String, isLive: Bool) {
            self.startedAt = startedAt
            self.players = players
            self.status = status
            self.isLive = isLive
        }
    }

    public enum StoreError: Error, Equatable, Sendable {
        case concurrencyConflict(stream: String, expected: Int, actual: Int)
    }

    static let migrations: [(id: String, sql: String)] = [
        ("matches.001.event-store", """
            CREATE TABLE match_events (
                sequence       INTEGER PRIMARY KEY AUTOINCREMENT,
                stream_id      TEXT    NOT NULL,
                version        INTEGER NOT NULL,
                event_id       TEXT    NOT NULL UNIQUE,
                origin_device  TEXT    NOT NULL,
                type           TEXT    NOT NULL,
                schema_version INTEGER NOT NULL,
                payload        BLOB    NOT NULL,
                occurred_at    REAL    NOT NULL,
                recorded_at    REAL    NOT NULL,
                UNIQUE (stream_id, version)
            );
            CREATE TABLE match_streams (
                stream_id     TEXT    PRIMARY KEY NOT NULL,
                version       INTEGER NOT NULL,
                started_at    REAL    NOT NULL,
                first_player  TEXT    NOT NULL,
                second_player TEXT    NOT NULL,
                status        TEXT    NOT NULL,
                is_live       INTEGER NOT NULL
            );
            CREATE INDEX match_streams_live ON match_streams (is_live, started_at);
            CREATE INDEX match_streams_first ON match_streams (first_player);
            CREATE INDEX match_streams_second ON match_streams (second_player);
            """),
    ]

    private let db: SQLiteDatabase
    /// Stamped on every event this device records.
    public let originDevice: UUID

    public init(db: SQLiteDatabase, originDevice: UUID) throws {
        self.db = db
        self.originDevice = originDevice
        try db.migrate(Self.migrations)
    }

    /// Appends `events` to `stream` if it is still at `expectedVersion` (0 for a new stream), all or nothing.
    public func append(
        _ events: [MatchEvent], to stream: String, expectedVersion: Int, summary: StreamSummary,
        recordedAt: Date = Date()
    ) throws -> [RecordedMatchEvent] {
        guard !events.isEmpty else { return [] }
        do {
            return try db.transaction {
                let actual = try db.query("SELECT version FROM match_streams WHERE stream_id = ?", [stream]).first?.int("version") ?? 0
                guard actual == expectedVersion else {
                    throw StoreError.concurrencyConflict(stream: stream, expected: expectedVersion, actual: actual)
                }
                var recorded: [RecordedMatchEvent] = []
                for (offset, event) in events.enumerated() {
                    let wire = try MatchEventWire.encode(event)
                    let r = RecordedMatchEvent(
                        eventId: UUID(), originDevice: originDevice, streamVersion: expectedVersion + offset + 1, event: event)
                    try db.execute("""
                        INSERT INTO match_events
                            (stream_id, version, event_id, origin_device, type, schema_version, payload, occurred_at, recorded_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        [stream, r.streamVersion, r.eventId, r.originDevice, wire.type, wire.schemaVersion,
                         wire.payload, event.at, recordedAt])
                    recorded.append(r)
                }
                let players = summary.players + Array(repeating: "", count: max(0, 2 - summary.players.count))
                try db.execute("""
                    INSERT INTO match_streams (stream_id, version, started_at, first_player, second_player, status, is_live)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT (stream_id) DO UPDATE SET
                        version = excluded.version, status = excluded.status, is_live = excluded.is_live,
                        first_player = excluded.first_player, second_player = excluded.second_player
                    """,
                    [stream, expectedVersion + events.count, summary.startedAt, players[0], players[1],
                     summary.status, summary.isLive])
                return recorded
            }
        } catch let error as SQLiteError where error.isConstraintViolation {
            // Another writer got the same version in first (backstop for the check above).
            let actual = (try? db.query("SELECT version FROM match_streams WHERE stream_id = ?", [stream]).first?.int("version")) ?? nil
            throw StoreError.concurrencyConflict(stream: stream, expected: expectedVersion, actual: actual ?? -1)
        }
    }

    /// The whole stream, in order (rehydration and export). Empty for an unknown stream.
    public func readStream(_ stream: String) throws -> [RecordedMatchEvent] {
        try db.query("""
            SELECT version, event_id, origin_device, type, schema_version, payload
            FROM match_events WHERE stream_id = ? ORDER BY version
            """, [stream]
        ).map { row in
            guard let version = row.int("version"), let eventId = row.uuid("event_id"),
                  let device = row.uuid("origin_device"), let type = row.string("type"),
                  let schema = row.int("schema_version"), let payload = row.data("payload")
            else { throw SQLiteError(code: -1, message: "Malformed event row in stream \(stream)") }
            return RecordedMatchEvent(
                eventId: eventId, originDevice: device, streamVersion: version,
                event: try MatchEventWire.decode(type: type, schemaVersion: schema, payload: payload))
        }
    }

    /// Every stream id, in creation order (export).
    public func allStreams() throws -> [String] {
        try db.query("SELECT stream_id FROM match_streams ORDER BY rowid").compactMap { $0.string("stream_id") }
    }

    /// Live streams, oldest started first, ties by creation order.
    func liveStreams() throws -> [String] {
        try db.query("SELECT stream_id FROM match_streams WHERE is_live = 1 ORDER BY started_at, rowid")
            .compactMap { $0.string("stream_id") }
    }

    /// Streams with that player on either side, oldest started first.
    func streams(withPlayer player: String) throws -> [String] {
        try db.query("""
            SELECT stream_id FROM match_streams WHERE first_player = ? OR second_player = ?
            ORDER BY started_at, rowid
            """, [player, player]
        ).compactMap { $0.string("stream_id") }
    }
}

/// `MatchRepository` over the event store: rehydrates from the stream, saves by appending.
public final class EventSourcedMatchRepository: MatchRepository {
    private let store: SQLiteMatchEventStore

    public init(store: SQLiteMatchEventStore) {
        self.store = store
    }

    public func getById(_ id: MatchID) throws -> Match? {
        try load(MatchId(id).value)
    }

    @discardableResult
    public func save(_ match: Match) throws -> [RecordedMatchEvent] {
        let summary = SQLiteMatchEventStore.StreamSummary(
            startedAt: match.startTime.date,
            players: [match.setup.first.value, match.setup.second.value],
            status: match.status.rawValue,
            isLive: match.status.isLive)
        do {
            return try store.append(match.uncommittedEvents, to: match.id.value, expectedVersion: match.version, summary: summary)
        } catch SQLiteMatchEventStore.StoreError.concurrencyConflict(_, let expected, let actual) {
            throw MatchRepositoryError.concurrencyConflict(
                match: UUID(uuidString: match.id.value) ?? UUID(), expectedVersion: expected, actualVersion: actual)
        }
    }

    public func findLive() throws -> [Match] {
        try store.liveStreams().compactMap(load)
    }

    public func findByPlayer(_ player: PlayerRef) throws -> [Match] {
        try store.streams(withPlayer: PlayerId(player).value).compactMap(load)
    }

    private func load(_ stream: String) throws -> Match? {
        let history = try store.readStream(stream).map(\.event)
        guard !history.isEmpty else { return nil }
        switch Match.rehydrate(history) {
        case .success(let match): return match
        case .failure(let error):
            throw MatchRepositoryError.corruptStream(match: UUID(uuidString: stream) ?? UUID(), detail: "\(error)")
        }
    }
}

/// `MatchSettingsStore` as one JSON row in a per-device settings table.
public final class SQLiteMatchSettingsStore: MatchSettingsStore {
    private let db: SQLiteDatabase

    public init(db: SQLiteDatabase) throws {
        self.db = db
        try db.migrate([("matches.002.settings", """
            CREATE TABLE match_settings (id INTEGER PRIMARY KEY CHECK (id = 1), schema_version INTEGER NOT NULL, payload BLOB NOT NULL);
            """)])
    }

    public func get() throws -> MatchSettingsValues? {
        guard let payload = try db.query("SELECT payload FROM match_settings WHERE id = 1").first?.data("payload") else { return nil }
        return try JSONDecoder().decode(MatchSettingsValues.self, from: payload)
    }

    public func save(_ settings: MatchSettingsValues) throws {
        try db.execute("""
            INSERT INTO match_settings (id, schema_version, payload) VALUES (1, 1, ?)
            ON CONFLICT (id) DO UPDATE SET schema_version = excluded.schema_version, payload = excluded.payload
            """, [try JSONEncoder().encode(settings)])
    }
}
