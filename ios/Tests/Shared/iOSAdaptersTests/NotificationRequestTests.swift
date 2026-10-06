#if canImport(UserNotifications)
import Foundation
import iOSAdapters
import Testing
import UserNotifications

// UserNotifications adapter (spec 019): the request each notification becomes. The adapter's calls on
// `UNUserNotificationCenter` need an app bundle, so they are checked on the simulator (spec 019).

@Suite("UserNotificationsScheduler requests")
struct NotificationRequestTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()

    @Test func futureDateBecomesAOneOffCalendarTriggerToTheSecond() throws {
        let fireAt = now.addingTimeInterval(30 * 60 + 17)
        let request = UserNotificationsScheduler.request(
            id: "long-frame.x.0", title: "Long-running frame", body: "Frame 1: 30 minutes.",
            at: fireAt, calendar: calendar, now: now)

        #expect(request.identifier == "long-frame.x.0")
        #expect(request.content.title == "Long-running frame")
        #expect(request.content.body == "Frame 1: 30 minutes.")
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(!trigger.repeats)
        #expect(calendar.date(from: trigger.dateComponents) == fireAt)
    }

    @Test func pastOrPresentDateIsDeliveredStraightAway() {
        let request = UserNotificationsScheduler.request(
            id: "summary", title: "t", body: "b", at: now, calendar: calendar, now: now)
        #expect(request.trigger == nil)
    }
}
#endif
