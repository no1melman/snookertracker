import Foundation

// Ports for the Matches context. Implementations are @MainActor @Observable objects, so SwiftUI
// re-renders when a read model changes (reading a property through these protocols is tracked).

// MARK: - Queries (read models, spec 009)

/// `LiveMatches`: one row per live match, oldest started first.
@MainActor public protocol LiveMatchesQuery: AnyObject, Sendable {
    var liveMatches: [LiveMatchRow] { get }
}

/// `LiveMatchScreen`: everything the live screen shows for one match; nil once it has ended.
@MainActor public protocol LiveMatchScreenQuery: AnyObject, Sendable {
    func liveMatchScreen(_ id: MatchID) -> LiveMatchScreen?
}

/// `MatchSettingsView` + `ChangeMatchDefaults` + `SetLiveMatchLimit` (spec 007). The values are the
/// effective ones: while Free, the Free style, break rule and live-match limit, whatever is stored
/// (spec 026).
@MainActor public protocol MatchSettings: AnyObject, Sendable {
    var defaults: MatchDefaults { get }
    var liveMatchLimit: Int { get }
    /// Free: a style or break-rule change throws `UpgradeRequired`; the game stays free (S20, S21).
    func changeDefaults(_ defaults: MatchDefaults) throws
    /// `SetLiveMatchLimit` (S44), paid: throws `UpgradeRequired(.severalLiveMatches)` while Free.
    func setLiveMatchLimit(_ limit: Int) throws
    /// `setLiveMatchLimit` ignoring a refusal or a failed write.
    func changeLiveMatchLimit(_ limit: Int)
}

// MARK: - Commands (use cases, spec 010)

/// The live-play use cases: StartMatch, ChooseBreaker, AwardFrame, RemoveFrame, PauseMatch,
/// ResumeMatch, FinishMatch, AbandonMatch, CancelMatch.
@MainActor public protocol MatchCommands: AnyObject, Sendable {
    @discardableResult
    func startMatch(_ setup: MatchSetup) throws -> MatchID
    /// Asked before `startMatch` (S11, `IsPlayerInLiveMatch`): the setup's players who are already in
    /// a live match, so the UI can ask "are you sure?". Empty means start straight away.
    func playersAlreadyLive(_ setup: MatchSetup) throws -> [MatchPlayer]
    func chooseBreaker(_ match: MatchID, player: PlayerRef) throws
    /// `CorrectBreaker` (S41): `player` is breaking now; the break rule carries on from them.
    /// In play or paused, once a breaker has been chosen.
    func correctBreaker(_ match: MatchID, player: PlayerRef) throws
    /// `OverrideMatchColour` (S46): gives `player` the palette colour `colour` for this match only,
    /// when both sides share a colour and no breaker is chosen yet. Saved player colours don't change.
    func overrideMatchColour(_ match: MatchID, of player: PlayerRef, to colour: String) throws
    func awardFrame(_ match: MatchID, to player: PlayerRef) throws
    func removeFrame(_ match: MatchID, from player: PlayerRef) throws
    func pauseMatch(_ match: MatchID) throws
    func resumeMatch(_ match: MatchID) throws
    /// Finishing a target style short of its target throws `MatchCommandError.finishShortOfTarget`
    /// unless `anyway` (then it counts as abandoned).
    func finishMatch(_ match: MatchID, anyway: Bool) throws
    func abandonMatch(_ match: MatchID) throws
    func cancelMatch(_ match: MatchID) throws
    /// What Finish all would do (S43): the UI shows one dialog, warning when any will be abandoned.
    func finishAllMatchesPreview() throws -> FinishAllPreview
    /// `FinishAllMatches` (S43): finishable live matches are finished, the others abandoned.
    func finishAllMatches() throws
    /// Deletes an ended match (S30); a live match throws `notAllowedNow`.
    func deleteMatch(_ match: MatchID) throws
    /// `CorrectMatchScore` (S29), finished or abandoned matches only. A race-to score off the target
    /// throws `correctionNotOnTarget`; an inconsistent sets score throws `correctionNeedsConfirmation`
    /// (nothing saved) unless `confirmed`.
    func correctMatchScore(_ match: MatchID, to score: CorrectedScore, confirmed: Bool) throws
    /// `MarkMatchFinished` (S31): abandoned → finished; anything else throws `notAllowedNow`.
    func markMatchFinished(_ match: MatchID) throws
}

// MARK: - Supplier port (Players context, adapted in the composition root)

/// What Matches needs from Players: names and colours, `PlayerSuggestions`, and inline add.
@MainActor public protocol MatchPlayerDirectory: AnyObject, Sendable {
    var suggestions: [MatchPlayer] { get }
    var me: PlayerRef? { get }
    func player(_ id: PlayerRef) -> MatchPlayer?
    func addPlayer(named name: String, colour: String) throws -> MatchPlayer
}

public struct MatchPlayer: Identifiable, Hashable, Sendable {
    public let id: PlayerRef
    public var name: String
    /// Palette key (DesignSystem `PlayerColour` raw value).
    public var colour: String

    public init(id: PlayerRef, name: String, colour: String) {
        self.id = id
        self.name = name
        self.colour = colour
    }
}

public extension MatchCommands {
    func finishMatch(_ match: MatchID) throws { try finishMatch(match, anyway: false) }
}
