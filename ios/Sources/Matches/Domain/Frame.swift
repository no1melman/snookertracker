import Foundation

/// One frame won. Live frames carry a length and the time they were won; a frame added by
/// correction has neither (and may not know its breaker).
///
/// Design for later (S23, snooker points): new facts such as a loss reason or a points breakdown
/// are added as further optional properties; existing stored frames decode unchanged.
public struct Frame: Hashable, Sendable, Codable {
    public let winner: Side
    /// 1-based, across the whole match.
    public let number: Int
    /// 1-based; always 1 outside the sets style.
    public let setNumber: Int
    /// nil for a corrected-in frame.
    public let length: PlayDuration?
    public let breaker: Side?
    /// When the frame was scored; nil for a corrected-in frame.
    public let wonAt: Date?

    init(winner: Side, number: Int, setNumber: Int, length: PlayDuration?, breaker: Side?, wonAt: Date?) {
        self.winner = winner
        self.number = number
        self.setNumber = setNumber
        self.length = length
        self.breaker = breaker
        self.wonAt = wonAt
    }

    func renumbered(number: Int, setNumber: Int) -> Frame {
        Frame(winner: winner, number: number, setNumber: setNumber, length: length, breaker: breaker, wonAt: wonAt)
    }
}

/// Frames per side; for sets also sets won and current-set frames, shown "(1) 5 – 2 (0)".
public struct Score: Hashable, Sendable, Codable, CustomStringConvertible {
    public struct Sets: Hashable, Sendable, Codable {
        public let firstSets: Int
        public let secondSets: Int
        public let firstCurrentSetFrames: Int
        public let secondCurrentSetFrames: Int

        public init(firstSets: Int, secondSets: Int, firstCurrentSetFrames: Int, secondCurrentSetFrames: Int) {
            self.firstSets = firstSets
            self.secondSets = secondSets
            self.firstCurrentSetFrames = firstCurrentSetFrames
            self.secondCurrentSetFrames = secondCurrentSetFrames
        }
    }

    /// Total frames won by the setup's first player.
    public let firstFrames: Int
    /// Total frames won by the setup's second player.
    public let secondFrames: Int
    /// Present for the sets style only.
    public let sets: Sets?

    public init(firstFrames: Int, secondFrames: Int, sets: Sets? = nil) {
        self.firstFrames = firstFrames
        self.secondFrames = secondFrames
        self.sets = sets
    }

    public static let zero = Score(firstFrames: 0, secondFrames: 0)

    public var description: String {
        guard let s = sets else { return "\(firstFrames) – \(secondFrames)" }
        return "(\(s.firstSets)) \(s.firstCurrentSetFrames) – \(s.secondCurrentSetFrames) (\(s.secondSets))"
    }
}

public enum MatchResult: Hashable, Sendable, Codable {
    case win(Side)
    case draw
}

/// Full timestamp stored; day and time displayed ("Fri 19:30").
public struct StartTime: Hashable, Comparable, Sendable, Codable {
    public let date: Date

    public init(_ date: Date) { self.date = date }

    public static func < (lhs: StartTime, rhs: StartTime) -> Bool { lhs.date < rhs.date }

    /// "Fri 19:30" in the given time zone.
    public func display(in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE HH:mm"
        return formatter.string(from: date)
    }
}
