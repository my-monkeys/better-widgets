import SwiftUI

/// macOS gives apps no API to place a widget on the desktop — the user must do it via
/// the system's "Edit Widgets" gallery. This sheet walks them through the three gestures.
struct AddToDesktopGuide: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.lg) {
            Text("Ajouter au bureau")
                .font(.system(size: DesignTokens.FontSize.titleXL, weight: .bold))
                .foregroundStyle(DesignTokens.textPrimary)
            Text("macOS ne permet pas de poser un widget à ta place. En trois gestes :")
                .foregroundStyle(DesignTokens.textSecondary)
            VStack(alignment: .leading, spacing: DesignTokens.Space.md) {
                step(1, "Clic droit sur le bureau → « Modifier les widgets ».")
                step(2, "Cherche « Better Widget » et fais-le glisser à la taille voulue.")
                step(3, "Clic droit sur le widget posé → « Modifier le widget » → choisis celui-ci.")
            }
            HStack {
                Spacer()
                Button("Fermer", action: onClose).buttonStyle(.borderedProminent).tint(DesignTokens.accent)
            }
        }
        .padding(DesignTokens.Space.xxl)
        .frame(width: 440)
        .background(DesignTokens.background)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Space.md) {
            Text("\(n)").font(.system(size: DesignTokens.FontSize.label, weight: .bold))
                .foregroundStyle(DesignTokens.accent)
            Text(text).foregroundStyle(DesignTokens.textPrimary)
        }
    }
}
