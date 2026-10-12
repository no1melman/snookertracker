import Foundation
import Observation
import UpgradeApplication
import UpgradePublished

/// The state behind `BenefitsScreen` (S49, S50, S53): price, Buy and Restore.
///
/// Buy: purchased → `unlocked`; pending (Ask to Buy) → `waitingForApproval` until the approval arrives
/// as `AppUnlocked`; cancelled or failed → back to `ready`, the screen unchanged.
/// Restore: on record → `unlocked`; none → "Nothing to restore"; offline → "Couldn't reach the App Store".
@MainActor @Observable
public final class BenefitsScreenModel {
    public enum Phase: Hashable, Sendable {
        case ready
        case purchasing
        case restoring
        /// Ask to Buy: nothing unlocks until the approval arrives (even after a restart).
        case waitingForApproval
        /// The edition is Unlocked: the screen closes.
        case unlocked
    }

    public static let nothingToRestore = "Nothing to restore"
    public static let appStoreUnreachable = "Couldn't reach the App Store"

    @ObservationIgnored private let commands: UpgradeUseCases
    public private(set) var phase: Phase
    /// The localised price from the App Store; nil until loaded, or when offline.
    public private(set) var price: String?
    /// A one-off message for an alert (restore outcomes); clear it once shown.
    public var message: String?

    public init(commands: UpgradeUseCases, edition: any CurrentEdition) {
        self.commands = commands
        phase = edition.isUnlocked ? .unlocked : .ready
    }

    public var isBusy: Bool { phase == .purchasing || phase == .restoring }

    public func loadPrice() async {
        price = await commands.displayPrice()
    }

    public func buy() async {
        guard phase == .ready || phase == .waitingForApproval else { return }
        let before = phase
        phase = .purchasing
        do {
            switch try await commands.purchaseUnlock() {
            case .purchased: phase = .unlocked
            case .pending: phase = .waitingForApproval
            // Cancelled or failed: leave the screen as it was.
            case .cancelled, .failed: phase = before
            }
        } catch {
            phase = before
        }
    }

    public func restore() async {
        guard phase == .ready || phase == .waitingForApproval else { return }
        let before = phase
        phase = .restoring
        do {
            switch try await commands.restorePurchases() {
            case .unlocked: phase = .unlocked
            case .nothingToRestore:
                phase = before
                message = Self.nothingToRestore
            case .appStoreUnavailable:
                phase = before
                message = Self.appStoreUnreachable
            }
        } catch {
            phase = before
        }
    }

    /// The edition changed elsewhere: an Ask to Buy approval or a purchase on another family device
    /// (`AppUnlocked`), or a revocation (`AppLocked`).
    public func editionChanged(isFree: Bool) {
        if !isFree { phase = .unlocked } else if phase == .unlocked { phase = .ready }
    }
}
