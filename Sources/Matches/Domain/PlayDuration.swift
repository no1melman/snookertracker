import Foundation

public enum PlayDurationError: Error, Equatable, Sendable {
    case negative(TimeInterval)
}

/// Frame length / match length: elapsed time minus paused time; never negative.
/// The ubiquitous language calls it "Duration"; named `PlayDuration` to avoid shadowing `Swift.Duration`.
public struct PlayDuration: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let seconds: TimeInterval

    private init(seconds: TimeInterval) { self.seconds = seconds }

    public static func create(seconds: TimeInterval) -> Result<PlayDuration, PlayDurationError> {
        guard seconds >= 0 else { return .failure(.negative(seconds)) }
        return .success(PlayDuration(seconds: seconds))
    }

    public static let zero = PlayDuration(seconds: 0)

    public static func hours(_ h: Int) -> PlayDuration { PlayDuration(seconds: TimeInterval(max(h, 0) * 3600)) }
    public static func minutes(_ m: Int) -> PlayDuration { PlayDuration(seconds: TimeInterval(max(m, 0) * 60)) }

    /// `start → end` minus `paused`, floored at zero (approximate by nature).
    public static func elapsed(from start: Date, to end: Date, minusPaused paused: TimeInterval) -> PlayDuration {
        PlayDuration(seconds: max(0, end.timeIntervalSince(start) - paused))
    }

    public static func < (lhs: PlayDuration, rhs: PlayDuration) -> Bool { lhs.seconds < rhs.seconds }

    /// "1:05:09" or "5:09".
    public var description: String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        guard case .success(let d) = PlayDuration.create(seconds: try c.decode(TimeInterval.self)) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Negative PlayDuration")
        }
        self = d
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(seconds)
    }
}
