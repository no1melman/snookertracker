import Foundation

// The `NotificationScheduler` port (spec 015, S37): local notifications handed to the OS ahead of time,
// so they fire while the app is suspended. Implemented with UserNotifications in iOSAdapters (spec 019).

/// One local notification: what to show and when. Scheduling an `id` that is already pending
/// replaces it, so a policy can reschedule by reusing its ids.
public struct ScheduledNotification: Hashable, Sendable {
    public let id: String
    public var title: String
    public var body: String
    public var fireAt: Date

    public init(id: String, title: String, body: String, fireAt: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.fireAt = fireAt
    }
}

/// Schedules and cancels local notifications by id. Fire-and-forget: when notifications are not
/// allowed nothing is shown and nothing else changes (S37 failure path).
@MainActor public protocol NotificationScheduler: AnyObject, Sendable {
    /// Schedules each notification, replacing any pending one with the same id.
    func schedule(_ notifications: [ScheduledNotification])
    /// Cancels pending notifications with these ids; unknown ids are ignored.
    func cancel(_ ids: [String])
}

/// In-memory `NotificationScheduler` for tests and previews: keeps what is pending, by id.
@MainActor
public final class InMemoryNotificationScheduler: NotificationScheduler {
    public private(set) var pending: [String: ScheduledNotification] = [:]

    public init() {}

    public func schedule(_ notifications: [ScheduledNotification]) {
        for n in notifications { pending[n.id] = n }
    }

    public func cancel(_ ids: [String]) {
        for id in ids { pending[id] = nil }
    }

    /// Pending notifications, soonest first.
    public var queue: [ScheduledNotification] {
        pending.values.sorted { ($0.fireAt, $0.id) < ($1.fireAt, $1.id) }
    }
}
