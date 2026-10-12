import EventDispatch
import Foundation
import MatchesDomain
import Observation
import UpgradePublished

/// `MatchSettingsView` + `ChangeMatchDefaults` + `SetLiveMatchLimit` (spec 007), persisted per device.
///
/// Edition guards (spec 026, ADR-0010/0011): while Free the effective defaults keep the stored game
/// but use a style and break rule the Free limits allow (most frames wins, alternate breaks), and the
/// effective live-match limit is the Free one, whatever is stored. Changing the style or break rule
/// and setting the limit are refused with `UpgradeRequired`; the game (S20) stays free. Nothing
/// stored is rewritten to enforce a limit, so unlocking brings the stored values straight back.
@MainActor @Observable
public final class MatchSettingsService: MatchSettings {
    private let store: any MatchSettingsStore
    /// What is stored, whatever the edition.
    public private(set) var values: MatchSettingsValues
    /// Upgrade's `CurrentEdition` open host (ADR-0011): read it before a guarded action. Unlocked
    /// (no limits) until the composition root hands over the device's edition.
    @ObservationIgnored public var edition: any CurrentEdition
    /// Bumped on `AppUnlocked` / `AppLocked`, so views reading the effective values re-render.
    private var editionChanges = 0

    public init(store: any MatchSettingsStore, edition: any CurrentEdition = FixedEdition.unlocked) throws {
        self.store = store
        self.edition = edition
        values = try store.get() ?? .initial
    }

    // MARK: MatchSettingsView (effective values)

    /// The defaults New Game offers: the stored ones, with the Free style and break rule while Free.
    public var defaults: MatchDefaults { MatchDefaults(effectiveDefaults) }

    /// The limit `StartMatch` should enforce: the Free limit while Free, the stored one otherwise.
    public var liveMatchLimit: Int { effectiveLiveMatchLimit.value }

    public var effectiveDefaults: MatchesDomain.MatchDefaults {
        _ = editionChanges
        let stored = values.defaults
        guard let limits = edition.limits else { return stored }
        return MatchesDomain.MatchDefaults(
            game: stored.game,
            style: limits.allows(settingsStyleKind(stored.style)) ? stored.style : .mostFramesWins,
            breakRule: limits.allows(settingsBreakRuleKind(stored.breakRule)) ? stored.breakRule : .alternate)
    }

    public var effectiveLiveMatchLimit: LiveMatchLimit {
        _ = editionChanges
        guard let limits = edition.limits, case .success(let free) = LiveMatchLimit.create(limits.liveMatches)
        else { return values.liveMatchLimit }
        return free
    }

    // MARK: ChangeMatchDefaults

    /// Free: a style or break-rule change is refused (`UpgradeRequired`); the game still changes, and
    /// the stored style and break rule are left as they are.
    public func changeDefaults(_ defaults: MatchDefaults) throws {
        let requested = try defaults.domain()
        var next = values
        if edition.limits != nil {
            let current = effectiveDefaults
            if requested.style != current.style {
                throw UpgradeRequired(settingsPaidFeature(of: requested.style) ?? .raceTo)
            }
            if requested.breakRule != current.breakRule { throw UpgradeRequired(.winnerBreaks) }
            next.defaults = MatchesDomain.MatchDefaults(
                game: requested.game, style: values.defaults.style, breakRule: values.defaults.breakRule)
        } else {
            next.defaults = requested
        }
        try store.save(next)
        values = next
    }

    // MARK: SetLiveMatchLimit

    /// Paid: refused with `UpgradeRequired(.severalLiveMatches)` while Free. Clamped to 1…100 (the
    /// stepper's range).
    public func setLiveMatchLimit(_ limit: Int) throws {
        guard edition.allows(.severalLiveMatches) else { throw UpgradeRequired(.severalLiveMatches) }
        let clamped = min(LiveMatchLimit.range.upperBound, max(LiveMatchLimit.range.lowerBound, limit))
        guard case .success(let l) = LiveMatchLimit.create(clamped) else { return }
        var next = values
        next.liveMatchLimit = l
        try store.save(next)
        values = next
    }

    /// `setLiveMatchLimit` without an error channel: a refusal or a failed write keeps the old value.
    public func changeLiveMatchLimit(_ limit: Int) {
        try? setLiveMatchLimit(limit)
    }

    // MARK: Edition changes

    /// `AppUnlocked` / `AppLocked`: the effective values change, so observers re-read them.
    public func subscribe(to dispatcher: EventDispatcher) {
        dispatcher.subscribe(AppUnlockedPublished.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.editionChanges += 1 }
        }
        dispatcher.subscribe(AppLockedPublished.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.editionChanges += 1 }
        }
    }
}

// Matches' style and break rule as Upgrade's Free limits name them (ADR-0011).

private func settingsStyleKind(_ style: MatchesDomain.MatchStyle) -> MatchStyleKind {
    switch style {
    case .mostFramesWins: .mostFramesWins
    case .raceTo: .raceTo
    case .sets: .sets
    }
}

private func settingsBreakRuleKind(_ rule: MatchesDomain.BreakRule) -> BreakRuleKind {
    rule == .alternate ? .alternate : .winnerBreaks
}

/// The paid feature behind choosing `style` as the default (S21); nil for most frames wins.
private func settingsPaidFeature(of style: MatchesDomain.MatchStyle) -> PaidFeature? {
    switch style {
    case .mostFramesWins: nil
    case .raceTo: .raceTo
    case .sets: .sets
    }
}
