import ProfileFeature
import KinetDesign
import PetFeature
import SwiftUI

struct SettingsSheet: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppComposition.self) private var app
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        ScrollView {
            VStack(spacing: SheetMetrics.spacing) {
                SheetHeader("Nastavení", subtitle: "Verze \(version)", symbol: "gearshape.fill", tint: theme.water)
                ProfileSettingsSection()
                PetSettingsSection()
                FeedbackSettingsSection()
                DemoControlsSection()
                Button {
                    app.preferences.permissionsAsked = false
                    app.preferences.guideCompleted = false
                    dismiss()
                } label: {
                    Text("Spustit průvodce").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(theme.water)
                .controlSize(.large)
            }
            .padding(.horizontal, SheetMetrics.horizontal)
            .padding(.top, SheetMetrics.top)
            .padding(.bottom, SheetMetrics.bottom)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .glassSheetBackground()
    }
}
