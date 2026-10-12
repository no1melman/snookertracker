import Foundation

/// The device's edition became Unlocked (S49, S50).
public struct AppUnlocked: Hashable, Sendable, Codable {
    public let occurredAt: Date

    public init(occurredAt: Date) { self.occurredAt = occurredAt }
}

/// The device's edition went back to Free (S51).
public struct AppLocked: Hashable, Sendable, Codable {
    public let occurredAt: Date

    public init(occurredAt: Date) { self.occurredAt = occurredAt }
}

/// Every event the `Edition` aggregate raises.
public enum EditionEvent: Hashable, Sendable, Codable {
    case unlocked(AppUnlocked)
    case locked(AppLocked)
}
