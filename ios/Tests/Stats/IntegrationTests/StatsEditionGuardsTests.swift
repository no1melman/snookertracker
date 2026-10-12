import EventDispatch
import Foundation
import MatchesPublished
import Observation
import PlayersPublished
import SQLiteSupport
import StatsApplication
import StatsInfrastructure
import StatsPublished
import Testing
import UpgradePublished

// Outside-in (spec 027): published match and player events go through the dispatcher into Stats'
// real projection over the real SQLite store (wrapped to count writes), with a `FixedEdition`
// flipped by hand. Free hides matches beyond the newest `FreeLimits.visibleEndedMatches` and locks
// head-to-head and stats; the projection keeps building, and unlocking shows everything with no
// rebuild.

private let callum = UUID()
private let asher = UUID()
private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
private let visible = FreeLimits.standard.visibleEndedMatches
private let everything = PastMatchesFilter(showCancelled: true, includeArchivedPlayers: true)

/// The real SQLite store, counting every record write: an unlock must not write (no rebuild).
private final class CountingStore: StatsEventLog, MatchRecordStore, StatsPlayerStore, StatsTransactions, @unchecked Sendable {
    let inner: SQLiteStatsStore
    private(set) var recordWrites = 0
    private(set) var rebuilds = 0

    init(_ inner: SQLiteStatsStore) { self.inner = inner }

    func append(_ event: MatchEventPublished) throws -> Bool { try inner.append(event) }
    func events(of match: UUID) throws -> [MatchEventPublished] { try inner.events(of: match) }
    func loggedMatches() throws -> [UUID] { try inner.loggedMatches() }
    func checkpoints() throws -> [UUID: Int] { try inner.checkpoints() }
    func setCheckpoint(_ match: UUID, version: Int) throws { try inner.setCheckpoint(match, version: version) }
    func save(_ record: MatchRecord) throws { recordWrites += 1; try inner.save(record) }
    func deleteRecord(_ match: UUID) throws { recordWrites += 1; try inner.deleteRecord(match) }
    func deleteAllRecords() throws { rebuilds += 1; try inner.deleteAllRecords() }
    func allRecords() throws -> [MatchRecord] { try inner.allRecords() }
    func save(_ player: StatsPlayer) throws { try inner.save(player) }
    func allPlayers() throws -> [StatsPlayer] { try inner.allPlayers() }
    func inTransaction<T>(_ body: () throws -> T) throws -> T { try inner.inTransaction(body) }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}

@MainActor
private final class World {
    let db: SQLiteDatabase
    let dispatcher = EventDispatcher()
    let store: CountingStore
    let edition: FixedEdition
    let stats: MatchRecordsProjection
    private var started = 0

    init(db: SQLiteDatabase? = nil, edition: FixedEdition = .free) throws {
        self.db = try db ?? .inMemory()
        self.edition = edition
        store = CountingStore(try SQLiteStatsStore(db: self.db))
        stats = try MatchRecordsProjection(store: store, edition: edition)
        stats.subscribe(to: dispatcher)
        player("PlayerAdded", callum, ["name": "Callum", "colour": "blue"])
        player("PlayerAdded", asher, ["name": "Asher", "colour": "orange"])
    }

    func player(_ type: String, _ id: UUID, _ fields: [String: Any] = [:]) {
        var body = fields
        body["playerId"] = id.uuidString
        let payload = try! JSONSerialization.data(withJSONObject: body)
        dispatcher.dispatch([PlayerEventPublished(playerId: id, type: type, schemaVersion: 1, payload: payload, occurredAt: t0)])
    }

    private func match(_ id: UUID, _ version: Int, _ type: String, _ body: [String: Any], at: Date) {
        let payload = try! JSONSerialization.data(withJSONObject: body)
        dispatcher.dispatch([MatchEventPublished(
            matchId: id, eventId: UUID(), originDevice: UUID(), streamVersion: version,
            type: type, schemaVersion: 1, payload: payload, occurredAt: at)])
    }

    /// A race-to-3 pool match, each a day after the last; `frames` lists each frame's winner.
    /// Finished (the leader wins) unless `cancelled`.
    @discardableResult
    func play(_ frames: [UUID], cancelled: Bool = false) -> UUID {
        let id = UUID()
        started += 1
        let start = t0.addingTimeInterval(Double(started) * 86_400)
        let side = { (p: UUID) -> [String: Any] in ["player": p.uuidString, "colour": p == callum ? "blue" : "orange"] }
        match(id, 1, "MatchStarted", [
            "setup": ["first": callum.uuidString, "second": asher.uuidString, "game": "pool",
                      "style": ["raceTo": ["_0": ["raceTo": 3]]], "breakRule": "alternate"],
            "first": side(callum), "second": side(asher), "at": start.timeIntervalSince1970,
        ], at: start)
        for (i, w) in frames.enumerated() {
            let at = start.addingTimeInterval(Double(i + 1) * 600)
            match(id, i + 2, "FrameWon", ["player": w.uuidString, "frameNumber": i + 1, "setNumber": 1,
                                          "length": 600, "at": at.timeIntervalSince1970], at: at)
        }
        let end = start.addingTimeInterval(Double(frames.count + 1) * 600)
        if cancelled {
            match(id, frames.count + 2, "MatchCancelled", ["at": end.timeIntervalSince1970], at: end)
            return id
        }
        let (fa, fb) = (frames.filter { $0 == callum }.count, frames.filter { $0 == asher }.count)
        match(id, frames.count + 2, "MatchFinished", [
            "result": ["win": ["_0": side(fa > fb ? callum : asher)]],
            "score": ["firstFrames": fa, "secondFrames": fb], "endedAt": end.timeIntervalSince1970,
            "length": Double(frames.count) * 600, "shortOfTarget": false,
        ], at: end)
        return id
    }

