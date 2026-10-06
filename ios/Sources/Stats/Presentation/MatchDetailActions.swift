import Foundation
import SwiftUI

/// Matches' maintenance use cases for a past match (spec 015), as closures adapted by the
/// composition root, so Stats Presentation does not import Matches. Unset, the detail screen shows
/// no actions.
public struct MatchDetailActions: Sendable {
    /// `CorrectMatchScore` (S29). Returns the inconsistencies to confirm (nothing saved) when
    /// `confirmed` is false and the sets score is inconsistent; empty once saved. Refusals throw.
    public let correctScore: @MainActor @Sendable (UUID, ScoreEdit, _ confirmed: Bool) throws -> [String]
    /// `MarkMatchFinished` (S31), abandoned matches only.
    public let markFinished: @MainActor @Sendable (UUID) throws -> Void
    /// `DeleteMatch` (S30).
    public let delete: @MainActor @Sendable (UUID) throws -> Void

    public init(
        correctScore: @escaping @MainActor @Sendable (UUID, ScoreEdit, Bool) throws -> [String],
        markFinished: @escaping @MainActor @Sendable (UUID) throws -> Void,
        delete: @escaping @MainActor @Sendable (UUID) throws -> Void
    ) {
        self.correctScore = correctScore
        self.markFinished = markFinished
        self.delete = delete
    }
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
