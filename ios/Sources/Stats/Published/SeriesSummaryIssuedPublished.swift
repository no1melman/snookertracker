import EventDispatch
import Foundation

/// `SeriesSummaryIssued` (spec 017, S38), Stats' published language: dispatched in-process once a
/// series' monthly summary is issued and recorded. Stage 2: iOS Notifications turns it into a
/// notification that opens the monthly summary screen for `seriesId` and `year`/`month`.
public struct SeriesSummaryIssuedPublished: PublishedEvent, Hashable {
    public static let eventType = "Stats.SeriesSummaryIssued"
    public static let version = 1

    public let seriesId: UUID
    /// "Fridays with Asher".
    public let seriesName: String
    public let year: Int
    /// 1...12.
    public let month: Int
    /// "September", in the device's language.
    public let monthName: String
    /// "you 3–1 in matches, 22–17 in frames", or "Callum v Asher 2–2 in matches, 9–9 in frames",
    /// or "5 matches across 2 pairings".
    public let headline: String
    public let occurredAt: Date

    public init(
        seriesId: UUID, seriesName: String, year: Int, month: Int, monthName: String, headline: String, occurredAt: Date
    ) {
        self.seriesId = seriesId; self.seriesName = seriesName; self.year = year; self.month = month
        self.monthName = monthName; self.headline = headline; self.occurredAt = occurredAt
    }

    /// The notification text: "Fridays with Asher, September: you 3–1 in matches, 22–17 in frames".
    public var text: String { "\(seriesName), \(monthName): \(headline)" }
}
