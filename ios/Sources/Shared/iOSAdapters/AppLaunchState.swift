#if canImport(UIKit)
import UIKit
#endif

extension AppLifecycle {
    /// Whether iOS started this process in the background (e.g. to run a Live Activity button) rather
    /// than the user opening the app. Read it at launch, before the first scene connects.
    public static var processLaunchedInBackground: Bool {
        #if canImport(UIKit)
        UIApplication.shared.applicationState == .background
        #else
        false
        #endif
    }
}
