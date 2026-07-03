import Foundation

struct RSSItem: Equatable {
    let title: String
    let link: String
    let published: String?
    let summary: String?
}

/// Minimal RSS 2.0 + Atom parser over Foundation's XMLParser (no third-party dep).
enum RSSFeedParser {
    static func parse(_ data: Data) -> (title: String?, items: [RSSItem]) {
        let delegate = FeedDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return (delegate.feedTitle, delegate.items)
    }
}

private final class FeedDelegate: NSObject, XMLParserDelegate {
    private(set) var feedTitle: String?
    private(set) var items: [RSSItem] = []

    private var inItem = false
    private var seenFeedTitle = false
    private var text = ""
    private var curTitle = "", curLink = "", curSummary = "", curPublished = ""
    private var hasSummary = false, hasPublished = false

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes attrs: [String: String]) {
        text = ""
        if name == "item" || name == "entry" {
            inItem = true
            curTitle = ""; curLink = ""; curSummary = ""; curPublished = ""
            hasSummary = false; hasPublished = false
        } else if inItem, name == "link", let href = attrs["href"] {
            curLink = href // Atom link is an attribute
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "item" || name == "entry" {
            items.append(RSSItem(title: curTitle, link: curLink,
                                 published: hasPublished ? curPublished : nil,
                                 summary: hasSummary ? curSummary : nil))
            inItem = false
            return
        }
        if inItem {
            switch name {
            case "title": curTitle = value
            case "link" where !value.isEmpty: curLink = value // RSS link is text
            case "description", "summary", "content": curSummary = value; hasSummary = true
            case "pubDate", "updated", "published": curPublished = value; hasPublished = true
            default: break
            }
        } else if name == "title", !seenFeedTitle {
            feedTitle = value
            seenFeedTitle = true
        }
    }
}
