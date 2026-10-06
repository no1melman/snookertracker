import Foundation

/// The `MatchRecord` projection (spec 013): everything Stats knows about one match, folded from its
/// published events. Rebuilt from the whole stream on every event, so corrections, mark-finished and
/// removed frames always land consistently; a deleted match has no record.
public struct MatchRecord: Codable, Hashable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable { case live, finished, abandoned, cancelled }

    public struct Target: Codable, Hashable, Sendable {
        public let raceTo: Int
        /// Set when entered as "best of".
        public let bestOf: Int?

        public init(raceTo: Int, bestOf: Int? = nil) {
            self.raceTo = raceTo; self.bestOf = bestOf
        }
    }

    public enum Style: Codable, Hashable, Sendable {
        case mostFramesWins
        case raceTo(Target)
        case sets(sets: Target, frames: Target)
    }

    public struct Side: Codable, Hashable, Sendable {
        public let player: UUID
        /// This match's colour (may be a one-match override).
        public var colour: String
    }

    /// Frames by the setup's first and second player; sets for the sets style.
    public struct Score: Codable, Hashable, Sendable {
        public let first: Int
        public let second: Int
        public let firstSets: Int?
        public let secondSets: Int?

        public init(first: Int, second: Int, firstSets: Int? = nil, secondSets: Int? = nil) {
            self.first = first; self.second = second; self.firstSets = firstSets; self.secondSets = secondSets
        }
    }

    public enum Result: Codable, Hashable, Sendable {
        case win(UUID)
        case draw
    }

    public struct Frame: Codable, Hashable, Sendable {
        public let number: Int
        public let setNumber: Int
        public let winner: UUID
        /// Frame length, minus paused time.
        public let length: TimeInterval
        public let breaker: UUID?
        public let at: Date
    }

    public struct Pause: Codable, Hashable, Sendable {
        public let from: Date
        public var to: Date?
    }

    /// A score correction (S29): kept beside the original, never in place of it.
    public struct Correction: Codable, Hashable, Sendable {
        public let before: Score
        public let after: Score
        public let at: Date
    }

    public let id: UUID
    public let game: String
    public let style: Style
    public let breakRule: String
    public var first: Side
    public var second: Side
    public let startedAt: Date
    public var status: Status = .live
    public var endedAt: Date?
    /// Match length at the end, minus paused time.
    public var length: TimeInterval?
    public var frames: [Frame] = []
    public var pauses: [Pause] = []
    public var result: Result?
    /// The score the match ended with, before any correction.
    public var endingScore: Score?
    public var shortOfTarget = false
    public var corrections: [Correction] = []
    /// When an abandoned match was turned finished (S31).
    public var markedFinishedAt: Date?

    /// The score as it stands: the latest correction, else the ending score.
    public var score: Score? { corrections.last?.after ?? endingScore }
    /// Altered: the score has been corrected (shown as a label in History).
    public var isAltered: Bool { !corrections.isEmpty }
    public var isEnded: Bool { status != .live }

    // MARK: Fold

    /// Folds one match's published events, in stream order. nil before `MatchStarted` or once deleted.
    static func fold(id: UUID, _ facts: [MatchFact]) -> MatchRecord? {
        var record: MatchRecord?
        for fact in facts {
            if case .started(let s) = fact {
                record = MatchRecord(
                    id: id, game: s.setup.game, style: s.setup.style.value, breakRule: s.setup.breakRule,
                    first: Side(player: s.first.player, colour: s.first.colour),
                    second: Side(player: s.second.player, colour: s.second.colour),
                    startedAt: s.at)
                continue
            }
            if case .deleted = fact { return nil }
            record?.apply(fact)
        }
        return record
    }

    private mutating func apply(_ fact: MatchFact) {
        switch fact {
        case .started, .deleted, .ignored:
            break
        case .frameWon(let f):
            frames.append(Frame(number: f.frameNumber, setNumber: f.setNumber, winner: f.player,
                                length: f.length, breaker: f.breaker, at: f.at))
        case .frameRemoved(let number):
            frames.removeAll { $0.number == number }
            frames = renumbered(frames)
        case .paused(let at):
            if pauses.last.map({ $0.to != nil }) ?? true { pauses.append(Pause(from: at, to: nil)) }
        case .resumed(let at):
            if let last = pauses.indices.last, pauses[last].to == nil { pauses[last].to = at }
        case .colourOverridden(let player, let colour):
            if first.player == player { first.colour = colour }
            if second.player == player { second.colour = colour }
        case .finished(let f):
            status = .finished
            result = f.result.value
            endingScore = f.score.record
            endedAt = f.endedAt
            length = f.length
            shortOfTarget = f.shortOfTarget
        case .abandoned(let a):
            status = .abandoned
            endingScore = a.score.record
            endedAt = a.endedAt
            length = a.length
        case .cancelled(let at):
            status = .cancelled
            endedAt = at
            length = max(0, at.timeIntervalSince(startedAt) - pausedTime(before: at))
            endingScore = runningScores().last ?? Score(first: 0, second: 0)
        case .scoreCorrected(let c):
            corrections.append(Correction(before: c.before.record, after: c.after.record, at: c.at))
            if let r = c.result { result = r.value }
        case .markedFinished(let m):
            status = .finished
            result = m.result.value
            markedFinishedAt = m.at
        }
    }

    /// After a removal, frames are numbered 1… again and set numbers follow the style.
    private func renumbered(_ frames: [Frame]) -> [Frame] {
        let sets = setNumbers(frames.map(\.winner))
        return frames.enumerated().map { i, f in
            Frame(number: i + 1, setNumber: sets[i], winner: f.winner, length: f.length, breaker: f.breaker, at: f.at)
        }
    }

    private var framesPerSet: Int? {
        if case .sets(_, let frames) = style { return frames.raceTo }
        return nil
    }

    private func setNumbers(_ winners: [UUID]) -> [Int] {
        var numbers: [Int] = [], set = 1, a = 0, b = 0
        for w in winners {
            numbers.append(set)
            if w == first.player { a += 1 } else { b += 1 }
            if let target = framesPerSet, a == target || b == target { set += 1; a = 0; b = 0 }
        }
        return numbers
    }

    /// The score after each frame, in frame order.
    func runningScores() -> [Score] {
        var a = 0, b = 0, setA = 0, setB = 0, sa = 0, sb = 0
        return frames.map { f in
            if f.winner == first.player { a += 1; setA += 1 } else { b += 1; setB += 1 }
            guard let target = framesPerSet else { return Score(first: a, second: b) }
            if setA == target || setB == target {
                if setA == target { sa += 1 } else { sb += 1 }
                setA = 0; setB = 0
            }
            return Score(first: a, second: b, firstSets: sa, secondSets: sb)
        }
    }

    /// Paused time before `date` (an open pause runs up to `date`).
    func pausedTime(before date: Date) -> TimeInterval {
        pauses.reduce(0) { sum, p in
            guard p.from < date else { return sum }
            return sum + max(0, min(p.to ?? date, date).timeIntervalSince(p.from))
        }
    }

    /// Match time when a frame ended: start → frame end, minus paused time.
    func matchTime(at date: Date) -> TimeInterval {
        max(0, date.timeIntervalSince(startedAt) - pausedTime(before: date))
    }
}
