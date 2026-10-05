import iOSAdapters
import LiveActivityShared

/// Composition for the lock-screen Live Activity (spec 018): the ActivityKit adapter follows
/// `LockScreenState` after every stored match event, and the lock-screen buttons (App Intents
/// performed in this process) are routed to the Matches use cases.
///
/// Installed from the app's `init`, so it is in place even when iOS launches the app in the
/// background just to perform a lock-screen button.
@MainActor
public enum LockScreenLiveActivity {
    private static var activity: LockScreenActivity?

    public static func install() {
        guard activity == nil else { return }
        let container = AppContainer.shared
        MatchActivityCommandRoute.commands = LockScreenCommands(commands: container.matchCommands)
        #if os(iOS) && canImport(ActivityKit)
        let presenter = ActivityKitLockScreenPresenter()
        let activity = LockScreenActivity(state: container.liveMatches, presenter: presenter)
        activity.subscribe(to: container.dispatcher)
        presenter.observeForeground { activity.refresh() }
        activity.refresh()
        self.activity = activity
        #endif
    }
}
