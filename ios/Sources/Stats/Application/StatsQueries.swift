import Foundation
import StatsDomain
import StatsPublished

/// `Stats(filter)` and the open-host queries for Matches (spec 014), read straight off the
/// match records: no aggregate, deciders computed from the frames as played (ADR-0003).
extension MatchRecordsProjection: StatsQuery, MatchStatsQueries {

    // MARK: Stats(filter)

    public func stats(_ filter: StatsFilter) -> StatsReport {
        let pov = resolve(player: filter.pointOfView)
        var overall = StatsFigures()
        var groups: [StatsGroup.Key: (opponent: HistoryPlayer?, figures: StatsFigures)] = [:]
        for m in counted(includeAbandoned: filter.includeAbandoned, includeArchivedPlayers: filter.includeArchivedPlayers) {
            guard let side = m.side(of: pov.id), matches(m, filter) else { continue }
            let figures = Self.figures(m.record, from: side)
            overall = overall + figures
            guard !filter.grouping.isEmpty else { continue }
            let opponent = filter.grouping.contains(.opponent) ? m.opponent(of: side) : nil
            let weekday = filter.grouping.contains(.weekday) ? m.weekday : nil
            let key = StatsGroup.Key(opponent: opponent?.id, weekday: weekday)
            groups[key, default: (opponent, StatsFigures())].figures = groups[key, default: (opponent, StatsFigures())].figures + figures
        }
        let sorted = groups.map { StatsGroup(opponent: $0.value.opponent, weekday: $0.key.weekday, figures: $0.value.figures) }
            .sorted { a, b in
                if filter.grouping == .weekday { return (a.weekday?.order ?? 0) < (b.weekday?.order ?? 0) }
                if a.figures.matches != b.figures.matches { return a.figures.matches > b.figures.matches }
                if (a.opponent?.name ?? "") != (b.opponent?.name ?? "") { return (a.opponent?.name ?? "") < (b.opponent?.name ?? "") }
                return (a.weekday?.order ?? 0) < (b.weekday?.order ?? 0)
            }
        return StatsReport(pointOfView: players[pov.id] == nil ? nil : pov, overall: overall, groups: sorted)
    }

    public func statsPlayers(includeArchived: Bool) -> [HistoryPlayer] {
        players.values
            .filter { !$0.isRemoved && $0.mergedInto == nil && (includeArchived || !$0.isArchived) }
            .map { HistoryPlayer(id: $0.id, name: $0.name, colour: $0.colour, isArchived: $0.isArchived) }
            .sorted { ($0.name.localizedLowercase, $0.id.uuidString) < ($1.name.localizedLowercase, $1.id.uuidString) }
    }

    public func statsChoices(for pointOfView: UUID, includeArchivedPlayers: Bool) -> StatsChoices {
        let pov = resolve(player: pointOfView).id
        var opponents: [UUID: HistoryPlayer] = [:], games: Set<String> = [], styles: [String: MatchRecord.Style] = [:]
        for m in counted(includeAbandoned: true, includeArchivedPlayers: includeArchivedPlayers) {
            guard let side = m.side(of: pov) else { continue }
            let o = m.opponent(of: side)
            opponents[o.id] = o
            games.insert(m.record.game)
            styles[Self.styleText(m.record.style)] = m.record.style
        }
        return StatsChoices(
            opponents: opponents.values.sorted { $0.name.localizedLowercase < $1.name.localizedLowercase },
            games: games.sorted(),
            styles: styles.map { StatsChoices.StyleChoice(style: $0.value, text: $0.key) }.sorted { $0.text < $1.text })
    }

    // MARK: Open host for Matches

    public func headToHead(_ a: UUID, _ b: UUID) -> HeadToHead {
        let f = stats(StatsFilter(pointOfView: a, opponent: b, includeArchivedPlayers: true)).overall
        return HeadToHead(won: f.won, drawn: f.drawn, lost: f.lost, framesWon: f.framesWon, framesLost: f.framesLost,
                          decidersWon: f.decidersWon, decidersLost: f.decidersLost)
    }

    public func averageFrameTime(_ player: UUID) -> TimeInterval? {
        let id = resolve(player: player).id
        var average = StatsFigures.Average()
        for m in counted(includeAbandoned: false, includeArchivedPlayers: true) where m.side(of: id) != nil {
            for f in m.record.frames where m.resolvedWinner(f) == id { average.add(f.length) }
        }
        return average.value
    }

