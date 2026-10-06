import Foundation

/// Counts frames into sets and scores. Pure; recomputed from the frame list, so removing any frame
/// reverts whatever set win it caused.
struct Tally: Sendable {
    struct SetWin: Hashable, Sendable {
        let setNumber: Int
        let winner: PlayerId
        let score: SetFrames
        /// Index in the frame list of the frame that won the set.
        let frameIndex: Int
    }

    private(set) var firstFrames = 0
    private(set) var secondFrames = 0
    private(set) var firstSets = 0
    private(set) var secondSets = 0
    private(set) var firstCurrentSetFrames = 0
    private(set) var secondCurrentSetFrames = 0
    private(set) var currentSetNumber = 1
    private(set) var setNumbers: [Int] = []
    private(set) var setWins: [SetWin] = []
    private let isSets: Bool

    init(winners: [PlayerId], setup: Setup) {
        let framesPerSet: Int?
        if case .sets(_, let frames) = setup.style { framesPerSet = frames.value } else { framesPerSet = nil }
        isSets = framesPerSet != nil

        for (index, winner) in winners.enumerated() {
            setNumbers.append(currentSetNumber)
            let isFirst = winner == setup.first
            if isFirst { firstFrames += 1; firstCurrentSetFrames += 1 } else { secondFrames += 1; secondCurrentSetFrames += 1 }
            guard let target = framesPerSet,
                  firstCurrentSetFrames == target || secondCurrentSetFrames == target else { continue }
            setWins.append(SetWin(
                setNumber: currentSetNumber, winner: winner,
                score: SetFrames(first: firstCurrentSetFrames, second: secondCurrentSetFrames),
                frameIndex: index))
            if isFirst { firstSets += 1 } else { secondSets += 1 }
            firstCurrentSetFrames = 0
            secondCurrentSetFrames = 0
            currentSetNumber += 1
        }
    }

    init(frames: [Frame], setup: Setup) {
        self.init(winners: frames.map(\.winner.player), setup: setup)
    }

    static func renumber(_ frames: [Frame], setup: Setup) -> [Frame] {
        let tally = Tally(frames: frames, setup: setup)
        return frames.enumerated().map { i, frame in frame.renumbered(number: i + 1, setNumber: tally.setNumbers[i]) }
    }

    var score: Score {
        Score(
            firstFrames: firstFrames, secondFrames: secondFrames,
            sets: isSets
                ? Score.Sets(
                    firstSets: firstSets, secondSets: secondSets,
                    firstCurrentSetFrames: firstCurrentSetFrames, secondCurrentSetFrames: secondCurrentSetFrames)
                : nil)
    }

    func isMatchTargetReached(style: MatchStyle) -> Bool {
        switch style {
        case .mostFramesWins: false
        case .raceTo(let target): max(firstFrames, secondFrames) >= target.value
        case .sets(let sets, _): max(firstSets, secondSets) >= sets.value
        }
    }
}
