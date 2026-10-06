import Foundation
import MatchesApplication

/// How the previous process ended, as seen from this launch.
public enum PreviousSession: Equatable, Sendable {
    /// First launch on this install: nothing to recover.
    case none
    /// The last session was killed rather than returned to the foreground (swiped away, killed by iOS,
    /// the phone died, a crash). `lastBackgroundAt` is when it last went to the background, or nil if it
    /// was on screen when it died.
    case killed(lastBackgroundAt: Date?)
    /// iOS started this process in the background to run a lock-screen button (S47). The match is plainly
    /// still being played, so nothing is auto-paused (ADR-0007); the background time is kept for a later launch.
    case launchedInBackground
}

/// App lifecycle anti-corruption adapter (S27, ADR-0004). iOS gives no reliable signal when it kills a
/// suspended app, so the kill is detected on the next launch: every new process means the previous one
/// died without coming back to the foreground. The markers are persisted in `UserDefaults`.
///
/// Going to the background never pauses anything here; it only records the time.
@MainActor
public final class AppLifecycle {
    private enum Key {
        static let sessionStarted = "lifecycle.sessionStarted"
        static let lastBackgroundAt = "lifecycle.lastBackgroundAt"
    }

    private let defaults: UserDefaults
    private let now: @Sendable () -> Date

    public init(defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    /// Call once per process, before anything reads live matches. Reports how the previous session
    /// ended and starts a new one (the app is on screen).
    ///
    /// `launchedInBackground`: iOS started this process to run a lock-screen button. That is not the
    /// user leaving the match, so it isn't treated as a kill (ADR-0007), and the last background time is
    /// kept: the app is still in the background.
    public func beginSession(launchedInBackground: Bool = false) -> PreviousSession {
        if launchedInBackground {
            defaults.set(true, forKey: Key.sessionStarted)
            return .launchedInBackground
        }
        let previous: PreviousSession = defaults.bool(forKey: Key.sessionStarted)
            ? .killed(lastBackgroundAt: defaults.object(forKey: Key.lastBackgroundAt) as? Date)
            : .none
        defaults.set(true, forKey: Key.sessionStarted)
        defaults.removeObject(forKey: Key.lastBackgroundAt)
        return previous
    }

    /// The app went to the background (switching apps, locking the phone).
    public func didEnterBackground() {
        defaults.set(now(), forKey: Key.lastBackgroundAt)
    }

    /// The app is back on screen.
    public func didBecomeActive() {
        defaults.removeObject(forKey: Key.lastBackgroundAt)
    }
}

/// What runs on launch, in order (S27 → S28). Must run before anything reads live matches.
@MainActor
public struct AppLaunchSequence {
    private let lifecycle: AppLifecycle
    private let matches: any LiveMatchAutoPausing
    private let afterAutoPause: [@MainActor () throws -> Void]

    /// `afterAutoPause` is the seam for checks that must see the auto-paused matches, such as
    /// `FlagStaleMatches` (S28, specs 014/015); they run on every launch, after auto-pause.
    public init(
        lifecycle: AppLifecycle, matches: any LiveMatchAutoPausing,
        afterAutoPause: [@MainActor () throws -> Void] = []
    ) {
        self.lifecycle = lifecycle
        self.matches = matches
        self.afterAutoPause = afterAutoPause
    }

    public func run(launchedInBackground: Bool = false) throws {
        if case .killed(let lastBackgroundAt) = lifecycle.beginSession(launchedInBackground: launchedInBackground) {
            try matches.autoPauseLiveMatches(lastBackgroundAt: lastBackgroundAt)
        }
        for step in afterAutoPause { try step() }
    }
}
