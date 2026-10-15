#if canImport(UIKit)
import DesignSystem
import UIKit

/// Answers iOS's orientation question from `OrientationLock` (spec 030): portrait everywhere except
/// the live match screen.
public final class AppDelegate: NSObject, UIApplicationDelegate {
    public func application(_ application: UIApplication,
                            supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
#endif
