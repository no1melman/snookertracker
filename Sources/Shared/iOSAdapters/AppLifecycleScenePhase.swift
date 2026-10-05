import SwiftUI

/// Feeds SwiftUI's scene phase into `AppLifecycle`, keeping lifecycle types out of the app's layers.
private struct RecordsAppLifecycle: ViewModifier {
    let lifecycle: AppLifecycle
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: lifecycle.didEnterBackground()
            case .active: lifecycle.didBecomeActive()
            default: break  // .inactive (control centre, app switcher) is neither
            }
        }
    }
}

public extension View {
    /// Records background time and returns to the foreground for kill detection (S27).
    func recordsAppLifecycle(_ lifecycle: AppLifecycle) -> some View {
        modifier(RecordsAppLifecycle(lifecycle: lifecycle))
    }
}
