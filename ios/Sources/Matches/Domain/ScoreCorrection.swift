import Foundation

public enum ScoreCorrectionError: Error, Equatable, Sendable {
    case negativeFrames
    /// Frames given for a sets match, or sets for a frames match.
    case styleMismatch
    /// A race-to correction must put exactly one side on the target.
    case raceToNeedsExactlyOneOnTarget(target: Int, first: Int, second: Int)
}

/// Inconsistencies in a sets correction: reported, never refused.
public enum ScoreCorrectionWarning: Hashable, Sendable, Codable {
    case noSets
    /// Neither, or both, sides on the frames target, or a side past it.
    case setNotWonOnTarget(setNumber: Int)
    case setPlayedAfterMatchDecided(setNumber: Int)
    case setsTargetNotReached
}

/// Frames of one set, by side.
public struct SetFrames: Hashable, Sendable, Codable {
    public let first: Int
    public let second: Int

    public init(first: Int, second: Int) {
        self.first = first
        self.second = second
    }
}

/// A corrected score for an ended match (S29).
public struct ScoreCorrection: Hashable, Sendable, Codable {
    public enum Scores: Hashable, Sendable, Codable {
        case frames(first: Int, second: Int)
        case sets([SetFrames])
    }

    public let scores: Scores
    public let warnings: [ScoreCorrectionWarning]

    private init(scores: Scores, warnings: [ScoreCorrectionWarning]) {
        self.scores = scores
        self.warnings = warnings
    }

    /// Most frames wins or race to.
    public static func frames(first: Int, second: Int, for style: MatchStyle) -> Result<ScoreCorrection, ScoreCorrectionError> {
        guard first >= 0, second >= 0 else { return .failure(.negativeFrames) }
        switch style {
        case .mostFramesWins:
            break
        case .raceTo(let target):
            let onTarget = [first, second].filter { $0 == target.value }.count
            let past = first > target.value || second > target.value
            guard onTarget == 1, !past else {
                return .failure(.raceToNeedsExactlyOneOnTarget(target: target.value, first: first, second: second))
            }
        case .sets:
            return .failure(.styleMismatch)
        }
        return .success(ScoreCorrection(scores: .frames(first: first, second: second), warnings: []))
    }

    /// Per-set frame scores; inconsistencies become warnings.
    public static func sets(_ perSet: [SetFrames], for style: MatchStyle) -> Result<ScoreCorrection, ScoreCorrectionError> {
        guard case .sets(let setsTarget, let framesTarget) = style else { return .failure(.styleMismatch) }
        guard perSet.allSatisfy({ $0.first >= 0 && $0.second >= 0 }) else { return .failure(.negativeFrames) }

        var warnings: [ScoreCorrectionWarning] = perSet.isEmpty ? [.noSets] : []
        var firstSets = 0, secondSets = 0
        for (index, set) in perSet.enumerated() {
            let number = index + 1
            if firstSets == setsTarget.value || secondSets == setsTarget.value {
                warnings.append(.setPlayedAfterMatchDecided(setNumber: number))
            }
            let f = framesTarget.value
            switch (set.first, set.second) {
            case (f, let s) where s < f: firstSets += 1
            case (let s, f) where s < f: secondSets += 1
            default: warnings.append(.setNotWonOnTarget(setNumber: number))
            }
        }
        if !perSet.isEmpty, firstSets < setsTarget.value, secondSets < setsTarget.value {
            warnings.append(.setsTargetNotReached)
        }
        return .success(ScoreCorrection(scores: .sets(perSet), warnings: warnings))
    }
}
