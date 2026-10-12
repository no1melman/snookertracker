import Foundation

/// This device's edition (ADR-0010).
///
/// Allowed transitions, and no others:
/// - Free → Unlocked (a verified purchase, an Ask to Buy approval or a restore)
/// - Unlocked → Free (a revocation)
public enum EditionStatus: String, CaseIterable, Hashable, Sendable, Codable {
    /// The default: the Free limits apply.
    case free
    /// Every feature, for good, from one purchase.
    case unlocked

    public func canTransition(to next: EditionStatus) -> Bool {
        switch (self, next) {
        case (.free, .unlocked), (.unlocked, .free): true
        default: false
        }
    }
}
