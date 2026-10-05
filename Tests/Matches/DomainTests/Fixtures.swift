import Foundation
import MatchesDomain

extension Result {
    var value: Success? { try? get() }
    var error: Failure? {
        if case .failure(let e) = self { return e }
        return nil
    }
}

enum Fixture {
    static let callum = PlayerId.create("callum").value!
    static let asher = PlayerId.create("asher").value!
    static let stranger = PlayerId.create("stranger").value!
    static let red = Colour.create("red").value!
    static let blue = Colour.create("blue").value!
    static let green = Colour.create("green").value!
    static let matchId = MatchId.create("match-1").value!
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    static func time(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    static func target(_ n: Int) -> Target { Target.raceTo(n).value! }

    static func setup(
        style: MatchStyle = .mostFramesWins, breakRule: BreakRule = .alternate
    ) -> Setup {
        Setup.create(callum, asher, game: .pool, style: style, breakRule: breakRule).value!
    }

    static func newMatch(
        style: MatchStyle = .mostFramesWins, breakRule: BreakRule = .alternate,
        colours: (Colour, Colour) = (red, blue)
    ) -> Match {
        Match.start(id: matchId, setup: setup(style: style, breakRule: breakRule),
                    firstColour: colours.0, secondColour: colours.1, at: t0)
    }

    /// Started, Callum breaking first, at minute 0.
    static func inPlay(style: MatchStyle = .mostFramesWins, breakRule: BreakRule = .alternate) -> Match {
        newMatch(style: style, breakRule: breakRule).chooseBreaker(callum, at: t0).value!
    }
}

extension Match {
    /// Awards frames in order, one minute apart from `startMinute`.
    func awarding(_ winners: [PlayerId], startMinute: Double = 1) -> Match {
        var m = self
        for (i, w) in winners.enumerated() {
            m = m.awardFrame(to: w, at: Fixture.time(startMinute + Double(i))).value!
        }
        return m
    }

    var newEvents: [MatchEvent] { uncommittedEvents }
}
