import XCTest

final class RSSFeedParserTests: XCTestCase {
    func testParsesRSS2() {
        let xml = """
        <?xml version="1.0"?><rss version="2.0"><channel>
        <title>My Feed</title>
        <item><title>First</title><link>https://ex.com/1</link>
          <description>Hello</description><pubDate>Mon, 01 Jul 2026 10:00:00 GMT</pubDate></item>
        <item><title>Second</title><link>https://ex.com/2</link></item>
        </channel></rss>
        """
        let result = RSSFeedParser.parse(Data(xml.utf8))
        XCTAssertEqual(result.title, "My Feed")
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items[0], RSSItem(title: "First", link: "https://ex.com/1",
                                                published: "Mon, 01 Jul 2026 10:00:00 GMT", summary: "Hello"))
        XCTAssertEqual(result.items[1].title, "Second")
        XCTAssertNil(result.items[1].summary)
    }

    func testParsesAtom() {
        let xml = """
        <?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom">
        <title>Atom Feed</title>
        <entry><title>Post</title><link href="https://ex.com/a"/>
          <summary>Sum</summary><updated>2026-07-01T10:00:00Z</updated></entry>
        </feed>
        """
        let result = RSSFeedParser.parse(Data(xml.utf8))
        XCTAssertEqual(result.title, "Atom Feed")
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].title, "Post")
        XCTAssertEqual(result.items[0].link, "https://ex.com/a")
        XCTAssertEqual(result.items[0].summary, "Sum")
        XCTAssertEqual(result.items[0].published, "2026-07-01T10:00:00Z")
    }

    func testEmptyOnGarbage() {
        let result = RSSFeedParser.parse(Data("not xml".utf8))
        XCTAssertTrue(result.items.isEmpty)
    }
}
