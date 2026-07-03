import SwiftUI
import WidgetKit

struct RenderEntry: TimelineEntry {
    let date: Date
    let instanceId: UUID?
}

struct WidgetRenderView: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: RenderEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        if let id = entry.instanceId, let image = loadImage(id: id) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            VStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.title2)
                Text("Configure-moi dans\nBetter Widgets")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func loadImage(id: UUID) -> NSImage? {
        let theme: Theme = colorScheme == .dark ? .dark : .light
        let url = SharedStore.appGroup().renderURL(instanceId: id, theme: theme)
        return NSImage(contentsOf: url)
    }
}
