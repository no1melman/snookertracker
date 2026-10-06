import Foundation

// Series monthly summary (spec 017, S38). Issuing a summary changes nothing on the series: it only
// raises `SeriesSummaryIssued` (Stage 2, published for iOS Notifications). Which months have been
// issued is kept by the application layer (`SeriesSummaryLog`), so each month is issued once.

/// A series' summary for a finished month was issued.
public struct SeriesSummaryIssued: Hashable, Sendable {
    public let seriesId: SeriesId
    public let name: SeriesName
    public let month: Month

    public init(seriesId: SeriesId, name: SeriesName, month: Month) {
        self.seriesId = seriesId; self.name = name; self.month = month
    }
}

public enum SeriesSummaryError: Error, Equatable, Sendable {
    /// S38: only series with at least one match of their setups in the month get a summary.
    case noMatches(SeriesId, Month)
    /// A month is summarised once it is over.
    case monthNotOver(Month)
    /// A deleted series gets no summary.
    case deleted(SeriesId)
}

extension SeriesSummaryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noMatches(_, let m): "The series had no matches in \(m)."
        case .monthNotOver(let m): "\(m) isn't over yet."
        case .deleted: "That series has been deleted."
        }
    }
}

public extension Series {
    /// S38: the summary for `month`. Guards: the series still exists, `month` is before `currentMonth`,
    /// and at least one match of its setups was played in it (`matchesInMonth`, counted by the caller
    /// from the matches whose setup is one of this series').
    func issueSummary(for month: Month, matchesInMonth: Int, currentMonth: Month) -> Result<SeriesSummaryIssued, SeriesSummaryError> {
        guard !isDeleted else { return .failure(.deleted(id)) }
        guard month < currentMonth else { return .failure(.monthNotOver(month)) }
        guard matchesInMonth > 0 else { return .failure(.noMatches(id, month)) }
        return .success(SeriesSummaryIssued(seriesId: id, name: name, month: month))
    }
}
