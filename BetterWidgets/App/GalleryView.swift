import SwiftUI

/// "Galerie" screen: lists bundled templates and lets the user spin up a new
/// `WidgetInstance` from one, at a chosen size, via `AppState.createInstance`.
struct GalleryView: View {
    @ObservedObject var state: AppState
    var onCreated: (WidgetInstance) -> Void = { _ in }

    private var templates: [TemplateManifest] { state.templates.list() }

    var body: some View {
        ScrollView {
            if templates.isEmpty {
                Text("Aucun template disponible.")
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                VStack(alignment: .leading, spacing: DesignTokens.Space.lg) {
                    ForEach(templates, id: \.id) { manifest in
                        row(manifest)
                    }
                }
                .padding(DesignTokens.Space.xxl)
            }
        }
        .background(DesignTokens.background)
    }

    private func row(_ manifest: TemplateManifest) -> some View {
        HStack(alignment: .center, spacing: DesignTokens.Space.lg) {
            VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
                Text(manifest.name).font(.system(size: DesignTokens.FontSize.title, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                HStack(spacing: DesignTokens.Space.sm) {
                    ForEach(manifest.sizes, id: \.self) { badge($0.rawValue) }
                    ForEach(manifest.sources, id: \.key) { badge($0.type) }
                }
            }
            Spacer()
            Menu("Créer") {
                ForEach(manifest.sizes, id: \.self) { size in
                    Button(size.rawValue) { onCreated(state.createInstance(templateId: manifest.id, size: size)) }
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
            .tint(DesignTokens.accent)
        }
        .padding(DesignTokens.Space.lg)
        .background(DesignTokens.surface)
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.card).stroke(DesignTokens.separator, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(.system(size: DesignTokens.FontSize.caption))
            .padding(.horizontal, DesignTokens.Space.sm).padding(.vertical, DesignTokens.Space.xs)
            .foregroundStyle(DesignTokens.textSecondary)
            .overlay(Capsule().stroke(DesignTokens.separator, lineWidth: 1))
    }
}
