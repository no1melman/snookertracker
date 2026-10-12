import EventDispatch
import Foundation
import UpgradePublished

/// The lock-screen Live Activity as Matches sees it: the ActivityKit adapter (spec 018) implements it.
@MainActor public protocol LiveActivityPort: AnyObject {
    /// Removes the Live Activity, if one is shown.
    func removeLiveActivity()
}

/// `RemoveLiveActivityOnLock` (S47, S51): policy on Upgrade's `AppLocked`. The lock screen is paid,
/// so the Live Activity is removed. Nothing else happens: live matches carry on unchanged, keeping
/// their style, break rule and pauses (nothing is deleted or rewritten to enforce a limit).
@MainActor
public final class RemoveLiveActivityOnLock {
    private let liveActivity: any LiveActivityPort

    public init(liveActivity: any LiveActivityPort) {
        self.liveActivity = liveActivity
    }

    public func subscribe(to dispatcher: EventDispatcher) {
        dispatcher.subscribe(AppLockedPublished.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.handle() }
        }
    }

    public func handle() {
        liveActivity.removeLiveActivity()
    }
}
