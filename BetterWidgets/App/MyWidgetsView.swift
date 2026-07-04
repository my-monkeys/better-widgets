import SwiftUI

/// "Mes widgets" screen: a grid of the user's widget instances, with duplicate/delete/
/// add-to-desktop actions surfaced via `WidgetCard`'s per-card menu.
struct MyWidgetsView: View {
    @ObservedObject var state: AppState
    @State private var pendingDelete: WidgetInstance?
    @State private var guideShown = false

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: DesignTokens.Space.xl)]

    var body: some View {
        Group {
            if state.instances.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: DesignTokens.Space.xl) {
                        ForEach(state.instances) { instance in
                            WidgetCard(
                                model: WidgetCardModel(instance: instance,
                                                       status: state.status(for: instance.id),
                                                       rendersDir: state.shared.renderURL),
                                onDuplicate: { _ = state.duplicateInstance(instance.id) },
                                onDelete: { pendingDelete = instance },
                                onAddToDesktop: { guideShown = true })
                        }
                    }
                    .padding(DesignTokens.Space.xxl)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(DesignTokens.Space.section)
        .background(DesignTokens.background)
    }
}
