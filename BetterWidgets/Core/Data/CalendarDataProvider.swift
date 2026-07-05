import Foundation
import EventKit

struct CalendarEventDTO: Equatable {
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let location: String?
}

protocol EventFetching {
    func upcomingEvents(within days: Int) async throws -> [CalendarEventDTO]
}

/// Real EventKit-backed fetcher. Requests calendar access, then queries events
/// from now to `days` ahead across all calendars.
struct EventKitFetcher: EventFetching {
    func upcomingEvents(within days: Int) async throws -> [CalendarEventDTO] {
        let store = EKEventStore()
        // macOS 14+ API — requestAccess(to:) no longer prompts and just denies.
        let granted = try await store.requestFullAccessToEvents()
        guard granted else { throw DataProviderError.missingConfig("calendar access denied") }
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map {
            CalendarEventDTO(title: $0.title ?? "", start: $0.startDate, end: $0.endDate,
                             allDay: $0.isAllDay, location: $0.location)
        }
    }
}

struct CalendarDataProvider: DataProvider {
    static let type = "calendar"
    let minimumInterval: TimeInterval = 300
    let fetcher: EventFetching

    func fetch(spec: SourceSpec, paramValues: [String: String]) async throws -> Any {
        // Substitute {{param}} first: the manifest passes `days: "{{days}}"`, so a raw Int.init
        // on the un-substituted value would always fail and silently fall back to 7 (dead control).
        let days = spec.config?["days"].map { substituteParams($0, params: paramValues) }.flatMap(Int.init) ?? 7
        let events = try await fetcher.upcomingEvents(within: days)
        let iso = ISO8601DateFormatter()
        let mapped: [[String: Any]] = events.map { event in
            var dict: [String: Any] = [
                "title": event.title,
                "start": iso.string(from: event.start),
                "end": iso.string(from: event.end),
                "allDay": event.allDay,
            ]
            if let location = event.location { dict["location"] = location }
            return dict
        }
        return ["events": mapped]
    }
}
