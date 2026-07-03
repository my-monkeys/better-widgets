import XCTest

final class CalendarDataProviderTests: XCTestCase {
    private struct FakeFetcher: EventFetching {
        let events: [CalendarEventDTO]
        var thrown: Error?
        func upcomingEvents(within days: Int) async throws -> [CalendarEventDTO] {
            if let thrown { throw thrown }
            return events
        }
    }

    func testTypeAndInterval() {
        XCTAssertEqual(CalendarDataProvider.type, "calendar")
        XCTAssertGreaterThanOrEqual(CalendarDataProvider(fetcher: FakeFetcher(events: [])).minimumInterval, 60)
    }

    func testMapsEventsToJSON() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let event = CalendarEventDTO(title: "Standup", start: start,
                                     end: start.addingTimeInterval(1800), allDay: false, location: "Zoom")
        let provider = CalendarDataProvider(fetcher: FakeFetcher(events: [event]))
        let result = try await provider.fetch(spec: SourceSpec(key: "cal", type: "calendar", config: nil),
                                              paramValues: [:])
        let dict = try XCTUnwrap(result as? [String: Any])
        let events = try XCTUnwrap(dict["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0]["title"] as? String, "Standup")
        XCTAssertEqual(events[0]["location"] as? String, "Zoom")
        XCTAssertNotNil(events[0]["start"] as? String) // ISO8601
        XCTAssertTrue(JSONSerialization.isValidJSONObject(dict))
    }

    func testPropagatesFetcherError() async {
        let provider = CalendarDataProvider(fetcher: FakeFetcher(events: [], thrown: DataProviderError.missingConfig("no access")))
        do {
            _ = try await provider.fetch(spec: SourceSpec(key: "cal", type: "calendar", config: nil), paramValues: [:])
            XCTFail("expected throw")
        } catch { /* expected — becomes a failedKey upstream */ }
    }
}
