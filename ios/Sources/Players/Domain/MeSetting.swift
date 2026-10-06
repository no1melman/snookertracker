import Foundation

/// Which player is "Me" on this device (the `Me` value: an optional `PlayerId`).
/// One per device. A setting: none of its changes raise events.
public struct MeSetting: Hashable, Sendable, Codable {
    /// The device owner's player, or `nil` until set.
    public private(set) var me: PlayerId?

    private init(me: PlayerId?) { self.me = me }

    /// No player is Me yet (first launch, or after the Me player was removed).
    public static let unset = MeSetting(me: nil)

    /// Rebuilds the setting from storage.
    public static func reconstitute(me: PlayerId?) -> MeSetting { MeSetting(me: me) }

    public var isSet: Bool { me != nil }

    public func set(_ player: PlayerId) -> MeSetting { MeSetting(me: player) }

    public func clear() -> MeSetting { .unset }

    /// On `PlayersMerged`: if the folded-in player was Me, Me follows the kept player.
    public func followingMerge(foldedIn: PlayerId, kept: PlayerId) -> MeSetting {
        me == foldedIn ? set(kept) : self
    }

    /// On `PlayerRemoved`: if the removed player was Me, Me is cleared.
    public func clearingOnRemoval(of removed: PlayerId) -> MeSetting {
        me == removed ? clear() : self
    }
}
