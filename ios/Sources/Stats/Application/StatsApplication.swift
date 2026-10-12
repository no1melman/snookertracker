import EventDispatch
import Foundation
import MatchesPublished
import Observation
import PlayersPublished
import UpgradePublished

/// The match-record projections (spec 013): takes in Matches' and Players' published events, keeps
/// its own log of them, folds each match into a `MatchRecord`, and answers `PastMatches` and
/// `MatchTimeline`. No aggregate: a read side only (ADR-0003).
///
/// Catch-up: a device can hold matches recorded before Stats existed (or Stats' tables can be lost).
/// `catchUp(from:)` asks Matches' open-host `MatchEventHistory` for every stream past Stats' own
/// per-stream checkpoint, so the log converges on Matches' published history; event ids make it
/// idempotent with live dispatch.
@MainActor @Observable
public final class MatchRecordsProjection: MatchHistoryQuery {
    @ObservationIgnored private let store: any StatsStore
    private(set) var records: [UUID: MatchRecord] = [:]
    private(set) var players: [UUID: StatsPlayer] = [:]
    /// The last projection failure (logged, never thrown into a Matches or Players command).
    @ObservationIgnored public private(set) var lastError: (any Error)?
    /// Weekdays (S19, S28) are read from a match's start time in this calendar.
    @ObservationIgnored let calendar: Calendar
    /// Upgrade's `CurrentEdition` open host (ADR-0011): read it before a guarded action. Unlocked
    /// (no limits) until the composition root hands over the device's edition.
    @ObservationIgnored public var edition: any CurrentEdition

    public init(store: any StatsStore, calendar: Calendar = .current, edition: any CurrentEdition = FixedEdition.unlocked) throws {
        self.store = store
        self.edition = edition
        self.calendar = calendar
        records = Dictionary(uniqueKeysWithValues: try store.allRecords().map { ($0.id, $0) })
        players = Dictionary(uniqueKeysWithValues: try store.allPlayers().map { ($0.id, $0) })
    }

