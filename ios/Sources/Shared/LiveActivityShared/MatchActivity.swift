import Foundation
#if os(iOS) && canImport(ActivityKit)
import ActivityKit
#endif

// Shared between the app and the Live Activity widget extension (spec 018). Plain data only: the
// app's adapter (iOSAdapters) maps `LockScreenState` into it; the extension only renders it.

/// The lock-screen match's Live Activity. Everything lives in `ContentState`, so handing over to the
/// next-oldest match is an update, not a new activity.
public struct MatchActivityAttributes: Hashable, Codable, Sendable {
    public struct ContentState: Hashable, Codable, Sendable {
        public struct Side: Hashable, Codable, Sendable {
            public var player: UUID
            public var name: String
            /// Palette key (DesignSystem `PlayerColour` raw value).
            public var colour: String
            public var frames: Int
            public var isBreaker: Bool

            public init(player: UUID, name: String, colour: String, frames: Int, isBreaker: Bool) {
                self.player = player
                self.name = name
                self.colour = colour
                self.frames = frames
                self.isBreaker = isBreaker
            }
        }

        public var matchID: UUID
        public var sides: [Side]
        /// Origin of the frame timer: when the frame would have started had it never been paused.
        public var frameTimerStart: Date
        /// Set while paused: the timer shows the frozen value `pausedAt - frameTimerStart`.
        public var pausedAt: Date?
        public var canAward: Bool
        public var canPause: Bool
        public var canResume: Bool

        public init(
            matchID: UUID, sides: [Side], frameTimerStart: Date, pausedAt: Date?,
            canAward: Bool, canPause: Bool, canResume: Bool
        ) {
            self.matchID = matchID
            self.sides = sides
            self.frameTimerStart = frameTimerStart
            self.pausedAt = pausedAt
            self.canAward = canAward
            self.canPause = canPause
            self.canResume = canResume
        }

        public var isPaused: Bool { pausedAt != nil }

        /// VoiceOver form: "Asher 4, Callum 3".
        public var spokenScore: String { sides.map { "\($0.name) \($0.frames)" }.joined(separator: ", ") }
    }

    public init() {}
}

#if os(iOS) && canImport(ActivityKit)
extension MatchActivityAttributes: ActivityAttributes {}
#endif

// MARK: - Lock-screen buttons

/// What the lock-screen buttons (App Intents, `LiveActivityIntent`) ask of the app. The intents run
/// in the app process; the composition root installs the implementation in `MatchActivityCommandRoute`.
@MainActor public protocol MatchActivityCommands: AnyObject {
    func awardFrame(match: UUID, to player: UUID) throws
    func pauseMatch(_ match: UUID) throws
    func resumeMatch(_ match: UUID) throws
}

public enum MatchActivityCommandError: Error, Sendable {
    /// The intent ran somewhere the app has not installed its commands (e.g. the widget process).
    case notInstalled
}

@MainActor public enum MatchActivityCommandRoute {
    public static var commands: (any MatchActivityCommands)?

    public static func resolve() throws -> any MatchActivityCommands {
        guard let commands else { throw MatchActivityCommandError.notInstalled }
        return commands
    }
}
