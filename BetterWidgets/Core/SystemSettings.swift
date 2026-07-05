import AppKit

/// Deep-links into the macOS System Settings panes Better Widgets needs to send the user to.
enum SystemSettings {
    /// Privacy → Local Network. macOS 15+ gates outbound connections to private/CGNAT hosts
    /// (Home Assistant, self-hosted dashboards, Tailscale) behind this per-app toggle, so a
    /// widget whose data source lives on the LAN renders "aucune data" until the user enables
    /// Better Widgets here. There is no API to grant it — only to open the pane.
    static func openLocalNetwork() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") else { return }
        NSWorkspace.shared.open(url)
    }
}
