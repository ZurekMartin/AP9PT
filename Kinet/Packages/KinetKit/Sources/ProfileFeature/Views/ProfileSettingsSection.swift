import KinetCurrency
import KinetDesign
import SwiftUI

public struct ProfileSettingsSection: View {
    @Environment(ProfileModel.self) private var profile

    public init() {}

    public var body: some View {
        @Bindable var settings = profile.settings
        SettingsGroup("Kroky", hint: hint) {
            Stepper(value: $settings.stepGoal, in: profile.config.stepGoalRange, step: profile.config.stepGoalStep) {
                Text("Cíl kroků: \(MinuteFormatter.number(settings.stepGoal))")
                    .monospacedDigit()
            }
            switch profile.healthAccess {
            case .unavailable:
                EmptyView()
            case .notDetermined:
                Button {
                    Task { await profile.requestHealthAccess() }
                } label: {
                    Text("Povolit přístup ke Zdraví").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            case .requested:
                Label("Zdraví je propojené", systemImage: "heart.fill")
                    .font(.subheadline)
                    .foregroundStyle(Palette.sage)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var hint: String {
        switch profile.healthAccess {
        case .unavailable: "Zdraví není na tomto zařízení dostupné."
        case .notDetermined: "Kinet čte kroky a workouty a mění je na minuty."
        case .requested: "Cíl kroků určuje, kdy streak povyroste."
        }
    }
}