    /// Subscribes to both contexts' published events. Dispatch happens on the main actor.
    public func subscribe(to dispatcher: EventDispatcher) {
        dispatcher.subscribe(MatchEventPublished.self) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
        }
        dispatcher.subscribe(PlayerEventPublished.self) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
        }
    }

    // MARK: Taking in events

    public func receive(_ event: MatchEventPublished) {
        record { try self.take([event], match: event.matchId, checkpoint: event.streamVersion) }
    }

    public func receive(_ event: PlayerEventPublished) {
        record {
            let fact = try PlayerFact.decode(event)
            try self.apply(fact)
        }
    }

    /// Takes in every published match event Stats has not seen yet. Returns how many matches changed.
    @discardableResult
    public func catchUp(from history: any MatchEventHistory) throws -> Int {
        let seen = try store.checkpoints()
        var changed = 0
        for (match, version) in try history.streamVersions() where version > seen[match, default: 0] {
            let events = try history.publishedEvents(of: match, after: seen[match, default: 0])
            try take(events, match: match, checkpoint: version)
            changed += 1
        }
        return changed
    }

    /// Players as they stand now (state-stored in Players, so there is no event history to replay).
    /// Fills in players Stats has not heard of and refreshes names, colours and archived; merges and
    /// removals Stats learnt from events are kept.
    public func seedPlayers(_ current: [StatsPlayer]) throws {
        try store.inTransaction {
            for p in current {
                var player = players[p.id] ?? p
                player.name = p.name
                player.colour = p.colour
                player.isArchived = p.isArchived
                if player != players[p.id] {
                    try store.save(player)
                    players[p.id] = player
                }
            }
        }
    }

    /// Rebuilds every record from Stats' own event log.
    public func rebuildAll() throws {
        let rebuilt = try store.inTransaction {
            try store.deleteAllRecords()
            var all: [UUID: MatchRecord] = [:]
            for match in try store.loggedMatches() {
                if let r = try fold(match) {
                    try store.save(r)
                    all[match] = r
                }
            }
            return all
        }
        records = rebuilt
    }

    private func take(_ events: [MatchEventPublished], match: UUID, checkpoint: Int) throws {
        let record: MatchRecord? = try store.inTransaction {
            var added = false
            for e in events {
                if try store.append(e) { added = true }
            }
            let seen = try store.checkpoints()[match, default: 0]
            if checkpoint > seen { try store.setCheckpoint(match, version: checkpoint) }
            guard added else { return records[match] }
            let r = try fold(match)
            if let r { try store.save(r) } else { try store.deleteRecord(match) }
            return r
        }
        if records[match] != record { records[match] = record }
    }

    private func fold(_ match: UUID) throws -> MatchRecord? {
        let facts = try store.events(of: match).map(MatchFact.decode)
        return MatchRecord.fold(id: match, facts)
    }

    private func apply(_ fact: PlayerFact) throws {
        func change(_ id: UUID, _ body: (inout StatsPlayer) -> Void) throws {
            var p = players[id] ?? StatsPlayer(id: id, name: "Unknown player", colour: "gray")
            body(&p)
            try store.save(p)
            players[id] = p
        }
        switch fact {
        case .added(let id, let name, let colour): try change(id) { $0.name = name; $0.colour = colour }
        case .renamed(let id, let name): try change(id) { $0.name = name }
        case .colourChanged(let id, let colour): try change(id) { $0.colour = colour }
        case .merged(let kept, let foldedIn): try change(foldedIn) { $0.mergedInto = kept }
        case .archived(let id): try change(id) { $0.isArchived = true }
        case .unarchived(let id): try change(id) { $0.isArchived = false }
        case .removed(let id): try change(id) { $0.isRemoved = true }
        case .ignored: break
        }
    }

    private func record(_ body: () throws -> Void) {
        do { try body() } catch { lastError = error }
    }

    // MARK: Queries

    public func pastMatches(_ filter: PastMatchesFilter) -> [PastMatchRow] {
        records.values
            .filter { $0.isEnded && ($0.status != .cancelled || filter.showCancelled) }
            .compactMap { r -> PastMatchRow? in
                let (a, b) = (resolve(r.first), resolve(r.second))
                if a.player.isRemoved || b.player.isRemoved { return nil }
                if !filter.includeArchivedPlayers, a.view.isArchived || b.view.isArchived { return nil }
                return row(r, a.view, b.view)
            }
            .sorted { ($0.startedAt, $0.id.uuidString) > ($1.startedAt, $1.id.uuidString) }
    }

    public func timeline(_ match: UUID) -> MatchTimeline? {
        guard let r = records[match], r.isEnded else { return nil }
        let (a, b) = (resolve(r.first).view, resolve(r.second).view)
        let side = { (id: UUID) in id == r.first.player ? a : b }
        let running = r.runningScores()
        let setsWon = { (s: MatchRecord.Score) in (s.firstSets ?? 0) + (s.secondSets ?? 0) }
        let frames = r.frames.enumerated().map { i, f in
            MatchTimeline.FrameEntry(
                number: f.number, setNumber: f.setNumber, winner: side(f.winner), breaker: f.breaker.map(side),
                frameTime: f.length, matchTime: r.matchTime(at: f.at), runningScore: Self.line(running[i]),
                wonSet: setsWon(running[i]) > (i > 0 ? setsWon(running[i - 1]) : 0))
        }
        var isSets = false
        if case .sets = r.style { isSets = true }
        return MatchTimeline(
            match: row(r, a, b), breakRule: r.breakRule, isSets: isSets, frames: frames,
            originalScore: r.endingScore.map(Self.line),
            corrections: r.corrections.map { .init(at: $0.at, before: Self.line($0.before), after: Self.line($0.after)) },
            markedFinishedAt: r.markedFinishedAt, shortOfTarget: r.shortOfTarget)
    }

    /// The player shown for a side: merges followed to the kept player; current name and colour.
    func resolve(_ side: MatchRecord.Side) -> (player: StatsPlayer, view: HistoryPlayer) {
        var p = players[side.player] ?? StatsPlayer(id: side.player, name: "Unknown player", colour: side.colour)
        var hops = 0
        while let next = p.mergedInto, let kept = players[next], hops < 16 { p = kept; hops += 1 }
        return (p, HistoryPlayer(id: p.id, name: p.name, colour: p.colour, isArchived: p.isArchived))
    }

    private func row(_ r: MatchRecord, _ a: HistoryPlayer, _ b: HistoryPlayer) -> PastMatchRow {
        let status: PastMatchStatus = switch r.status {
        case .abandoned: .abandoned
        case .cancelled: .cancelled
        default: .finished
        }
        var winner: UUID?
        if status == .finished, case .win(let w) = r.result { winner = w == r.first.player ? a.id : b.id }
        return PastMatchRow(
            id: r.id, startedAt: r.startedAt, endedAt: r.endedAt, length: r.length, game: r.game,
            style: Self.styleText(r.style), first: a, second: b,
            score: Self.line(r.score ?? MatchRecord.Score(first: 0, second: 0)), status: status,
            winner: winner, isDraw: status == .finished && r.result == .draw, isAltered: r.isAltered)
    }

    static func line(_ s: MatchRecord.Score) -> ScoreLine {
        ScoreLine(first: s.first, second: s.second, firstSets: s.firstSets, secondSets: s.secondSets)
    }

    static func styleText(_ style: MatchRecord.Style) -> String {
        func target(_ t: MatchRecord.Target, _ unit: String = "") -> String {
            if let m = t.bestOf { return "best of \(m)\(unit)" }
            return "race to \(t.raceTo)\(unit)"
        }
        switch style {
        case .mostFramesWins: return "Most frames"
        case .raceTo(let t): return target(t).capitalizedFirst
        case .sets(let sets, let frames): return (target(sets, " sets") + " · " + target(frames)).capitalizedFirst
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
