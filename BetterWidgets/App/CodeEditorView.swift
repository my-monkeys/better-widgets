import SwiftUI

/// Tab strip (`index.html` / `manifest.json`) over the CodeMirror bridge — the left panel of
/// `TemplateCodeEditorView`. The active `Binding<String>` and `CodeEditorBridge.Language` both
/// follow `model.tab`.
struct CodeEditorView: View {
    @ObservedObject var model: TemplateEditorModel
    let assetsDir: URL

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.tab) {
                Text("index.html").tag(TemplateEditorModel.Tab.html)
                Text("manifest.json").tag(TemplateEditorModel.Tab.manifest)
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(DesignTokens.Space.sm)
            CodeEditorBridge(text: activeBinding,
                             language: model.tab == .manifest ? .json : .html,
                             assetsDir: assetsDir)
        }
        .background(DesignTokens.surface)
    }

    private var activeBinding: Binding<String> {
        model.tab == .manifest
            ? Binding(get: { model.manifestText }, set: { model.manifestText = $0 })
            : Binding(get: { model.htmlText }, set: { model.htmlText = $0 })
    }
}
