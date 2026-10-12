import Foundation

/// The App Store identifier of the single non-consumable purchase that unlocks the app (S49, S50).
public struct UnlockProductId: Hashable, Sendable, Codable, CustomStringConvertible {
    public let value: String

    /// Refuses a blank identifier.
    public init?(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.value = trimmed
    }

    /// The product configured in App Store Connect.
    public static let fullVersion = UnlockProductId("com.snookertracker.unlock")!

    public var description: String { value }
}
