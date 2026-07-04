import SwiftUI
import AppKit

/// "Galerie" screen: lists bundled templates and lets the user spin up a new
/// `WidgetInstance` from one, at a chosen size, via `AppState.createInstance`.
struct GalleryView: View {
    @ObservedObject var state: AppState
    var onCreated: (WidgetInstance) -> Void = { _ in }
    @State private var editingTemplateId: IdentifiedString?
    @State private var pendingDelete: String?
    @State private var importError: String?
    /// Bumped after a successful import to force `templates` to re-evaluate:
    /// `TemplateStore.list()` reads the filesystem directly, so SwiftUI has no
    /// observable signal that a new directory appeared on disk.
    @State private var refreshTick = 0

    private var templates: [TemplateManifest] {
        _ = refreshTick
        return state.templates.list()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DesignTokens.Space.sm) {
                    Button("Nouveau template") {
                        let id = state.templates.createUserTemplate(name: "Nouveau widget")
                        editingTemplateId = IdentifiedString(id: id)
                    }
                    .buttonStyle(.borderedProminent).tint(DesignTokens.accent)

                    Button("Importer…") { importBWidget() }
                        .buttonStyle(.bordered).tint(DesignTokens.accent)
                }
                .padding([.top, .horizontal], DesignTokens.Space.xxl)

                if templates.isEmpty {
                    Text("Aucun template disponible.")
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .padding(.horizontal, DesignTokens.Space.xxl)
                } else {
                    VStack(alignment: .leading, spacing: DesignTokens.Space.lg) {
                        ForEach(templates, id: \.id) { manifest in
                            row(manifest)
                        }
                    }
                    .padding(DesignTokens.Space.xxl)
                }
            }
        }
        .background(DesignTokens.background)
        .sheet(item: $editingTemplateId) { identified in
            TemplateCodeEditorView(state: state, templateId: identified.id) { editingTemplateId = nil }
        }
        .confirmationDialog("Supprimer ce template ?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete) { id in
            Button("Supprimer", role: .destructive) { state.templates.deleteUserTemplate(id: id); pendingDelete = nil }
            Button("Annuler", role: .cancel) { pendingDelete = nil }
        } message: { _ in Text("Les widgets basés dessus afficheront un placeholder.") }
        .alert("Import", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: { Text(importError ?? "") }
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
            Menu {
                ForEach(manifest.sizes, id: \.self) { size in
                    Button("Créer — \(size.rawValue)") { onCreated(state.createInstance(templateId: manifest.id, size: size)) }
                }
                Divider()
                Button("Forker") {
                    if let id = try? state.templates.forkTemplate(from: manifest.id) {
                        editingTemplateId = IdentifiedString(id: id)
                    }
                }
                Button("Exporter…") { exportBWidget(manifest.id) }
                if state.templates.isUserTemplate(id: manifest.id) {
                    Button("Éditer le code") { editingTemplateId = IdentifiedString(id: manifest.id) }
                    Button("Supprimer", role: .destructive) { pendingDelete = manifest.id }
                }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize().tint(DesignTokens.accent)
        }
        .padding(DesignTokens.Space.lg)
        .background(DesignTokens.surface)
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.card).stroke(DesignTokens.separator, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
    }

    private func importBWidget() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []           // filter by extension below
        panel.allowsOtherFileTypes = true
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, url.pathExtension == "bwidget",
              let data = try? Data(contentsOf: url) else { return }
        do {
            _ = try BWidgetImporter.install(archive: data, into: state.templates)
            refreshTick += 1
        } catch {
            importError = "Import impossible : \(error)"
        }
    }

    private func exportBWidget(_ id: String) {
        guard let data = try? BWidgetArchive.export(templateDir: state.templates.templateDirectory(id: id)) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(id).bwidget"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(.system(size: DesignTokens.FontSize.caption))
            .padding(.horizontal, DesignTokens.Space.sm).padding(.vertical, DesignTokens.Space.xs)
            .foregroundStyle(DesignTokens.textSecondary)
            .overlay(Capsule().stroke(DesignTokens.separator, lineWidth: 1))
    }
}

/// `.sheet(item:)` needs `Identifiable`; a template id (`String`) doesn't carry that on its own.
struct IdentifiedString: Identifiable {
    let id: String
}
