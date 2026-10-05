#if DEBUG
import Foundation
import MatchesApplication

extension AppContainer {
    /// Screenshot aid (`-uiDemo`): a few ended matches so History and match detail have content.
    /// They are played through the real commands, so they reach Stats like any other match.
    func seedHistoryDemo(me: PlayerRef, asher: PlayerRef, dev: PlayerRef) {
        let matches = matchCommands
        func play(_ setup: MatchSetup, breaker: PlayerRef, _ frames: [PlayerRef], end: (MatchID) throws -> Void) {
            guard let id = try? matches.startMatch(setup) else { return }
            try? matches.chooseBreaker(id, player: breaker)
            for p in frames { try? matches.awardFrame(id, to: p) }
            try? end(id)
        }
        play(MatchSetup(players: [asher, me], game: .pool, style: .raceTo(3), breakRule: .alternate),
             breaker: me, [me, asher, me, asher, me]) { try matches.finishMatch($0, anyway: false) }
        play(MatchSetup(players: [me, dev], game: .snooker, style: .mostFramesWins, breakRule: .winnerBreaks),
             breaker: dev, [dev, dev, me]) { try matches.finishMatch($0, anyway: false) }
        play(MatchSetup(players: [dev, asher], game: .pool, style: .bestOf(7), breakRule: .alternate),
             breaker: asher, [asher, dev]) { try matches.abandonMatch($0) }
    }
}
#endif
