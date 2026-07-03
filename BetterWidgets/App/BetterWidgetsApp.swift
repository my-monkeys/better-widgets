import SwiftUI

@main
struct BetterWidgetsApp: App {
    var body: some Scene {
        MenuBarExtra("Better Widgets", systemImage: "square.grid.2x2") {
            Text("Better Widgets")
            Divider()
            Button("Quitter") { NSApp.terminate(nil) }
        }
    }
}
