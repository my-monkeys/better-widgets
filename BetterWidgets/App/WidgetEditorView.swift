import SwiftUI

/// Param editor sheet for a widget instance: a form on the left (generated from the
/// template's manifest) and a preview placeholder on the right (replaced by a real
/// live preview in Task 7). Driven by `WidgetEditorModel`'s isolated working copy so
/// edits only commit to `AppState` on "Enregistrer".
struct WidgetEditorView: View {
    @StateObject private var model: WidgetEditorModel
    private let state: AppState
    private let onClose: () -> Void
    @State private var confirmCancel = false

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
                previewPlaceholder
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

    private var previewPlaceholder: some View {
        // Replaced by LivePreviewView in Task 7.
        RoundedRectangle(cornerRadius: DesignTokens.Radius.preview)
            .fill(DesignTokens.surface)
            .overlay(Text("Aperçu (bientôt)").foregroundStyle(DesignTokens.textSecondary))
            .frame(maxWidth: .infinity, minHeight: 360)
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.preview).stroke(DesignTokens.separator, lineWidth: 1))
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
        Binding(get: { model.paramValues[key] ?? "" }, set: { model.paramValues[key] = $0 })
    }

    private func secretBinding(_ req: (sourceKey: String, header: String)) -> Binding<String> {
        let composite = "\(req.sourceKey).\(req.header)"
        return Binding(get: { model.secretValues[composite] ?? "" }, set: { model.secretValues[composite] = $0 })
    }

    private func colorBinding(_ key: String) -> Binding<Color> {
        Binding(
            get: { Color(hex: model.paramValues[key] ?? "#000000") },
            set: { model.paramValues[key] = $0.toHex() })
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
