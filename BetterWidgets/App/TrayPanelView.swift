import SwiftUI

/// The menu-bar dropdown, in `.window` style: a live preview of one chosen widget on top,
/// a picker to swap which widget is shown there, then the app actions. The chosen widget id
/// is persisted so the tray keeps showing the same one across launches.
struct TrayPanelView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var state: AppState
    var onOpenWindow: () -> Void

    @AppStorage("trayInstanceId") private var trayInstanceId: String = ""

    private static let panelWidth: CGFloat = 320
    private static let maxPreviewWidth: CGFloat = 300

    /// Persisted choice, falling back to the first instance if it was deleted or never set.
    private var selected: WidgetInstance? {
        state.instances.first { $0.id.uuidString == trayInstanceId } ?? state.instances.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.md) {
            if let selected {
                // Re-reads the render PNG every 2s so a background refresh surfaces here too.
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    preview(for: selected)
                }
                instancePicker(current: selected)
            } else {
                emptyState
            }

            Divider()
            actions
        }
        .padding(DesignTokens.Space.lg)
        .frame(width: Self.panelWidth)
    }

    @ViewBuilder private func preview(for instance: WidgetInstance) -> some View {
        let size = instance.size.pointSize
        let width = min(Self.maxPreviewWidth, size.width)
        let height = width * (size.height / size.width)
        let url = state.shared.renderURL(instanceId: instance.id, theme: colorScheme == .dark ? .dark : .light)
        ZStack {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                DesignTokens.background
                Text("rendu en cours…")
                    .font(.system(size: DesignTokens.FontSize.caption))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.preview))
        .frame(maxWidth: .infinity)
    }

    private func instancePicker(current: WidgetInstance) -> some View {
        HStack(spacing: DesignTokens.Space.sm) {
            Circle().fill(DesignTokens.statusColor(state.status(for: current.id)))
                .frame(width: DesignTokens.statusDotSize, height: DesignTokens.statusDotSize)
            Menu {
                ForEach(state.instances) { instance in
                    Button(instance.name) { trayInstanceId = instance.id.uuidString }
                }
            } label: {
                HStack(spacing: DesignTokens.Space.xs) {
                    Text(current.name).font(.system(size: DesignTokens.FontSize.label, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: DesignTokens.FontSize.caption))
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
            Text("Aucun widget").font(.system(size: DesignTokens.FontSize.label, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)
            Text("Crée ton premier widget dans la fenêtre.")
                .font(.system(size: DesignTokens.FontSize.caption))
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DesignTokens.Space.lg)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.sm) {
            Button(action: onOpenWindow) {
                Label("Réglages — ouvrir la fenêtre", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.accent)

            HStack {
                Button("Tout rafraîchir") { state.refreshAll() }
                Spacer()
                Button("Réseau local…") { SystemSettings.openLocalNetwork() }
            }
            .font(.system(size: DesignTokens.FontSize.caption))
            .buttonStyle(.link)
            .tint(DesignTokens.accent)

            Divider()
            Button("Quitter Better Widgets") { NSApp.terminate(nil) }
                .buttonStyle(.link)
                .font(.system(size: DesignTokens.FontSize.caption))
                .tint(DesignTokens.textSecondary)
        }
    }
}
