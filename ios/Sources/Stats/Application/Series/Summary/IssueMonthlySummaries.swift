import EventDispatch
import Foundation
import StatsDomain
import StatsPublished

/// `IssueMonthlySummaries` (spec 017, S38). Trigger: the clock, read on launch and whenever the app
/// returns to the foreground (no background task). For every series it issues the previous month's
/// summary once, when the series had a match that month: `findAll` → `MonthlySummary` (the count)
/// → `Series.issueSummary` → record the month in `SeriesSummaryLog` → dispatch
/// `SeriesSummaryIssuedPublished` for iOS Notifications.
///
/// Not issuing on the 1st exactly: the first run in a month covers the month before, so a phone
/// left off on the 1st still gets the summary. A month that had no matches is not recorded, so a
/// match from that month taken in later (catch-up) can still earn one.
@MainActor
public final class IssueMonthlySummaries {
    private let repository: any SeriesRepository
    private let summaries: MonthlySummaryProjection
    private let log: any SeriesSummaryLog
    private let dispatcher: EventDispatcher
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    /// The last failure for one series (a run never throws into launch).
    public private(set) var lastError: (any Error)?

    public init(
        repository: any SeriesRepository, summaries: MonthlySummaryProjection, log: any SeriesSummaryLog,
        dispatcher: EventDispatcher, now: @escaping @Sendable () -> Date = Date.init, calendar: Calendar = .current
    ) {
        self.repository = repository
        self.summaries = summaries
        self.log = log
        self.dispatcher = dispatcher
        self.now = now
        self.calendar = calendar
    }

    /// Issues every summary due now; returns what was issued. Safe to call repeatedly.
    @discardableResult
    public func run() -> [SeriesSummaryIssued] {
        let at = now()
        let current = Month.containing(at, calendar: calendar)
        let month = current.previous
        let all: [Series]
        do { all = try repository.findAll() } catch { lastError = error; return [] }

        var issued: [SeriesSummaryIssued] = []
        var published: [any PublishedEvent] = []
        for series in all {
            do {
                guard try !log.isIssued(series.id, month) else { continue }
                let summary = summaries.summary(series: series.id.value, month: month)
                switch series.issueSummary(for: month, matchesInMonth: summary?.matches ?? 0, currentMonth: current) {
                case .failure(.noMatches): continue
                case .failure(let error): throw error
                case .success(let event):
                    try log.markIssued(series.id, month, at: at)
                    issued.append(event)
                    if let summary { published.append(Self.publish(event, summary, at: at)) }
                }
            } catch {
                lastError = error
            }
        }
        dispatcher.dispatch(published)
        return issued
    }

    static func publish(_ e: SeriesSummaryIssued, _ s: MonthlySummary, at: Date) -> SeriesSummaryIssuedPublished {
        SeriesSummaryIssuedPublished(
            seriesId: e.seriesId.value, seriesName: e.name.value, year: e.month.year, month: e.month.month,
            monthName: s.monthName, headline: s.headline, occurredAt: at)
    }
}
