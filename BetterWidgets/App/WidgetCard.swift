import SwiftUI

struct WidgetCardModel {
    let instance: WidgetInstance
    let status: InstanceStatus
    let rendersDir: (UUID, Theme) -> URL

    func imageURL(dark: Bool) -> URL { rendersDir(instance.id, dark ? .dark : .light) }

    var statusLabel: String {
        switch status {
        case .ok: return "À jour"
        case .stale: return "Données périmées"
        case .error: return "Erreur"
        }
    }

    var cardWidth: CGFloat { instance.size == .small ? 170 : 340 }
}

struct WidgetCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let model: WidgetCardModel
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onAddToDesktop: () -> Void

    private var image: NSImage? {
        NSImage(contentsOf: model.imageURL(dark: colorScheme == .dark))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.sm) {
            preview
            HStack(spacing: DesignTokens.Space.sm) {
                Circle().fill(DesignTokens.statusColor(model.status)).frame(width: 7, height: 7)
                Text(model.instance.name).font(.system(size: DesignTokens.FontSize.title, weight: .semibold))
                Spacer()
                actions
            }
            Text(model.statusLabel)
                .font(.system(size: DesignTokens.FontSize.caption))
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(DesignTokens.Space.lg)
        .frame(width: model.cardWidth + DesignTokens.Space.lg * 2, alignment: .leading)
        .background(DesignTokens.surface)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DesignTokens.separator, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var preview: some View {
        let ratio: CGFloat = model.instance.size == .large ? 382.0 / 364.0 : (model.instance.size == .medium ? 170.0 / 364.0 : 1)
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                DesignTokens.background
                Text("rendu en cours…")
                    .font(.system(size: DesignTokens.FontSize.caption))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
        .frame(width: model.cardWidth, height: model.cardWidth * ratio)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var actions: some View {
        Menu {
            Button("Éditer") {}.disabled(true)  // 3b
            Button("Dupliquer", action: onDuplicate)
            Button("Ajouter au bureau…", action: onAddToDesktop)
            Divider()
            Button("Supprimer", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis.circle").foregroundStyle(DesignTokens.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
