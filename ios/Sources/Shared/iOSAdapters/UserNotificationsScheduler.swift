#if canImport(UserNotifications)
import Foundation
import MatchesApplication
import UserNotifications

// UserNotifications anti-corruption adapter (spec 019): local notifications for the long-frame
// warnings (S37, `NotificationScheduler`) and, later, the monthly series summary (S38). No
// UserNotifications type crosses into a context's application layer.

/// `NotificationScheduler` over `UNUserNotificationCenter`. `deliver(title:body:at:id:)` is the generic
/// entry point other contexts' ports (e.g. Stats' `SeriesSummaryIssued`, spec 017) can adapt to.
@MainActor
public final class UserNotificationsScheduler: NotificationScheduler {
    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    /// `center` defaults to `.current()`, which needs an app bundle: build one only in the app.
    public init(center: UNUserNotificationCenter = .current(), calendar: Calendar = .current) {
        self.center = center
        self.calendar = calendar
    }

    /// Asks for alert + sound permission once; later calls return the stored answer without a prompt.
    /// Call at a point where a warning makes sense to the Scorer (see spec 019), never before Welcome.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Shows `title`/`body` at `date` (straight away when `date` has passed), replacing any pending
    /// notification with the same `id`. Without permission the system drops it; nothing else changes.
    public func deliver(title: String, body: String, at date: Date, id: String) {
        center.add(Self.request(id: id, title: title, body: body, at: date, calendar: calendar)) { _ in }
    }

    public func schedule(_ notifications: [ScheduledNotification]) {
        for n in notifications { deliver(title: n.title, body: n.body, at: n.fireAt, id: n.id) }
    }

    public func cancel(_ ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// The request for one notification: a calendar trigger at `date` to the second (wall-clock, so it
    /// is unaffected by how long the request takes to reach the system), or none (deliver now) when
    /// `date` is not in the future.
    nonisolated public static func request(
        id: String, title: String, body: String, at date: Date, calendar: Calendar = .current, now: Date = Date()
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger: UNNotificationTrigger? = date > now
            ? UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date),
                repeats: false)
            : nil
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}

/// Shows notifications as banners while the app is in the foreground too (by default iOS only shows
/// them in the background). Keep a strong reference and set it as `UNUserNotificationCenter.delegate`.
public final class ForegroundNotificationBanners: NSObject, UNUserNotificationCenterDelegate, Sendable {
    override public init() { super.init() }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
#endif
