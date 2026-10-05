import Foundation
import MatchesApplication
import MatchesPublished
import SQLiteSupport

/// `MatchEventHistory` over the match event store: replays stored events as the published (Stage 2)
/// envelope. The stored type, schema version and payload *are* the published contract
/// (`MatchEventWire`), so nothing is re-encoded; Stage 1 events are filtered out.
public final class SQLiteMatchEventHistory: MatchEventHistory {
    private let db: SQLiteDatabase

    /// `store` guarantees the event-store schema exists on `db`.
    public init(db: SQLiteDatabase, store: SQLiteMatchEventStore) {
        _ = store
        self.db = db
    }

    public func streamVersions() throws -> [UUID: Int] {
        var versions: [UUID: Int] = [:]
        for row in try db.query("SELECT stream_id, version FROM match_streams") {
            if let id = row.uuid("stream_id"), let version = row.int("version") { versions[id] = version }
        }
        return versions
    }

    public func publishedEvents(of match: UUID, after version: Int) throws -> [MatchEventPublished] {
        try db.query("""
            SELECT version, event_id, origin_device, type, schema_version, payload, occurred_at
            FROM match_events WHERE stream_id = ? AND version > ? ORDER BY version
            """, [match.uuidString, version]
        ).compactMap { row in
            guard let streamVersion = row.int("version"), let eventId = row.uuid("event_id"),
                  let device = row.uuid("origin_device"), let type = row.string("type"),
                  let schema = row.int("schema_version"), let payload = row.data("payload"),
                  let occurredAt = row.date("occurred_at")
            else { throw SQLiteError(code: -1, message: "Malformed event row in stream \(match)") }
            let event = try MatchEventWire.decode(type: type, schemaVersion: schema, payload: payload)
            guard MatchEventWire.isPublished(event) else { return nil }
            return MatchEventPublished(
                matchId: match, eventId: eventId, originDevice: device, streamVersion: streamVersion,
                type: type, schemaVersion: schema, payload: payload, occurredAt: occurredAt)
        }
    }
}