    public func averageMatchLength(_ a: UUID, _ b: UUID, weekday: Int) -> TimeInterval? {
        let pair: Set = [resolve(player: a).id, resolve(player: b).id]
        var average = StatsFigures.Average()
        for m in counted(includeAbandoned: false, includeArchivedPlayers: true)
        where Set([m.first.id, m.second.id]) == pair && m.weekday.rawValue == weekday {
            if let length = m.record.length { average.add(length) }
        }
        return average.value
    }

    // MARK: Inclusion and figures

    /// A counted match with its sides as shown (merges followed).
    struct Counted {
        let record: MatchRecord
        let first: HistoryPlayer
        let second: HistoryPlayer
        let weekday: Weekday

        func side(of player: UUID) -> Deciders.Side? {
            if first.id == second.id { return nil }
            if first.id == player { return .first }
            if second.id == player { return .second }
            return nil
        }

        func opponent(of side: Deciders.Side) -> HistoryPlayer { side == .first ? second : first }

        func resolvedWinner(_ frame: MatchRecord.Frame) -> UUID {
            frame.winner == record.first.player ? first.id : second.id
        }

        /// A recorded player id as shown (merges followed).
        func shown(_ id: UUID) -> UUID {
            id == record.first.player ? first.id : id == record.second.player ? second.id : id
        }
    }

    /// The inclusion rules: finished always; abandoned opt-in; cancelled and live never; archived
    /// players' matches opt-in; removed players' matches never.
    func counted(includeAbandoned: Bool, includeArchivedPlayers: Bool) -> [Counted] {
        records.values.compactMap { r in
            switch r.status {
            case .finished: break
            case .abandoned where includeAbandoned: break
            default: return nil
            }
            let (a, b) = (resolve(r.first), resolve(r.second))
            if a.player.isRemoved || b.player.isRemoved { return nil }
            if !includeArchivedPlayers, a.view.isArchived || b.view.isArchived { return nil }
            return Counted(record: r, first: a.view, second: b.view, weekday: Weekday(of: r.startedAt, in: calendar))
        }
    }

    private func matches(_ m: Counted, _ filter: StatsFilter) -> Bool {
        if let o = filter.opponent, let side = m.side(of: resolve(player: filter.pointOfView).id),
           m.opponent(of: side).id != resolve(player: o).id { return false }
        if let w = filter.weekday, m.weekday != w { return false }
        if let g = filter.game, m.record.game != g { return false }
        if let s = filter.style, m.record.style != s { return false }
        if let d = filter.dates, !d.contains(m.record.startedAt) { return false }
        if let series = filter.series, !series.contains(m.record, resolve: m.shown) { return false }
        return true
    }

    /// One match's figures from `side`'s point of view.
    static func figures(_ r: MatchRecord, from side: Deciders.Side) -> StatsFigures {
        var f = StatsFigures()
        let mine = { (s: Deciders.Side) in s == side }
        let player = side == .first ? r.first.player : r.second.player
        if r.status == .finished {
            switch r.result {
            case .draw: f.drawn = 1
            case .win(let w): if w == player { f.won = 1 } else { f.lost = 1 }
            case nil: break
            }
        } else {
            f.abandoned = 1
        }
        let score = r.score ?? MatchRecord.Score(first: 0, second: 0)
        (f.framesWon, f.framesLost) = side == .first ? (score.first, score.second) : (score.second, score.first)

        let winners = r.frames.map { $0.winner == r.first.player ? Deciders.Side.first : .second }
        let deciders = Deciders.of(winners, style: deciderStyle(r.style))
        for d in deciders.frames {
            if mine(d.winner) { f.decidersWon += 1 } else { f.decidersLost += 1 }
            if d.isMatchDecider { if mine(d.winner) { f.matchDecidersWon += 1 } else { f.matchDecidersLost += 1 } }
        }
        for s in deciders.setDeciders {
            if mine(s) { f.setDecidersWon += 1 } else { f.setDecidersLost += 1 }
        }
        for (frame, w) in zip(r.frames, winners) {
            f.frameTime.add(frame.length)
            if mine(w) { f.frameTimeWon.add(frame.length) } else { f.frameTimeLost.add(frame.length) }
        }
        return f
    }

    static func deciderStyle(_ style: MatchRecord.Style) -> Deciders.Style {
        switch style {
        case .mostFramesWins: .mostFrames
        case .raceTo(let t): .race(frames: t.raceTo)
        case .sets(let sets, let frames): .sets(sets: sets.raceTo, frames: frames.raceTo)
        }
    }

    /// A player as shown: merges followed to the kept player.
    func resolve(player id: UUID) -> HistoryPlayer {
        resolve(MatchRecord.Side(player: id, colour: "gray")).view
    }
}
