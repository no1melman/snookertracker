import Foundation
import PlayersApplication
import PlayersDomain
import SQLiteSupport

/// The Players tables on the device's SQLite DB. State-stored: one row per player, plus the Me row.
enum PlayersSchema {
    static let migrations: [(id: String, sql: String)] = [
        ("players.001.players", """
            CREATE TABLE players (
                id          TEXT PRIMARY KEY NOT NULL,
                name        TEXT NOT NULL,
                name_key    TEXT NOT NULL,
                colour      TEXT NOT NULL,
                status      TEXT NOT NULL,
                merged_into TEXT,
                added_at    REAL NOT NULL
            );
            CREATE INDEX players_name_key ON players (name_key);
            CREATE TABLE me_setting (id INTEGER PRIMARY KEY CHECK (id = 1), player_id TEXT);
            """),
    ]
}

/// `PlayerRepository` over the `players` table.
public final class SQLitePlayerRepository: PlayerRepository, PlayersListReader {
    private let db: SQLiteDatabase
    private let palette: Palette

    public init(db: SQLiteDatabase, palette: Palette = .standard) throws {
        self.db = db
        self.palette = palette
        try db.migrate(PlayersSchema.migrations)
    }

    public func getById(_ id: PlayerId) throws -> Player? {
        try db.query("SELECT * FROM players WHERE id = ?", [id.value]).first.flatMap(Self.player)
    }

    public func save(_ player: Player) throws {
        try db.execute("""
            INSERT INTO players (id, name, name_key, colour, status, merged_into, added_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET
                name = excluded.name, name_key = excluded.name_key, colour = excluded.colour,
                status = excluded.status, merged_into = excluded.merged_into
            """,
            [player.id.value, player.name.value, player.name.comparisonKey, player.colour.rawValue,
             player.status.rawValue, player.mergedInto?.value, Date()])
    }

    public func findByName(_ name: PlayerName) throws -> Player? {
        try db.query("""
            SELECT * FROM players WHERE name_key = ?
            ORDER BY CASE status WHEN 'active' THEN 0 WHEN 'archived' THEN 1 ELSE 2 END, added_at DESC
            LIMIT 1
            """, [name.comparisonKey]
        ).first.flatMap(Self.player)
    }

    public func nextUnusedColour() throws -> Colour {
        let used = try db.query("SELECT colour FROM players WHERE status IN ('active', 'archived')")
            .compactMap { $0.string("colour").flatMap(Colour.init(rawValue:)) }
        return palette.nextUnusedColour(given: used)
    }

    public func countActive() throws -> Int {
        try db.query("SELECT COUNT(*) AS n FROM players WHERE status = 'active'").first?.int("n") ?? 0
    }

    public func list() throws -> [PlayerListItem] {
        try db.query("""
            SELECT id, name, colour, status FROM players WHERE status IN ('active', 'archived')
            ORDER BY CASE status WHEN 'active' THEN 0 ELSE 1 END, name_key
            """
        ).compactMap { row in
            guard let id = row.uuid("id"), let name = row.string("name"), let colour = row.string("colour") else { return nil }
            return PlayerListItem(id: id, name: name, colour: colour, isArchived: row.string("status") == "archived")
        }
    }

    private static func player(_ row: SQLiteRow) -> Player? {
        guard let id = row.uuid("id"),
              case .success(let name) = PlayerName.create(row.string("name") ?? ""),
              let colour = row.string("colour").flatMap(Colour.init(rawValue:)),
              let status = row.string("status").flatMap(PlayerStatus.init(rawValue:))
        else { return nil }
        return Player.reconstitute(
            id: PlayerId(id), name: name, colour: colour, status: status,
            mergedInto: row.uuid("merged_into").map(PlayerId.init))
    }
}

/// `MeSettingStore` as the single `me_setting` row.
public final class SQLiteMeSettingStore: MeSettingStore {
    private let db: SQLiteDatabase

    public init(db: SQLiteDatabase) throws {
        self.db = db
        try db.migrate(PlayersSchema.migrations)
    }

    public func get() throws -> MeSetting {
        let me = try db.query("SELECT player_id FROM me_setting WHERE id = 1").first?.uuid("player_id")
        return .reconstitute(me: me.map(PlayerId.init))
    }

    public func save(_ setting: MeSetting) throws {
        try db.execute("""
            INSERT INTO me_setting (id, player_id) VALUES (1, ?)
            ON CONFLICT (id) DO UPDATE SET player_id = excluded.player_id
            """, [setting.me?.value])
    }
}
