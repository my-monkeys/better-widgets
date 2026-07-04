import SwiftUI

struct PermissionConsentView: View {
    @ObservedObject var model: PermissionConsentModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.lg) {
            Text("Permissions du widget")
                .font(.system(size: DesignTokens.FontSize.titleXL, weight: .bold))
                .foregroundStyle(DesignTokens.textPrimary)
            Text("Ce widget peut accéder à ces données. Tu peux l'autoriser ou non ; macOS te demandera aussi confirmation au premier accès.")
                .font(.system(size: DesignTokens.FontSize.label))
                .foregroundStyle(DesignTokens.textSecondary)
            ForEach(model.requiredTypes, id: \.self) { type in
                Toggle(PermissionConsentModel.label(for: type), isOn: Binding(
                    get: { model.isGranted(type) },
                    set: { model.setGranted(type, $0) }))
                .tint(DesignTokens.accent)
            }
            HStack {
                Spacer()
                Button("Terminé", action: onClose).buttonStyle(.borderedProminent).tint(DesignTokens.accent)
            }
        }
        .padding(DesignTokens.Space.xxl)
        .frame(width: 420)
        .background(DesignTokens.background)
    }
}
