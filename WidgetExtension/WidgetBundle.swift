import WidgetKit
import SwiftUI

@main
struct BetterWidgetsWidgets: WidgetBundle {
    var body: some Widget {
        StubWidget()
    }
}

struct StubWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "bw.stub", provider: StubProvider()) { _ in
            Text("Better Widgets")
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName("Better Widgets (stub)")
    }
}

struct StubProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry(date: .now)], policy: .never))
    }
}

struct SimpleEntry: TimelineEntry { let date: Date }
