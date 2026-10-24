import KinetCurrency
import KinetDesign
import SwiftUI

struct TodayCard: View {
    @Environment(\.appTheme) private var theme
    @Environment(Wallet.self) private var wallet
    @Environment(ProfileModel.self) private var profile

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Eyebrow("Dnes")
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(MinuteFormatter.number(profile.todaySteps))
                            .font(KinetFont.metric)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("/ \(MinuteFormatter.number(profile.settings.stepGoal)) kroků")
                            .font(.subheadline)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    ProgressTrack(value: Double(profile.todaySteps) / Double(max(1, profile.settings.stepGoal)), tint: Palette.sage)
                }
                .padding(.top, -4)
                HStack {
                    Text("+\(MinuteFormatter.short(wallet.summary.income))")
                        .foregroundStyle(Palette.sage)
                    Text("·").foregroundStyle(Palette.inkSecondary)
                    Text("utraceno \(MinuteFormatter.short(wallet.summary.spent))")
                        .foregroundStyle(Palette.inkSecondary)
                }
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .monospacedDigit()
                if profile.isRestDayToday {
                    Label("Dnes odpočíváš", systemImage: "moon.zzz.fill")
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(theme.water)
                        .frame(maxWidth: .infinity)
                }
            }
            .animation(.smooth, value: profile.todaySteps)
        }
        .guideTarget("today")
    }
}

struct ProgressTrack: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.18))
                Capsule().fill(tint.gradient)
                    .frame(width: max(10, proxy.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 10)
        .animation(.smooth(duration: 0.8), value: value)
    }
}
