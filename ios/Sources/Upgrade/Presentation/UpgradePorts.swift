import Foundation
import Observation
import SwiftUI
import UpgradeApplication
import UpgradePublished

/// What Upgrade's screens (the offer and the benefits screen, spec 029) need from the application
/// layer. Built by the composition root.
public struct UpgradePorts: Sendable {
    public let edition: any CurrentEdition
    public let commands: UpgradeUseCases
    public let showOffer: ShowUpgradeOffer
    /// The hub's benefits menu item (S53), subscribed to `AppUnlocked` / `AppLocked` by the
    /// composition root. The offer screens watch it to close once the edition unlocks.
    public let menuItem: BenefitsMenuItem?

    public init(edition: any CurrentEdition, commands: UpgradeUseCases, menuItem: BenefitsMenuItem? = nil) {
        self.edition = edition
        self.commands = commands
        self.menuItem = menuItem
        showOffer = ShowUpgradeOffer(edition: edition)
    }

    /// Whether the edition is Free right now: observable through `menuItem` when there is one.
    @MainActor public var isFree: Bool { menuItem?.isVisible ?? edition.isFree }
}

public extension EnvironmentValues {
    @Entry var upgradePorts: UpgradePorts? = nil
}

/// Where a refused paid feature lands (S52): `show` sets `request` through `ShowUpgradeOffer` (nothing
/// once Unlocked); the offer UI presents it in place or as the generic screen, and clears it. Only a
/// touch on a paid feature ever sets it, so the offer never appears on launch or as a repeated pop-up.
@MainActor @Observable
public final class UpgradeOfferRouter {
    @ObservationIgnored private let showOffer: ShowUpgradeOffer
    public var request: UpgradeOfferRequest?

    public init(edition: any CurrentEdition) {
        showOffer = ShowUpgradeOffer(edition: edition)
    }

    public func show(_ feature: PaidFeature) {
        request = showOffer(feature)
    }

    public func dismiss() { request = nil }
}
