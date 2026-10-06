import Foundation
import MatchesApplication
import MatchesDomain
import SQLiteSupport

/// `TemplateRepository` and the `TemplateList` reader over the device's SQLite DB (spec 008).
///
/// `templates` holds one row per active template; deleting a template removes its row. `setup_key`
/// is the setup's identity in canonical form (players sorted, targets by value), and its UNIQUE
/// constraint backs the one-active-template-per-setup invariant. The setup itself is stored as
/// JSON so the targets keep the form they were entered in.
public final class SQLiteTemplateRepository: TemplateRepository, TemplateListReader {
    static let migrations: [(id: String, sql: String)] = [
        ("matches.templates.001", """
            CREATE TABLE templates (
                template_id   TEXT    PRIMARY KEY NOT NULL,
                setup_key     TEXT    NOT NULL UNIQUE,
                first_player  TEXT    NOT NULL,
                second_player TEXT    NOT NULL,
                setup         BLOB    NOT NULL,
                use_count     INTEGER NOT NULL CHECK (use_count >= 1),
                last_used_at  REAL    NOT NULL
            );
            CREATE INDEX templates_first ON templates (first_player);
            CREATE INDEX templates_second ON templates (second_player);
            CREATE INDEX templates_order ON templates (use_count DESC, last_used_at DESC);
            """),
    ]

    private let db: SQLiteDatabase
    private let now: @Sendable () -> Date

    public init(db: SQLiteDatabase, now: @escaping @Sendable () -> Date = Date.init) throws {
        self.db = db
        self.now = now
        try db.migrate(Self.migrations)
    }

    // MARK: TemplateRepository

    public func getById(_ id: TemplateID) throws -> Template? {
        try db.query("SELECT template_id, setup, use_count FROM templates WHERE template_id = ?",
                     [TemplateId(id).value]).first.map(Self.template)
    }

    public func save(_ template: Template) throws {
        if template.isDeleted {
            try db.execute("DELETE FROM templates WHERE template_id = ?", [template.id.value])
            return
        }
        // Only a use (or creating / combining) counts as using it; a merge moving a player does not.
        let used = template.uncommittedEvents.contains { event in
            if case .playerMoved = event { return false }
            return true
        }
        do {
            try db.execute("""
                INSERT INTO templates (template_id, setup_key, first_player, second_player, setup, use_count, last_used_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (template_id) DO UPDATE SET
                    setup_key = excluded.setup_key, first_player = excluded.first_player,
                    second_player = excluded.second_player, setup = excluded.setup, use_count = excluded.use_count,
                    last_used_at = CASE WHEN ? THEN excluded.last_used_at ELSE templates.last_used_at END
                """,
                [template.id.value, Self.key(template.setup), template.setup.first.value, template.setup.second.value,
                 try JSONEncoder().encode(template.setup), template.useCount.value, now(), used])
        } catch let error as SQLiteError where error.isConstraintViolation {
            throw TemplateRepositoryError.setupAlreadyHasTemplate
        }
    }

    public func findBySetup(_ setup: Setup) throws -> Template? {
        try db.query("SELECT template_id, setup, use_count FROM templates WHERE setup_key = ?", [Self.key(setup)])
            .first.map(Self.template)
    }

    public func findByPlayer(_ player: PlayerRef) throws -> [Template] {
        let id = PlayerId(player).value
        return try db.query("""
            SELECT template_id, setup, use_count FROM templates WHERE first_player = ? OR second_player = ?
            ORDER BY rowid
            """, [id, id]).map(Self.template)
    }

    // MARK: TemplateListReader

    public func templateList() throws -> [TemplateListEntry] {
        try db.query("""
            SELECT template_id, setup, use_count FROM templates
            ORDER BY use_count DESC, last_used_at DESC, rowid DESC
            """
        ).map { row in
            let t = try Self.template(row)
            guard let id = UUID(uuidString: t.id.value) else { throw Self.malformed(row) }
            return TemplateListEntry(id: id, setup: t.setup, useCount: t.useCount.value)
        }
    }

    // MARK: Mapping

    private static func template(_ row: SQLiteRow) throws -> Template {
        guard let rawId = row.string("template_id"), case .success(let id) = TemplateId.create(rawId),
              let payload = row.data("setup"), let count = row.int("use_count"),
              case .success(let useCount) = UseCount.create(count)
        else { throw malformed(row) }
        return Template.restore(id: id, setup: try JSONDecoder().decode(Setup.self, from: payload), useCount: useCount)
    }

    private static func malformed(_ row: SQLiteRow) -> SQLiteError {
        SQLiteError(code: -1, message: "Malformed template row \(row.string("template_id") ?? "?")")
    }

    /// The setup's identity, matching `Setup` equality: unordered players, targets by value.
    static func key(_ setup: Setup) -> String {
        let players = [setup.first.value, setup.second.value].sorted().joined(separator: "|")
        let style = switch setup.style {
        case .mostFramesWins: "most"
        case .raceTo(let t): "race:\(t.value)"
        case .sets(let sets, let frames): "sets:\(sets.value):\(frames.value)"
        }
        return [players, setup.game.rawValue, style, setup.breakRule.rawValue].joined(separator: "/")
    }
}
