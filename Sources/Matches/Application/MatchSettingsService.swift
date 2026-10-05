import Foundation
import MatchesDomain
import Observation

/// `MatchSettingsView` + `ChangeMatchDefaults` + `SetLiveMatchLimit` (spec 007), persisted per device.
@MainActor @Observable
public final class MatchSettingsService: MatchSettings {
    private let store: any MatchSettingsStore
    public private(set) var values: MatchSettingsValues

    public init(store: any MatchSettingsStore) throws {
        self.store = store
        values = try store.get() ?? .initial
    }

    public var defaults: MatchDefaults { MatchDefaults(values.defaults) }
    public var liveMatchLimit: Int { values.liveMatchLimit.value }

    public func changeDefaults(_ defaults: MatchDefaults) throws {
        var next = values
        next.defaults = try defaults.domain()
        try store.save(next)
        values = next
    }

    /// Clamped to 1…100 (the stepper's range).
    public func changeLiveMatchLimit(_ limit: Int) {
        let clamped = min(LiveMatchLimit.range.upperBound, max(LiveMatchLimit.range.lowerBound, limit))
        guard case .success(let l) = LiveMatchLimit.create(clamped) else { return }
        var next = values
        next.liveMatchLimit = l
        // The port has no error channel here; a failed write keeps the old value on screen.
        guard (try? store.save(next)) != nil else { return }
        values = next
    }
}
