import EventKit

/// Reads upcoming meetings from calendars synced into macOS Calendar (EventKit).
final class CalendarReader {
    struct Meeting: Equatable {
        let title: String
        let start: Date
        let end: Date
        let calendar: String
    }

    enum Access { case unknown, granted, denied }

    let store = EKEventStore()
    private(set) var access: Access = .unknown

    func requestAccess() async {
        do {
            access = try await store.requestFullAccessToEvents() ? .granted : .denied
        } catch {
            access = .denied
        }
    }

    /// Meetings in progress or upcoming within 7 days, earliest first, at most `limit`.
    /// Skips all-day events and events the current user declined.
    func nextMeetings(limit: Int, now: Date = Date()) -> [Meeting] {
        guard access == .granted else { return [] }
        let calendars = store.calendars(for: .event)
        let horizon = now.addingTimeInterval(7 * 24 * 3600)
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-12 * 3600), end: horizon, calendars: calendars)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now && !isDeclined($0) }
            .sorted { $0.startDate < $1.startDate }
            .prefix(limit)
            .map { Meeting(title: $0.title ?? "(No title)", start: $0.startDate, end: $0.endDate, calendar: $0.calendar.title) }
    }

    private func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus == .declined
    }
}
