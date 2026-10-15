import AppComposition
import SwiftUI

@main
struct SnookerTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Also runs when iOS launches the app in the background for a lock-screen button.
        LockScreenLiveActivity.install()
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
        }
    }
}
