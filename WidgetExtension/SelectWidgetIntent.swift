import AppIntents
import WidgetKit

struct SelectSmallWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choisir le widget"
    static let description = IntentDescription("Quel widget Better Widgets afficher.")

    @Parameter(title: "Widget", query: WidgetInstanceQuery(family: .small))
    var instance: WidgetInstanceEntity?
}

struct SelectMediumWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choisir le widget"
    static let description = IntentDescription("Quel widget Better Widgets afficher.")

    @Parameter(title: "Widget", query: WidgetInstanceQuery(family: .medium))
    var instance: WidgetInstanceEntity?
}

struct SelectLargeWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choisir le widget"
    static let description = IntentDescription("Quel widget Better Widgets afficher.")

    @Parameter(title: "Widget", query: WidgetInstanceQuery(family: .large))
    var instance: WidgetInstanceEntity?
}
