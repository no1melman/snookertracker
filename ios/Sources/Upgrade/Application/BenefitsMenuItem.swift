import EventDispatch
import Foundation
import Observation
import UpgradePublished

/// The hub's "Upgrade" menu item (S53), the read side of `BenefitsScreen`: visible only while Free.
/// Starts from the cached edition, then follows Upgrade's own published events: hidden on
/// `AppUnlocked`, shown again on `AppLocked`. It only shows a menu row; it never opens anything.
@MainActor @Observable
public final class BenefitsMenuItem {
    public private(set) var isVisible: Bool

    public init(edition: any CurrentEdition) {
        isVisible = edition.isFree
    }

    /// Subscribe before anything can dispatch. Upgrade's use cases dispatch on the main actor.
    public func subscribe(to dispatcher: EventDispatcher) {
        dispatcher.subscribe(AppUnlockedPublished.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.isVisible = false }
        }
        dispatcher.subscribe(AppLockedPublished.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.isVisible = true }
        }
    }
}
