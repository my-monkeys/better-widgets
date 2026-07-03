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

    var body: some Scene {
        MenuBarExtra("Better Widgets", systemImage: "square.grid.2x2") {
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
