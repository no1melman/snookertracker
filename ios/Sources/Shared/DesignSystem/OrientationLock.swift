#if canImport(UIKit)
import UIKit

/// Only the live match screen turns sideways (spec 030); every other screen stays portrait. The app
/// delegate answers iOS with `mask`, and the live screen widens it while it is on screen. The iPhone's
/// rotation lock still wins: with it on, the screen stays portrait.
@MainActor
public enum OrientationLock {
    public private(set) static var mask: UIInterfaceOrientationMask = .portrait

    public static func allowLandscape(_ allowed: Bool) {
        mask = allowed ? .allButUpsideDown : .portrait
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            if !allowed, scene.interfaceOrientation.isLandscape {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        }
    }
}
#endif
