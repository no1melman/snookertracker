import Foundation
import SwiftUI
import UpgradePublished

/// Matches' maintenance use cases for a past match (spec 015), as closures adapted by the
/// composition root, so Stats Presentation does not import Matches. Unset, the detail screen shows
/// no actions.
public struct MatchDetailActions: Sendable {
    /// `CorrectMatchScore` (S29): saved, inconsistencies to confirm (nothing saved), or refused by the
    /// edition (nothing saved; the screen closes the edit sheet and opens the offer, S52). Other
    /// refusals throw.
    public let correctScore: @MainActor @Sendable (UUID, ScoreEdit, _ confirmed: Bool) throws -> CorrectionOutcome
    /// `MarkMatchFinished` (S31), abandoned matches only.
    public let markFinished: @MainActor @Sendable (UUID) throws -> Void
    /// `DeleteMatch` (S30): true once deleted; false when the edition refused it (the offer is open).
    public let delete: @MainActor @Sendable (UUID) throws -> Bool

    public init(
        correctScore: @escaping @MainActor @Sendable (UUID, ScoreEdit, Bool) throws -> CorrectionOutcome,
        markFinished: @escaping @MainActor @Sendable (UUID) throws -> Void,
        delete: @escaping @MainActor @Sendable (UUID) throws -> Bool
    ) {
        self.correctScore = correctScore
        self.markFinished = markFinished
        self.delete = delete
    }
}

/// What a score correction came to. Only `.saved` means the score changed.
public enum CorrectionOutcome: Hashable, Sendable {
    case saved
    /// The sets score is inconsistent: confirm or fix it (nothing saved yet).
    case needsConfirming([String])
    /// The edition refused it (Free: beyond the newest ended matches): nothing saved; the upgrade
    /// offer for `feature` is due (S52).
    case refused(PaidFeature)
}
/// A corrected score as typed on the edit screen: frames, or each set's frames for the sets style.
/// `first` / `second` follow the match's first and second player.
public enum ScoreEdit: Hashable, Sendable {
    case frames(ScorePair)
    case sets([ScorePair])
}

public struct ScorePair: Hashable, Sendable {
    public var first: Int
    public var second: Int

    public init(first: Int, second: Int) {
        self.first = first
        self.second = second
    }
}

public extension EnvironmentValues {
    @Entry var matchDetailActions: MatchDetailActions? = nil
}
