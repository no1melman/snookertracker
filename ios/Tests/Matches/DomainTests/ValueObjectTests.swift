import Foundation
import Testing
import MatchesDomain

@Suite("Matches value objects")
struct ValueObjectTests {
    // MARK: Identifiers

    @Test func identifiersMustNotBeEmpty() {
        #expect(MatchId.create("").error == .empty)
        #expect(PlayerId.create("   ").error == .empty)
        #expect(TemplateId.create("\n").error == .empty)
        #expect(MatchId.create("m-1").value?.value == "m-1")
    }

    @Test func anIdDecodedFromEmptyStorageIsRejected() {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(PlayerId.self, from: Data("\"\"".utf8)) }
    }

    // MARK: Target

    @Test func raceToNeedsAtLeastOne() {
        #expect(Target.raceTo(0).error == .notPositive(0))
        #expect(Target.raceTo(-2).error == .notPositive(-2))
        #expect(Target.raceTo(1).value?.value == 1)
    }

    @Test func bestOfAcceptsOnlyOddNumbersAndStoresHalfRoundedUp() {
        #expect(Target.bestOf(4).error == .bestOfEven(4))
        #expect(Target.bestOf(0).error == .notPositive(0))
        #expect(Target.bestOf(1).value?.value == 1)
        #expect(Target.bestOf(5).value?.value == 3)
        #expect(Target.bestOf(17).value?.value == 9)
    }

    @Test func targetDisplaysAsEnteredButComparesOnRaceToNumber() {
        let bestOf5 = Target.bestOf(5).value!
        let raceTo3 = Target.raceTo(3).value!
        #expect(bestOf5.description == "best of 5")
        #expect(raceTo3.description == "race to 3")
        #expect(bestOf5 == raceTo3)
        #expect(bestOf5.hashValue == raceTo3.hashValue)
    }

    @Test func targetRoundTripsThroughStorageKeepingItsEntry() throws {
        let t = Target.bestOf(7).value!
        let decoded = try JSONDecoder().decode(Target.self, from: JSONEncoder().encode(t))
        #expect(decoded.description == "best of 7")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Target.self, from: Data(#"{"raceTo":2,"bestOf":4}"#.utf8))
        }
    }

    // MARK: Setup

    @Test func aPlayerCannotPlayThemselves() {
        let r = Setup.create(Fixture.callum, Fixture.callum, game: .pool, style: .mostFramesWins)
        #expect(r.error == .samePlayer(Fixture.callum))
    }

    @Test func setupDefaultsToAlternateBreaks() {
        let s = Setup.create(Fixture.callum, Fixture.asher, game: .snooker, style: .mostFramesWins).value!
        #expect(s.breakRule == .alternate)
    }

    @Test func setupEqualityIgnoresPlayerOrder() {
        let a = Setup.create(Fixture.callum, Fixture.asher, game: .pool, style: .mostFramesWins).value!
        let b = Setup.create(Fixture.asher, Fixture.callum, game: .pool, style: .mostFramesWins).value!
        #expect(a == b)
        #expect(Set([a, b]).count == 1)
    }

    @Test func setupBestOf5EqualsRaceTo3() {
        let a = Setup.create(Fixture.callum, Fixture.asher, game: .pool, style: .raceTo(Target.bestOf(5).value!)).value!
        let b = Setup.create(Fixture.asher, Fixture.callum, game: .pool, style: .raceTo(Target.raceTo(3).value!)).value!
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test func setupsDifferingInGameStyleOrRuleAreDifferent() {
        let base = Fixture.setup()
        #expect(base != Setup.create(Fixture.callum, Fixture.asher, game: .snooker, style: .mostFramesWins).value!)
        #expect(base != Fixture.setup(style: .raceTo(Fixture.target(3))))
        #expect(base != Fixture.setup(breakRule: .winnerBreaks))
        #expect(Fixture.setup(style: .sets(sets: Fixture.target(2), frames: Fixture.target(3)))
            != Fixture.setup(style: .sets(sets: Fixture.target(3), frames: Fixture.target(2))))
    }

    @Test func setupDecodedWithSamePlayerIsRejected() throws {
        let json = #"{"first":"a","second":"a","game":"pool","style":{"mostFramesWins":{}},"breakRule":"alternate"}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Setup.self, from: Data(json.utf8)) }
    }

    // MARK: Score, Duration, StartTime

    @Test func setsScoreDisplaysSetsInBracketsAroundCurrentSetFrames() {
        let s = Score(firstFrames: 9, secondFrames: 4, sets: .init(firstSets: 1, secondSets: 0, firstCurrentSetFrames: 5, secondCurrentSetFrames: 2))
        #expect(s.description == "(1) 5 – 2 (0)")
        #expect(Score(firstFrames: 3, secondFrames: 1).description == "3 – 1")
    }

    @Test func durationIsElapsedMinusPausedAndNeverNegative() {
        #expect(PlayDuration.create(seconds: -1).error == .negative(-1))
        let d = PlayDuration.elapsed(from: Fixture.t0, to: Fixture.time(10), minusPaused: 180)
        #expect(d.seconds == 420)
        #expect(PlayDuration.elapsed(from: Fixture.time(10), to: Fixture.t0, minusPaused: 0) == .zero)
    }

    @Test func startTimeDisplaysDayAndTime() {
        // Fri 2 Oct 2026 19:30 UTC
        let date = ISO8601DateFormatter().date(from: "2026-10-02T19:30:00Z")!
        #expect(StartTime(date).display(in: TimeZone(identifier: "UTC")!) == "Fri 19:30")
    }

    // MARK: Stale resolution values

    @Test func chosenEndTimeMustLieBetweenLastActionAndNow() {
        let last = Fixture.time(0), now = Fixture.time(600)
        #expect(ChosenEndTime.create(Fixture.time(-1), lastAction: last, now: now).error
            == .beforeLastAction(chosen: Fixture.time(-1), lastAction: last))
        #expect(ChosenEndTime.create(Fixture.time(601), lastAction: last, now: now).error
            == .afterNow(chosen: Fixture.time(601), now: now))
        #expect(ChosenEndTime.create(last, lastAction: last, now: now).value != nil)
        #expect(ChosenEndTime.create(now, lastAction: last, now: now).value != nil)
    }

    @Test func cappedLengthFallsBackToThreeHours() {
        #expect(CappedLength.from(samePairSameWeekdayAverage: nil).length == .hours(3))
        #expect(CappedLength.from(samePairSameWeekdayAverage: .minutes(95)).length == .minutes(95))
    }

    // MARK: Score corrections

    @Test func raceToCorrectionNeedsExactlyOneSideOnTheTarget() {
        let style = MatchStyle.raceTo(Fixture.target(5))
        #expect(ScoreCorrection.frames(first: 5, second: 3, for: style).value != nil)
        #expect(ScoreCorrection.frames(first: 2, second: 5, for: style).value != nil)
        #expect(ScoreCorrection.frames(first: 4, second: 3, for: style).error
            == .raceToNeedsExactlyOneOnTarget(target: 5, first: 4, second: 3))
        #expect(ScoreCorrection.frames(first: 5, second: 5, for: style).error
            == .raceToNeedsExactlyOneOnTarget(target: 5, first: 5, second: 5))
        #expect(ScoreCorrection.frames(first: 6, second: 2, for: style).error
            == .raceToNeedsExactlyOneOnTarget(target: 5, first: 6, second: 2))
    }

    @Test func mostFramesWinsCorrectionAcceptsAnyNonNegativeScore() {
        #expect(ScoreCorrection.frames(first: 4, second: 4, for: .mostFramesWins).value != nil)
        #expect(ScoreCorrection.frames(first: -1, second: 4, for: .mostFramesWins).error == .negativeFrames)
        #expect(ScoreCorrection.frames(first: 1, second: 0, for: .sets(sets: Fixture.target(2), frames: Fixture.target(2))).error == .styleMismatch)
    }

    @Test func setsCorrectionWarnsInsteadOfRefusing() {
        let style = MatchStyle.sets(sets: Fixture.target(2), frames: Fixture.target(3))
        let clean = ScoreCorrection.sets([.init(first: 3, second: 1), .init(first: 3, second: 2)], for: style).value!
        #expect(clean.warnings.isEmpty)

        let messy = ScoreCorrection.sets(
            [.init(first: 3, second: 1), .init(first: 2, second: 2), .init(first: 3, second: 0), .init(first: 0, second: 3)],
            for: style).value!
        #expect(messy.warnings == [.setNotWonOnTarget(setNumber: 2), .setPlayedAfterMatchDecided(setNumber: 4)])

        let short = ScoreCorrection.sets([.init(first: 3, second: 1)], for: style).value!
        #expect(short.warnings == [.setsTargetNotReached])
        #expect(ScoreCorrection.sets([], for: style).value!.warnings == [.noSets])
        #expect(ScoreCorrection.sets([.init(first: 1, second: 0)], for: .mostFramesWins).error == .styleMismatch)
    }

    // MARK: Template & settings values

    @Test func useCountIsAtLeastOne() {
        #expect(UseCount.create(0).error == .notPositive(0))
        #expect(UseCount.one.incremented().value == 2)
        #expect(UseCount.create(3).value!.adding(.one).value == 4)
    }

    @Test func matchDefaultsArePoolMostFramesAlternate() {
        #expect(MatchDefaults.initial == MatchDefaults(game: .pool, style: .mostFramesWins, breakRule: .alternate))
    }

    @Test func liveMatchLimitIsOneToAHundredDefaultTen() {
        #expect(LiveMatchLimit.standard.value == 10)
        #expect(LiveMatchLimit.create(0).error == .outOfRange(0))
        #expect(LiveMatchLimit.create(101).error == .outOfRange(101))
        #expect(LiveMatchLimit.create(1).value != nil)
        #expect(LiveMatchLimit.create(100).value != nil)
        #expect(LiveMatchLimit.standard.allowsAnother(liveCount: 9))
        #expect(!LiveMatchLimit.standard.allowsAnother(liveCount: 10))
    }
}
