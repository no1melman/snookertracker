import Foundation

/// Anything outside the Free limits (ADR-0010). Touching one while Free opens the upgrade offer (S52).
public enum PaidFeature: String, CaseIterable, Hashable, Sendable, Codable {
    /// Start from a template (S1), the templates area, delete a template (S36).
    case templates
    /// Pause and resume by hand (S7, S8). Resuming after an auto-pause (S27) stays free.
    case manualPause
    /// The race-to style (S15) and choosing it as the default (S21).
    case raceTo
    /// The sets style (S16) and choosing it as the default (S21).
    case sets
    /// The winner-breaks break rule (S2, S21).
    case winnerBreaks
    /// More active players than the Free limit (S3, S33–S35).
    case extraPlayers
    /// Ended matches beyond the newest Free-limit count (S17, S29, S30).
    case fullHistory
    /// Player colours (S22, S46).
    case colours
    /// The head-to-head (S14).
    case headToHead
    /// Stats by opponent and by day of the week (S18, S19).
    case stats
    /// Series and their monthly summaries (S38–S40).
    case series
    /// More than one live match, and the live-match limit setting (S11, S43, S44).
    case severalLiveMatches
    /// The lock-screen Live Activity (S47).
    case lockScreen

    /// Where the upgrade offer appears for this feature (S52): templates and pause show "Upgrade now"
    /// where they would be; every other feature opens the generic screen.
    public var offerPlacement: UpgradeOfferPlacement {
        switch self {
        case .templates, .manualPause: .inPlace
        default: .genericScreen
        }
    }
}

/// How the upgrade offer is shown (S52).
public enum UpgradeOfferPlacement: String, Hashable, Sendable, Codable {
    /// An "Upgrade now" prompt in place of the feature (templates area, pause button).
    case inPlace
    /// The generic "Upgrade once, forever, to unlock" screen, with Buy and Restore.
    case genericScreen
}
