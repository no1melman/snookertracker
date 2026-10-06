import EventDispatch
import Foundation
import MatchesPublished

/// `WarnLongFrame` (S37): "long-running frame" when a frame has run 30 minutes (minus paused time),
/// then every 10 minutes until it ends or the match is paused. Thresholds are fixed, not settings.
///
/// The warnings must fire while the app is suspended, so instead of a timer this policy hands the OS
/// a batch of local notifications ahead of time and keeps them in step with the match:
/// - the frame timer (re)starts or resumes (`MatchStarted`, `BreakerChosen`, `FrameWon`,
///   `FrameRemoved`, `MatchResumed`, `MatchTargetReached`): reschedule from the match's frame timer,
///   or cancel when the match is no longer in play (awaiting a breaker or a Finish? confirmation);
/// - the match pauses or ends (`MatchPaused`, `MatchAutoPaused`, `MatchFinished`, `MatchAbandoned`,
///   `MatchCancelled`, `MatchDeleted`): cancel.
/// Other matches' warnings are never touched. Ids are derived from the match, so a reschedule replaces
/// the pending batch and a cancel finds it even after a relaunch.
///
/// `LongFrameWarned` is not recorded: the warning fires while the app may be suspended, when no event
/// can be stored. The notification is the whole reaction (event map: `LongFrameWarned` → iOS Notifications).
@MainActor
public final class WarnLongFrame {
    /// First warning, in frame time.
    nonisolated public static let firstWarning: TimeInterval = 30 * 60
    /// Interval between later warnings.
    nonisolated public static let repeatEvery: TimeInterval = 10 * 60
    /// Warnings scheduled ahead per match: 30, 40, …, 140 min. Bounded because iOS keeps at most 64
    /// pending notifications per app; any event on the match (or `rescheduleAll`) tops it up.
    nonisolated public static let batchSize = 12

    static let restarting: Set<String> = [
        "MatchStarted", "BreakerChosen", "FrameWon", "FrameRemoved", "MatchResumed", "MatchTargetReached",
    ]
    static let stopping: Set<String> = [
        "MatchPaused", "MatchAutoPaused", "MatchFinished", "MatchAbandoned", "MatchCancelled", "MatchDeleted",
    ]

    private let matches: any LiveMatchScreenQuery & LiveMatchesQuery
    private let scheduler: any NotificationScheduler

    /// `matches` is the live-match read model; use cases project it before they dispatch, so it is
    /// current when a published event arrives here.
    public init(matches: any LiveMatchScreenQuery & LiveMatchesQuery, scheduler: any NotificationScheduler) {
        self.matches = matches
        self.scheduler = scheduler
    }

    public func subscribe(to dispatcher: EventDispatcher) {
        dispatcher.subscribe(MatchEventPublished.self) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
        }
    }

    public func receive(_ event: MatchEventPublished) {
        if Self.stopping.contains(event.type) {
            cancel(event.matchId)
        } else if Self.restarting.contains(event.type) {
            reschedule(event.matchId)
        }
    }

    /// Reschedules every live match's warnings: call at launch (after `AutoPauseLiveMatches`) and once
    /// notification permission is granted, so a match started before the grant is covered.
    public func rescheduleAll() {
        for row in matches.liveMatches { reschedule(row.id) }
    }

    /// Schedules the match's next warnings from its frame timer, or cancels them when it is not in play.
    public func reschedule(_ match: MatchID) {
        guard let screen = matches.liveMatchScreen(match), screen.controls.award,
              let anchor = screen.frameTimer.runningSince
        else {
            cancel(match)
            return
        }
        scheduler.schedule(Self.warnings(for: screen, from: anchor))
    }

    public func cancel(_ match: MatchID) {
        scheduler.cancel(Self.ids(for: match))
    }

    // MARK: Schedule

    /// The next `batchSize` thresholds after the frame time already run (`accumulated` at `anchor`),
    /// each placed at `anchor` + the frame time still to run to it.
    static func warnings(for screen: LiveMatchScreen, from anchor: Date) -> [ScheduledNotification] {
        let elapsed = screen.frameTimer.accumulated
        let next = elapsed < firstWarning ? 0 : Int(((elapsed - firstWarning) / repeatEvery).rounded(.down)) + 1
        let names = screen.sides.map(\.name).joined(separator: " v ")
        return (0..<batchSize).map { k in
            let threshold = firstWarning + Double(next + k) * repeatEvery
            return ScheduledNotification(
                id: id(for: screen.id, slot: k),
                title: "Long-running frame",
                body: "Frame \(screen.frameNumber), \(names): \(Int(threshold / 60)) minutes.",
                fireAt: anchor.addingTimeInterval(threshold - elapsed))
        }
    }

    /// The ids of a match's warning batch.
    public static func ids(for match: MatchID) -> [String] {
        (0..<batchSize).map { id(for: match, slot: $0) }
    }

    static func id(for match: MatchID, slot: Int) -> String {
        "long-frame.\(match.uuidString).\(slot)"
    }
}
