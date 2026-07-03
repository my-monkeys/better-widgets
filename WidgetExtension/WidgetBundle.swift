import WidgetKit
import SwiftUI
import AppIntents

@main
struct BetterWidgetsWidgets: WidgetBundle {
    var body: some Widget {
        BWSmallWidget()
        BWMediumWidget()
        BWLargeWidget()
    }
}

/// One provider per intent type (WidgetKit requires concrete intent types per kind).
struct RenderProvider<Intent: WidgetConfigurationIntent>: AppIntentTimelineProvider {
    let instanceId: (Intent) -> UUID?

    func placeholder(in context: Context) -> RenderEntry { RenderEntry(date: .now, instanceId: nil) }

    func snapshot(for configuration: Intent, in context: Context) async -> RenderEntry {
        RenderEntry(date: .now, instanceId: instanceId(configuration))
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<RenderEntry> {
        // Single entry, .never: the app drives reloads via WidgetCenter.
        Timeline(entries: [RenderEntry(date: .now, instanceId: instanceId(configuration))], policy: .never)
    }
}

private func uuid(_ entity: WidgetInstanceEntity?) -> UUID? {
    entity.flatMap { UUID(uuidString: $0.id) }
}

struct BWSmallWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetSize.small.kind, intent: SelectSmallWidgetIntent.self,
                               provider: RenderProvider { uuid($0.instance) }) { entry in
            WidgetRenderView(entry: entry)
        }
        .configurationDisplayName("Better Widget — Petit")
        .description("Un widget créé dans Better Widgets.")
        .supportedFamilies([.systemSmall])
    }
}

struct BWMediumWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetSize.medium.kind, intent: SelectMediumWidgetIntent.self,
                               provider: RenderProvider { uuid($0.instance) }) { entry in
            WidgetRenderView(entry: entry)
        }
        .configurationDisplayName("Better Widget — Moyen")
        .description("Un widget créé dans Better Widgets.")
        .supportedFamilies([.systemMedium])
    }
}

struct BWLargeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetSize.large.kind, intent: SelectLargeWidgetIntent.self,
                               provider: RenderProvider { uuid($0.instance) }) { entry in
            WidgetRenderView(entry: entry)
        }
        .configurationDisplayName("Better Widget — Grand")
        .description("Un widget créé dans Better Widgets.")
        .supportedFamilies([.systemLarge])
    }
}