    /// `count` finished matches Callum wins 3–1, oldest first.
    @discardableResult
    func playMany(_ count: Int) -> [UUID] {
        (0..<count).map { _ in play([callum, asher, callum, callum]) }
    }

    func unlock() {
        edition.status = .unlocked
        dispatcher.dispatch([AppUnlockedPublished(occurredAt: t0)])
    }
}

@MainActor
@Suite("Stats edition guards integration")
struct StatsEditionGuardsTests {
    @Test func projectionsKeepBuildingWhileFree() throws {
        let world = try World()
        let ids = world.playMany(visible + 3)

        #expect(try world.store.allRecords().count == visible + 3)
        #expect(Set(try world.store.allRecords().map(\.id)) == Set(ids))
        #expect(world.stats.lastError == nil)
        // AverageFrameTime and AverageMatchLength (the stale prompt, S28) stay free.
        #expect(world.stats.averageFrameTime(callum) == 600)
    }

    @Test func freeShowsTheNewestEndedMatchesAndCountsTheRestAsHidden() throws {
        let world = try World()
        let ids = world.playMany(visible + 2)

        let rows = world.stats.pastMatches(PastMatchesFilter())
        #expect(rows.count == visible)
        #expect(rows.map(\.id) == Array(ids.reversed().prefix(visible)))
        #expect(world.stats.hiddenMatchCount(PastMatchesFilter()) == 2)
        // The timeline only for the visible matches.
        #expect(world.stats.timeline(ids.last!) != nil)
        #expect(world.stats.timeline(ids[0]) == nil)
        #expect(world.stats.timeline(ids[1]) == nil)
    }

    @Test func theVisibleMatchesDoNotShiftWithTheFilter() throws {
        let world = try World()
        let older = world.playMany(visible)
        let cancelled = world.play([callum], cancelled: true)

        // The cancelled match is among the newest, so it takes a place even when the filter hides it.
        #expect(world.stats.pastMatches(everything).first?.id == cancelled)
        #expect(world.stats.pastMatches(everything).count == visible)
        #expect(world.stats.pastMatches(PastMatchesFilter()).count == visible - 1)
        #expect(world.stats.hiddenMatchCount(PastMatchesFilter()) == 1)
        #expect(world.stats.timeline(older[0]) == nil)
    }

    @Test func freeLocksHeadToHeadAndStats() throws {
        let world = try World()
        world.playMany(3)

        #expect(world.stats.headToHead(callum, asher) == .none)
        let report = world.stats.stats(StatsFilter(pointOfView: callum, grouping: .opponent))
        #expect(report.isLocked)
        #expect(report.overall.matches == 0 && report.groups.isEmpty && report.pointOfView == nil)
        #expect(world.stats.isStatsLocked)
    }

    @Test func unlockShowsEverythingWithNoRebuild() throws {
        let world = try World()
        let ids = world.playMany(visible + 2)
        let writes = world.store.recordWrites

        world.unlock()

        #expect(world.store.recordWrites == writes)
        #expect(world.store.rebuilds == 0)
        #expect(world.stats.pastMatches(PastMatchesFilter()).count == visible + 2)
        #expect(world.stats.hiddenMatchCount(PastMatchesFilter()) == 0)
        #expect(world.stats.timeline(ids[0]) != nil)
        let h2h = world.stats.headToHead(callum, asher)
        #expect(h2h.won == visible + 2 && h2h.framesWon == 3 * (visible + 2))
        let report = world.stats.stats(StatsFilter(pointOfView: callum))
        #expect(!report.isLocked && !world.stats.isStatsLocked)
        #expect(report.overall.won == visible + 2)
    }

    @Test func revokingHidesAgainAndDeletesNothing() throws {
        let db = try SQLiteDatabase.inMemory()
        let world = try World(db: db, edition: .unlocked)
        world.playMany(visible + 1)
        #expect(world.stats.pastMatches(PastMatchesFilter()).count == visible + 1)

        world.edition.status = .free
        world.dispatcher.dispatch([AppLockedPublished(occurredAt: t0)])
        #expect(world.stats.pastMatches(PastMatchesFilter()).count == visible)
        #expect(world.stats.hiddenMatchCount(PastMatchesFilter()) == 1)

        let relaunched = try World(db: db, edition: .free)
        #expect(try relaunched.store.allRecords().count == visible + 1)
        #expect(relaunched.stats.pastMatches(PastMatchesFilter()).count == visible)
    }

    @Test func anUnlockRefreshesObservingViews() throws {
        let world = try World()
        world.playMany(visible + 1)
        let changed = Flag()
        withObservationTracking {
            _ = world.stats.pastMatches(PastMatchesFilter())
            _ = world.stats.isStatsLocked
        } onChange: {
            changed.set()
        }
        world.unlock()
        #expect(changed.isSet)
    }
}
