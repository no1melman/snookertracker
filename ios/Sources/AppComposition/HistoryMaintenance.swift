import Foundation
import MatchesApplication
import StatsPresentation
import UpgradePublished

/// Matches' history maintenance (spec 015) adapted for Stats' match detail. Honest about Free
/// refusals (S29, S30, S52): a refused correction or deletion reports that nothing changed, never a
/// success.
@MainActor
enum HistoryMaintenance {
    /// `CorrectMatchScore`. Free, beyond the newest ended matches: `.refused`, nothing saved; the
    /// detail closes the edit sheet, then opens the upgrade offer.
    static func correctScore(_ matches: MatchUseCases) -> @MainActor @Sendable (UUID, ScoreEdit, Bool) throws -> CorrectionOutcome {
        { [matches] id, edit, confirmed in
            let score: CorrectedScore = switch edit {
            case .frames(let p): .frames(first: p.first, second: p.second)
            case .sets(let sets): .sets(sets.map { SetScore(first: $0.first, second: $0.second) })
            }
            do {
                try matches.correctMatchScore(id, to: score, confirmed: confirmed)
                return .saved
            } catch MatchCommandError.correctionNeedsConfirmation(let warnings) {
                return .needsConfirming(warnings)
            } catch let refused as UpgradeRequired {
                return .refused(refused.feature)
            }
        }
    }

    /// The Scorer's `DeleteMatch`: true once deleted. A Free refusal opens the upgrade offer instead
    /// of an error and returns false: nothing deleted.
    static func deleteOrOffer(
        _ matches: MatchUseCases, showUpgradeOffer: @escaping ShowUpgradeOfferAction
    ) -> @MainActor @Sendable (UUID) throws -> Bool {
        { [matches] id in
            do {
                try matches.deleteMatch(id)
                return true
            } catch let refused as UpgradeRequired {
                showUpgradeOffer(refused.feature)
                return false
            }
        }
    }
}
