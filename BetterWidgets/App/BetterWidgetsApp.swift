import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var onLaunch: (() -> Void)?
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.onLaunch?()
    }
}

@main
struct BetterWidgetsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Better Widgets", id: "main") {
            MainWindowView(state: state)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra("Better Widgets", systemImage: "square.grid.2x2") {
            Button("Ouvrir Better Widgets") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            Divider()
            ForEach(state.instances) { instance in
                Text(state.statusLine(for: instance))
            }
            Divider()
            Button("Tout rafraîchir") { state.refreshAll() }
            Button("Quitter") { NSApp.terminate(nil) }
        }
    }

    init() {
        let state = _state
        AppDelegate.onLaunch = { Task { @MainActor in state.wrappedValue.bootstrap() } }
    }
}
