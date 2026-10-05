#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation
import LiveActivityShared
import UIKit

/// ActivityKit implementation of `LockScreenPresenter`: one `Activity<MatchActivityAttributes>`,
/// local updates only (no push token, so no push capability is needed).
@MainActor
public final class ActivityKitLockScreenPresenter: LockScreenPresenter {
    private var activity: Activity<MatchActivityAttributes>?
    private var foregroundObserver: (any NSObjectProtocol)?

    /// Adopts an activity left by an earlier run of the app and ends any extras.
    public init() {
        let existing = Activity<MatchActivityAttributes>.activities
        activity = existing.first
        for extra in existing.dropFirst() { enqueue(id: extra.id) { await $0.end(nil, dismissalPolicy: .immediate) } }
    }

    /// Calls `onActive` whenever the app returns to the foreground (an activity can only be started
    /// from the foreground, so a refused start is retried then).
    public func observeForeground(_ onActive: @escaping @MainActor () -> Void) {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onActive() }
        }
    }

    public func start(_ content: MatchActivityAttributes.ContentState) -> Bool {
        if let current = activity, current.activityState == .active || current.activityState == .stale {
            update(content)
            return true
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        do {
            activity = try Activity.request(
                attributes: MatchActivityAttributes(), content: .init(state: content, staleDate: nil), pushType: nil)
            return true
        } catch {
            return false
        }
    }

    public func update(_ content: MatchActivityAttributes.ContentState) {
        // The Scorer can swipe the activity away; then show a fresh one.
        if let current = activity, current.activityState == .ended || current.activityState == .dismissed {
            activity = nil
        }
        guard activity != nil else {
            _ = start(content)
            return
        }
        guard let id = activity?.id else { return }
        enqueue(id: id) { await $0.update(.init(state: content, staleDate: nil)) }
    }

    public func end() {
        guard let activity else { return }
        self.activity = nil
        enqueue(id: activity.id) { await $0.end(nil, dismissalPolicy: .immediate) }
    }

    /// Runs ActivityKit calls one after another, in the order the match changed. `Activity` is not
    /// Sendable, so each task looks its activity up again by id instead of capturing it.
    private var pending: Task<Void, Never>?

    private func enqueue(
        id: String, _ work: @escaping @Sendable (Activity<MatchActivityAttributes>) async -> Void
    ) {
        let previous = pending
        pending = Task.detached {
            await previous?.value
            guard let activity = Activity<MatchActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
            await work(activity)
        }
    }
}
#endif
