import Foundation

public enum ChosenEndTimeError: Error, Equatable, Sendable {
    case beforeLastAction(chosen: Date, lastAction: Date)
    case afterNow(chosen: Date, now: Date)
}

/// An end time picked for a stale match: last recorded action ≤ t ≤ now.
public struct ChosenEndTime: Hashable, Sendable, Codable {
    public let date: Date

    private init(date: Date) { self.date = date }

    public static func create(_ chosen: Date, lastAction: Date, now: Date) -> Result<ChosenEndTime, ChosenEndTimeError> {
        guard chosen >= lastAction else { return .failure(.beforeLastAction(chosen: chosen, lastAction: lastAction)) }
        guard chosen <= now else { return .failure(.afterNow(chosen: chosen, now: now)) }
        return .success(ChosenEndTime(date: chosen))
    }
}

/// The length a stale match is capped to: the average length of past finished matches between the
/// same two players on the same weekday (computed by the caller from Stats), else 3 h.
public struct CappedLength: Hashable, Sendable, Codable {
    public static let fallback: PlayDuration = .hours(3)

    public let length: PlayDuration

    private init(length: PlayDuration) { self.length = length }

    public static func from(samePairSameWeekdayAverage average: PlayDuration?) -> CappedLength {
        CappedLength(length: average ?? fallback)
    }
}

/// The scorer's choice in the stale-match prompt.
public enum StaleResolution: Hashable, Sendable, Codable {
    case resume
    case endAt(ChosenEndTime)
    case endCapped(CappedLength)
    case abandon
    case cancel
}
