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
    @StateObject private var state = AppState.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Better Widgets", id: "main") {
            MainWindowView(state: state)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra("Better Widgets", systemImage: "square.grid.2x2") {
            TrayPanelView(state: state) {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        AppDelegate.onLaunch = { Task { @MainActor in AppState.shared.bootstrap() } }
    }
}
