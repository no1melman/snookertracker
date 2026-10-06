import StatsDomain
import Testing

// The decider rules (S10, S14, S18) on the worked examples from docs/ddd-requirements.md.

private let A = Deciders.Side.first
private let B = Deciders.Side.second

/// One set's frames: the winner reaches `target` with the loser on `loserFrames`, decided by
/// whether the hill-hill frame came last.
private func set(_ winner: Deciders.Side, _ target: Int, _ loserFrames: Int) -> [Deciders.Side] {
    let loser: Deciders.Side = winner == A ? B : A
    // Loser's frames first, then the winner's: the last frame is from level only at (t-1)-(t-1).
    return Array(repeating: winner, count: target - 1) + Array(repeating: loser, count: loserFrames) + [winner]
}

private let threeSetsOfNine = Deciders.Style.sets(sets: 3, frames: 9)

@Suite struct DecidersWorkedExamplesTests {
    @Test func threeOneWithALastSetAtNineEightIsAMatchDecider() {
        // Sets: A, A, B, then A wins the fourth 9–8.
        let frames = set(A, 9, 3) + set(A, 9, 4) + set(B, 9, 2) + set(A, 9, 8)
        let d = Deciders.of(frames, style: threeSetsOfNine)
        #expect(d.frames.count == 1)
        #expect(d.matchDecider == Deciders.Frame(index: frames.count - 1, winner: A, isMatchDecider: true))
        #expect(d.setDeciders.isEmpty)
    }

    @Test func threeTwoWithALastSetAtNineFiveIsASetDeciderOnly() {
        let frames = set(A, 9, 3) + set(B, 9, 4) + set(A, 9, 2) + set(B, 9, 1) + set(A, 9, 5)
        let d = Deciders.of(frames, style: threeSetsOfNine)
        #expect(d.frames.isEmpty)
        #expect(d.matchDecider == nil)
        #expect(d.setDeciders == [A])
    }

    @Test func threeTwoWithALastSetAtNineEightIsBoth() {
        let frames = set(B, 9, 3) + set(A, 9, 4) + set(B, 9, 2) + set(A, 9, 1) + set(B, 9, 8)
        let d = Deciders.of(frames, style: threeSetsOfNine)
        #expect(d.frames.map(\.winner) == [B])
        #expect(d.matchDecider?.winner == B)
        #expect(d.setDeciders == [B])
    }

    @Test func anEarlierSetAtNineEightIsADeciderOnly() {
        let frames = set(A, 9, 8) + set(A, 9, 4) + set(B, 9, 2) + set(A, 9, 1)
        let d = Deciders.of(frames, style: threeSetsOfNine)
        #expect(d.frames == [Deciders.Frame(index: 16, winner: A, isMatchDecider: false)])
        #expect(d.matchDecider == nil)
        #expect(d.setDeciders.isEmpty)
    }
}

@Suite struct DecidersFramesStyleTests {
    @Test func aRaceWonFromHillHillIsAMatchDecider() {
        let d = Deciders.of([A, B, A, B, B], style: .race(frames: 3))
        #expect(d.frames == [Deciders.Frame(index: 4, winner: B, isMatchDecider: true)])
        #expect(d.setDeciders.isEmpty)
    }

    @Test func aRaceNotWonFromLevelHasNoDecider() {
        #expect(Deciders.of([A, A, B, A], style: .race(frames: 3)).frames.isEmpty)
    }

    @Test func aRaceFinishedShortOfTargetHasNoDecider() {
        #expect(Deciders.of([A, B, A], style: .race(frames: 5)).frames.isEmpty)
    }

    @Test func aRaceToOneHasNoDecider() {
        #expect(Deciders.of([A], style: .race(frames: 1)).frames.isEmpty)
    }

    @Test func mostFramesLastFrameWonFromLevelIsAMatchDecider() {
        let d = Deciders.of([A, B, B, A, A], style: .mostFrames)
        #expect(d.frames == [Deciders.Frame(index: 4, winner: A, isMatchDecider: true)])
    }

    @Test func mostFramesOnlyTheLastFrameCounts() {
        // 1–1 → 2–1 mid-match is not the end of the match.
        #expect(Deciders.of([A, B, A, A], style: .mostFrames).frames.isEmpty)
        #expect(Deciders.of([A], style: .mostFrames).frames.isEmpty)
        #expect(Deciders.of([], style: .mostFrames).frames.isEmpty)
    }

    @Test func anUnfinishedDecidingSetIsNotASetDecider() {
        // Sets 1–1 in race to 2 sets, deciding set abandoned at 1–0.
        let d = Deciders.of([A, A, B, B, A], style: .sets(sets: 2, frames: 2))
        #expect(d.setDeciders.isEmpty)
    }

    @Test func aSetDeciderWonFromHillHillCountsBothTallies() {
        let d = Deciders.of([A, A, B, B, A, B, B], style: .sets(sets: 2, frames: 2))
        #expect(d.setDeciders == [B])
        #expect(d.frames == [Deciders.Frame(index: 6, winner: B, isMatchDecider: true)])
    }
}
