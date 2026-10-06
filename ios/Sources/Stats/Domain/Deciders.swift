/// The decider rules (S10, S14, S18), computed from the frames as played; Matches never stores them
/// (ADR-0003). Pure functions over who won each frame.
///
/// - **Decider:** a frame won from level at the end of a set, or at the end of a frames-style match
///   (e.g. 8–8 → 9–8), in any set.
/// - **Match decider:** such a frame that ends the match (it is also a decider).
/// - **Set decider:** a deciding set played with sets level (e.g. 2–2 in race to 3 sets). Its own
///   tally: never a match decider, and the frame that wins it is a decider only when won from level.
///
/// "Level" means at least one frame each: a race to 1 (or a one-frame match) has no deciders.
public struct Deciders: Hashable, Sendable {
    /// The setup's first or second player.
    public enum Side: Hashable, Sendable { case first, second }

    /// The match style as far as deciders care.
    public enum Style: Hashable, Sendable {
        /// Most frames wins: only the match's last frame can be a decider.
        case mostFrames
        /// Race to (or best of) `frames`.
        case race(frames: Int)
        /// Race to `sets` sets, each a race to `frames` frames.
        case sets(sets: Int, frames: Int)
    }

    public struct Frame: Hashable, Sendable {
        /// 0-based index into the frames.
        public let index: Int
        public let winner: Side
        public let isMatchDecider: Bool

        public init(index: Int, winner: Side, isMatchDecider: Bool) {
            self.index = index; self.winner = winner; self.isMatchDecider = isMatchDecider
        }
    }

    /// Decider frames, match deciders included, in frame order.
    public let frames: [Frame]
    /// The winner of each deciding set played with sets level.
    public let setDeciders: [Side]

    public var matchDecider: Frame? { frames.first(where: \.isMatchDecider) }

    public init(frames: [Frame], setDeciders: [Side]) {
        self.frames = frames
        self.setDeciders = setDeciders
    }

    /// The deciders in a match whose frames were won by `winners`, in order.
    public static func of(_ winners: [Side], style: Style) -> Deciders {
        switch style {
        case .mostFrames:
            guard let last = winners.indices.last else { return Deciders(frames: [], setDeciders: []) }
            let before = winners.dropLast()
            let a = before.filter { $0 == .first }.count, b = before.count - a
            guard a == b, a >= 1 else { return Deciders(frames: [], setDeciders: []) }
            return Deciders(frames: [Frame(index: last, winner: winners[last], isMatchDecider: true)], setDeciders: [])

        case .race(let target):
            return sets(winners, setsTarget: 1, framesTarget: target)

        case .sets(let setsTarget, let framesTarget):
            return sets(winners, setsTarget: setsTarget, framesTarget: framesTarget)
        }
    }

    /// A race is one set of `framesTarget` frames in a race to one set.
    private static func sets(_ winners: [Side], setsTarget: Int, framesTarget: Int) -> Deciders {
        var frames: [Frame] = [], setDeciders: [Side] = []
        var (a, b) = (0, 0)          // frames in the current set
        var (setsA, setsB) = (0, 0)
        var setStartedLevel = false  // a race (one set) never has a deciding set
        for (i, w) in winners.enumerated() {
            if a == 0 && b == 0 { setStartedLevel = setsTarget >= 2 && setsA == setsTarget - 1 && setsB == setsTarget - 1 }
            let fromLevel = framesTarget >= 2 && a == framesTarget - 1 && b == framesTarget - 1
            if w == .first { a += 1 } else { b += 1 }
            guard a == framesTarget || b == framesTarget else { continue }
            // This frame won the set.
            if w == .first { setsA += 1 } else { setsB += 1 }
            let endsMatch = setsA == setsTarget || setsB == setsTarget
            if fromLevel { frames.append(Frame(index: i, winner: w, isMatchDecider: endsMatch)) }
            if setStartedLevel { setDeciders.append(w) }
            (a, b) = (0, 0)
            if endsMatch { break }
        }
        return Deciders(frames: frames, setDeciders: setDeciders)
    }
}
