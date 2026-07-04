import SwiftUI

/// Advanced "code mode" editor for a template: `CodeEditorView` (index.html / manifest.json tabs)
/// on the left, `LivePreviewView` fed by a real data fetch on the right. Save validates the
/// manifest first — an invalid manifest shows an error banner and leaves the sheet open.
struct TemplateCodeEditorView: View {
    @StateObject private var model: TemplateEditorModel
    private let state: AppState
    private let onClose: () -> Void
    @State private var validationError: String?
    @State private var previewData: [String: Any] = [:]
    @State private var previewStale = false

    init(state: AppState, templateId: String, onClose: @escaping () -> Void) {
        self.state = state
        self.onClose = onClose
        _model = StateObject(wrappedValue: TemplateEditorModel(templateId: templateId, store: state.templates))
    }

    private var assetsDir: URL {
        Bundle.main.resourceURL!.appendingPathComponent("codemirror")
    }
    private var templateDir: URL { state.templates.templateDirectory(id: model.templateId) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignTokens.Space.xl) {
                CodeEditorView(model: model, assetsDir: assetsDir).frame(minWidth: 380)
                previewPanel
            }
            .padding(DesignTokens.Space.xl)
            if let validationError {
                Text(validationError).font(.system(size: DesignTokens.FontSize.caption))
                    .foregroundStyle(DesignTokens.statusError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DesignTokens.Space.xl)
            }
            Divider()
            toolbar
        }
        .frame(minWidth: 900, minHeight: 560)
        .background(DesignTokens.background)
    }

    private var previewPanel: some View {
        VStack {
            LivePreviewView(html: model.htmlText, templateDir: templateDir,
                            context: model.previewContext(data: previewData, stale: previewStale))
                .frame(width: (model.previewManifest()?.sizes.first ?? .small).pointSize.width,
                       height: (model.previewManifest()?.sizes.first ?? .small).pointSize.height)
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.preview).stroke(DesignTokens.separator, lineWidth: 1))
            if case .failure = model.validate() {
                Text("manifest invalide — aperçu figé").font(.system(size: DesignTokens.FontSize.caption))
                    .foregroundStyle(DesignTokens.statusStale)
            }
        }
        .frame(maxWidth: .infinity)
        .task { await fetchPreviewData() }
    }

    private var toolbar: some View {
        HStack {
            Text(model.templateId).font(.system(size: DesignTokens.FontSize.label)).foregroundStyle(DesignTokens.textSecondary)
            Spacer()
            Button("Fermer", action: onClose)
            Button("Enregistrer") {
                switch model.validate() {
                case .success:
                    do {
                        try model.save(into: state.templates)
                        validationError = nil
                        Task { await fetchPreviewData() }
                    } catch {
                        validationError = model.errorMessage(error)
                    }
                case .failure(let e):
                    validationError = model.errorMessage(e)
                }
            }
            .buttonStyle(.borderedProminent).tint(DesignTokens.accent)
        }
        .padding(DesignTokens.Space.lg)
    }

    @MainActor private func fetchPreviewData() async {
        guard let manifest = model.previewManifest() else { return }
        // No instance/grants here: fetch free sources, mark consent-required as __denied.
        let allowed = manifest.sources.filter { !$0.requiresConsent }
        let denied = manifest.sources.filter { $0.requiresConsent }
        let result = await DataProviderRegistry.standard().fetchAll(sources: allowed, paramValues: [:])
        var data = result.data
        for s in denied { data[s.key] = ["__denied": true] }
        previewData = data
        previewStale = !result.failedKeys.isEmpty
    }
}
