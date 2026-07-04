import SwiftUI

/// "Mes widgets" screen: a grid of the user's widget instances, with duplicate/delete/
/// add-to-desktop actions surfaced via `WidgetCard`'s per-card menu.
struct MyWidgetsView: View {
    @ObservedObject var state: AppState
    var onBrowseGallery: () -> Void = {}
    @State private var pendingDelete: WidgetInstance?
    @State private var guideShown = false
    @State private var editing: WidgetInstance?
    @State private var permissionInstance: WidgetInstance?

    // Must be >= the widest card's frame width (medium/large cards are 340pt wide + Space.lg
    // padding on each side), or a card clips/overflows its adaptive column in a narrow window.
    private let columns = [GridItem(.adaptive(minimum: 340 + DesignTokens.Space.lg * 2),
                                    spacing: DesignTokens.Space.xl)]

    var body: some View {
        Group {
            if state.instances.isEmpty {
                emptyState
            } else {
                // Neither the render PNGs nor `InstanceState` (status) are `@Published` — they're
                // written by a background worker after `instances` is mutated. This periodic
                // re-evaluation is what makes a completed background render (or a status
                // transition) show up in an already-open window, within ~2s, without adding a
                // second observable data model.
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: DesignTokens.Space.xl) {
                            ForEach(state.instances) { instance in
                                WidgetCard(
                                    model: WidgetCardModel(instance: instance,
                                                           status: state.status(for: instance.id),
                                                           rendersDir: state.shared.renderURL),
                                    onEdit: { editing = instance },
                                    onDuplicate: { _ = state.duplicateInstance(instance.id) },
                                    onDelete: { pendingDelete = instance },
                                    onAddToDesktop: { guideShown = true },
                                    onPermissions: templateRequiresConsent(instance) ? { permissionInstance = instance } : nil)
                            }
                        }
                        .padding(DesignTokens.Space.xxl)
                    }
                }
            }
        }
        .background(DesignTokens.background)
        .confirmationDialog("Supprimer ce widget ?", isPresented: isPendingDeletePresented,
                            presenting: pendingDelete) { instance in
            Button("Supprimer « \(instance.name) »", role: .destructive) {
                state.deleteInstance(instance.id); pendingDelete = nil
            }
            Button("Annuler", role: .cancel) { pendingDelete = nil }
        }
        .sheet(isPresented: $guideShown) { AddToDesktopGuide { guideShown = false } }
        .sheet(item: $editing) { instance in
            WidgetEditorView(state: state, instance: instance) { editing = nil }
        }
        .sheet(item: $permissionInstance) { instance in
            if let manifest = try? state.templates.manifest(id: instance.templateId) {
                PermissionConsentView(
                    model: PermissionConsentModel(instanceId: instance.id, manifest: manifest,
                                                  permissions: state.permissions)) {
                    permissionInstance = nil
                }
            }
        }
    }

    private func templateRequiresConsent(_ instance: WidgetInstance) -> Bool {
        (try? state.templates.manifest(id: instance.templateId))?.sources.contains { $0.requiresConsent } ?? false
    }

    /// `confirmationDialog` needs a writable binding: a dismissal from outside the two
    /// buttons above (Escape, click-away) must also clear `pendingDelete`, or the dialog
    /// would think it's still owed a presentation and pop back up.
    private var isPendingDeletePresented: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { presented in if !presented { pendingDelete = nil } })
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.md) {
            Text("Aucun widget").font(.system(size: DesignTokens.FontSize.titleXL, weight: .bold))
                .foregroundStyle(DesignTokens.textPrimary)
            Text("Crée ton premier widget depuis la Galerie.")
                .foregroundStyle(DesignTokens.textSecondary)
            Button("Parcourir la galerie", action: onBrowseGallery)
                .tint(DesignTokens.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(DesignTokens.Space.section)
        .background(DesignTokens.background)
    }
}
