import Foundation
import MatchesDomain

// Translation between the ports' vocabulary (UUIDs, entered targets) and the domain's value objects.

extension MatchesDomain.MatchId {
    // `MatchId(uuid)` is the domain's own initialiser (MatchID is a UUID).
    var uuid: MatchID? { UUID(uuidString: value) }
}

extension MatchesDomain.PlayerId {
    /// The domain's `init(_ uuid:)`; named so call sites read as a translation.
    init(ref: PlayerRef) { self = Self(ref) }
    var ref: PlayerRef? { UUID(uuidString: value) }
}

extension Game {
    init(_ game: MatchesDomain.Game) { self = game == .pool ? .pool : .snooker }
    var domain: MatchesDomain.Game { self == .pool ? .pool : .snooker }
}

extension BreakRule {
    init(_ rule: MatchesDomain.BreakRule) { self = rule == .alternate ? .alternate : .winnerBreaks }
    var domain: MatchesDomain.BreakRule { self == .alternate ? .alternate : .winnerBreaks }
}

extension MatchStyle {
    /// As entered: a best-of target keeps its "best of M" form.
    init(_ style: MatchesDomain.MatchStyle) {
        switch style {
        case .mostFramesWins: self = .mostFramesWins
        case .raceTo(let t):
            if case .bestOf(let m) = t.entry { self = .bestOf(m) } else { self = .raceTo(t.value) }
        // Not offered by the UI yet; shown by its sets target.
        case .sets(let sets, _): self = .raceTo(sets.value)
        }
    }

    /// The domain style, or `invalidTargets`.
    func domain() throws -> MatchesDomain.MatchStyle {
        switch self {
        case .mostFramesWins: return .mostFramesWins
        case .raceTo(let n):
            guard case .success(let t) = Target.raceTo(n) else { throw MatchCommandError.invalidTargets }
            return .raceTo(t)
        case .bestOf(let m):
            guard case .success(let t) = Target.bestOf(m) else { throw MatchCommandError.invalidTargets }
            return .raceTo(t)
        }
    }
}

extension MatchDefaults {
    init(_ defaults: MatchesDomain.MatchDefaults) {
        self.init(game: Game(defaults.game), style: MatchStyle(defaults.style), breakRule: BreakRule(defaults.breakRule))
    }

    func domain() throws -> MatchesDomain.MatchDefaults {
        MatchesDomain.MatchDefaults(game: game.domain, style: try style.domain(), breakRule: breakRule.domain)
    }
}

extension MatchCommandError {
    /// Domain refusals as the scorer sees them.
    init(_ error: MatchError) {
        switch error {
        case .finishShortOfTarget:
            self = .finishShortOfTarget
        case .invalidScoreCorrection(let e):
            self = MatchCommandError(e)
        case .notAllowed, .playerNotInMatch, .noFrameToRemove, .noBreakerToCorrect,
             .coloursAlreadyDiffer, .overrideColourNotDifferent, .pauseBeforeLastAction,
             .notStale, .invalidEndTime, .longFrameThresholdNotReached:
            self = .notAllowedNow
        }
    }

    init(_ error: ScoreCorrectionError) {
        switch error {
        case .raceToNeedsExactlyOneOnTarget(let target, _, _): self = .correctionNotOnTarget(target)
        case .negativeFrames, .styleMismatch: self = .invalidCorrection
        }
    }
}

extension CorrectedScore {
    /// The domain correction for `style` (with any sets warnings), or the refusal.
    func domain(for style: MatchesDomain.MatchStyle) throws -> ScoreCorrection {
        let result: Result<ScoreCorrection, ScoreCorrectionError>
        switch self {
        case .frames(let first, let second):
            result = ScoreCorrection.frames(first: first, second: second, for: style)
        case .sets(let sets):
            result = ScoreCorrection.sets(sets.map { SetFrames(first: $0.first, second: $0.second) }, for: style)
        }
        switch result {
        case .success(let correction): return correction
        case .failure(let e): throw MatchCommandError(e)
        }
    }
}

extension ScoreCorrectionWarning {
    /// As the scorer reads it before confirming a sets correction.
    var text: String {
        switch self {
        case .noSets: "No sets were entered."
        case .setNotWonOnTarget(let n): "Set \(n) doesn't end with one player on the frames target."
        case .setPlayedAfterMatchDecided(let n): "Set \(n) comes after the match was already won."
        case .setsTargetNotReached: "Nobody reaches the sets target."
        }
    }
}
