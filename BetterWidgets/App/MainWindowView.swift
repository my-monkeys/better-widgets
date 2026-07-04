import SwiftUI

/// Main window: a sidebar routes between "Mes widgets" and "Galerie". Creating a widget
/// from the gallery switches the selection back to "Mes widgets" so the result is visible
/// immediately.
struct MainWindowView: View {
    @ObservedObject var state: AppState

    enum Section: Hashable { case myWidgets, gallery }
    @State private var selection: Section = .myWidgets

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Mes widgets", systemImage: "square.grid.2x2").tag(Section.myWidgets)
                Label("Galerie", systemImage: "sparkles").tag(Section.gallery)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .tint(DesignTokens.accent)
        } detail: {
            switch selection {
            case .myWidgets:
                MyWidgetsView(state: state, onBrowseGallery: { selection = .gallery })
            case .gallery:
                GalleryView(state: state) { _ in selection = .myWidgets }
            }
        }
        .navigationTitle("Better Widgets")
        .frame(minWidth: 720, minHeight: 480)
    }
}
