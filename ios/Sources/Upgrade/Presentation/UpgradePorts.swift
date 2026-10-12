import Foundation
import Observation
import SwiftUI
import UpgradeApplication
import UpgradePublished

/// What Upgrade's screens (the offer and the benefits screen, a later spec) need from the application
/// layer. Built by the composition root.
public struct UpgradePorts: Sendable {
    public let edition: any CurrentEdition
    public let commands: UpgradeUseCases
    public let showOffer: ShowUpgradeOffer

    public init(edition: any CurrentEdition, commands: UpgradeUseCases) {
        self.edition = edition
        self.commands = commands
        showOffer = ShowUpgradeOffer(edition: edition)
    }
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
