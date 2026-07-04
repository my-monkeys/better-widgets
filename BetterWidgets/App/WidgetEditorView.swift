import SwiftUI

/// Param editor sheet for a widget instance: a form on the left (generated from the
/// template's manifest) and a live `LivePreviewView` on the right, with size/theme
/// toggles. Driven by `WidgetEditorModel`'s isolated working copy so edits only commit
/// to `AppState` on "Enregistrer".
struct WidgetEditorView: View {
    @StateObject private var model: WidgetEditorModel
    private let state: AppState
    private let onClose: () -> Void
    @State private var confirmCancel = false
    @State private var previewData: [String: Any] = [:]
    @State private var previewStale = false

    init(state: AppState, instance: WidgetInstance, onClose: @escaping () -> Void) {
        self.state = state
        self.onClose = onClose
        let manifest = (try? state.templates.manifest(id: instance.templateId))
            ?? TemplateManifest(id: instance.templateId, name: instance.name, version: "1",
                                sizes: [instance.size], refresh: 60, params: [], sources: [], links: nil)
        _model = StateObject(wrappedValue: WidgetEditorModel(instance: instance, manifest: manifest,
                                                             secrets: state.secrets))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: DesignTokens.Space.xl) {
                ParamFormView(model: model)
                    .frame(width: 320)
                previewPanel
            }
            .padding(DesignTokens.Space.xl)
            Divider()
            toolbar
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(DesignTokens.background)
        .confirmationDialog("Abandonner les modifications ?", isPresented: $confirmCancel) {
            Button("Abandonner", role: .destructive, action: onClose)
            Button("Continuer l'édition", role: .cancel) {}
        }
    }

    private var previewPanel: some View {
        VStack(spacing: DesignTokens.Space.md) {
            HStack(spacing: DesignTokens.Space.md) {
                Picker("", selection: $model.previewSize) {
                    ForEach(model.manifest.sizes, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).fixedSize()
                Toggle("Sombre", isOn: Binding(get: { model.previewTheme == .dark },
                                               set: { model.previewTheme = $0 ? .dark : .light }))
                Spacer()
                Button("Rafraîchir l'aperçu") { Task { await fetchPreviewData() } }
            }
            LivePreviewView(html: html, templateDir: templateDir,
                            context: model.previewContext(data: previewData, stale: previewStale))
                .frame(width: model.previewSize.pointSize.width, height: model.previewSize.pointSize.height)
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.preview).stroke(DesignTokens.separator, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .task { await fetchPreviewData() }
    }

    private var html: String { (try? state.templates.html(id: model.instance.templateId)) ?? "<html></html>" }
    private var templateDir: URL { state.templates.templateDirectory(id: model.instance.templateId) }

    /// Fetches preview data once (on open, and on demand via "Rafraîchir l'aperçu").
    /// Resolves working-copy secrets from an in-memory resolver (`model.previewResolver()`)
    /// so the preview is authenticated even for a not-yet-saved instance, without ever
    /// writing to the real Keychain — only "Enregistrer" (`persistSecrets`) does that.
    @MainActor private func fetchPreviewData() async {
        let granted = state.permissions.grantedTypes(instanceId: model.instance.id)
        let allowed = model.manifest.sources.filter { !$0.requiresConsent || granted.contains($0.type) }
        let resolver = model.previewResolver()
        let resolved = allowed.map { SourceSpec(key: $0.key, type: $0.type,
            config: resolver.resolvedConfig(for: $0, instanceId: model.instance.id)) }
        let result = await DataProviderRegistry.standard().fetchAll(sources: resolved, paramValues: model.mergedParams())
        var data = result.data
        for source in model.manifest.sources where source.requiresConsent && !granted.contains(source.type) {
            data[source.key] = ["__denied": true]
        }
        previewData = data
        previewStale = !result.failedKeys.isEmpty
    }

    private var toolbar: some View {
        HStack {
            Text(model.instance.name).font(.system(size: DesignTokens.FontSize.title, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)
            Spacer()
            Button("Annuler") { confirmCancel = true }
            Button("Enregistrer") {
                state.updateInstance(model.updatedInstance())
                model.persistSecrets(instanceId: model.instance.id)
                onClose()
            }
            .buttonStyle(.borderedProminent).tint(DesignTokens.accent)
        }
        .padding(DesignTokens.Space.lg)
    }
}

struct ParamFormView: View {
    @ObservedObject var model: WidgetEditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Space.lg) {
                ForEach(model.manifest.params, id: \.key) { spec in
                    paramRow(spec)
                }
                ForEach(model.secretRequirements, id: \.header) { req in
                    secretRow(req)
                }
            }
            .padding(DesignTokens.Space.lg)
        }
    }

    @ViewBuilder private func paramRow(_ spec: ParamSpec) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
            Text(spec.label).font(.system(size: DesignTokens.FontSize.label, weight: .medium))
                .foregroundStyle(DesignTokens.textPrimary)
            switch spec.type {
            case .color:
                ColorPicker("", selection: colorBinding(spec.key), supportsOpacity: false).labelsHidden()
            default:
                TextField("", text: paramBinding(spec.key)).textFieldStyle(.roundedBorder)
            }
        }
    }

    private func secretRow(_ req: (sourceKey: String, header: String)) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
            Text("Secret : \(req.header)").font(.system(size: DesignTokens.FontSize.label, weight: .medium))
                .foregroundStyle(DesignTokens.textPrimary)
            SecureField("", text: secretBinding(req)).textFieldStyle(.roundedBorder)
        }
    }

    private func paramBinding(_ key: String) -> Binding<String> {
        Binding(get: { model.paramValues[key] ?? defaultFor(key) ?? "" }, set: { model.paramValues[key] = $0 })
    }

    private func secretBinding(_ req: (sourceKey: String, header: String)) -> Binding<String> {
        let composite = "\(req.sourceKey).\(req.header)"
        return Binding(get: { model.secretValues[composite] ?? "" }, set: { model.secretValues[composite] = $0 })
    }

    private func colorBinding(_ key: String) -> Binding<Color> {
        Binding(
            get: { Color(hex: model.paramValues[key] ?? defaultFor(key) ?? "#000000") },
            set: { model.paramValues[key] = $0.toHex() })
    }

    private func defaultFor(_ key: String) -> String? {
        model.manifest.params.first { $0.key == key }?.default
    }
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b)
    }
    func toHex() -> String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int(ns.redComponent * 255), Int(ns.greenComponent * 255), Int(ns.blueComponent * 255))
    }
}
