import KinetCurrency
import KinetDesign
import SwiftUI

public struct StreakBarButton: View {
    @Environment(\.appTheme) private var theme
    @Environment(ProfileModel.self) private var profile
    private let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        GlassCircleButton("Streak \(profile.streakLevel)", action: action) {
            VStack(spacing: -1) {
                Image(systemName: profile.isRestDayToday ? "moon.zzz.fill" : "flame.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
                Text("\(profile.streakLevel)")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
            }
        }
    }

    private var tint: Color {
        if profile.isRestDayToday { return theme.water }
        return profile.streakLevel > 0 ? theme.accent : Palette.mist
    }
}

public struct StreakSheet: View {
    @Environment(\.appTheme) private var theme
    @Environment(ProfileModel.self) private var profile
    @Environment(Wallet.self) private var wallet
    @State private var message: String?

    public init() {}

    public var body: some View {
        let maxLevel = profile.config.streakMaxLevel
        let bonusToday = wallet.summary.incomeBySource[profile.config.streakBonusSource] ?? 0
        VStack(spacing: SheetMetrics.spacing) {
            SheetHeader(
                "Streak \(profile.streakLevel)",
                subtitle: bonusToday > 0 ? "Dnes bonus +\(MinuteFormatter.words(bonusToday))" : "Dnes zatím bez bonusu",
                symbol: profile.isRestDayToday ? "moon.zzz.fill" : "flame.fill",
                tint: profile.isRestDayToday ? theme.water : theme.accent
            )
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Stupeň \(profile.streakLevel) z \(maxLevel)")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text("+\(profile.streakBonusPercent) % k minutám")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.accent)
                }
                StreakTrack(level: profile.streakLevel, maxLevel: maxLevel, tint: theme.accent)
                SheetHint("Splníš-li cíl \(MinuteFormatter.number(profile.settings.stepGoal)) kroků, streak o stupeň povyroste. Vynechaný den ji jen mírně sníží, nic se neděje.")
                    .padding(.top, 4)
            }
            SheetDivider()
            restDay
        }
        .animation(.smooth, value: message)
        .animation(.smooth, value: profile.isRestDayToday)
    }

    private var restDay: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Odpočinkový den")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(MinuteFormatter.short(profile.config.restDayPrice))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.inkSecondary)
            }
            if profile.isRestDayToday {
                Label("Dnes odpočíváš", systemImage: "moon.zzz.fill")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(theme.water)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(theme.water.opacity(0.14), in: .capsule)
                    .transition(.opacity)
            } else {
                Button(action: buy) {
                    Text(profile.restDaysLeftThisWeek > 0 ? "Dát si odpočinek" : "Tento týden už využito")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(theme.water)
                .controlSize(.large)
                .disabled(profile.restDaysLeftThisWeek == 0)
                .transition(.opacity)
            }
            SheetHint(restHint)
            if let message {
                SheetHint(message, isAlert: true)
                    .transition(.opacity)
            }
        }
    }

    private var weeklyLimitText: String {
        let count = profile.config.restDaysPerWeek
        return count == 1 ? "jednou týdně" : "\(count)× týdně"
    }

    private var restHint: String {
        if profile.isRestDayToday { return "Streak zůstává v klidu, ať dopadnou kroky jakkoli." }
        if profile.restDaysLeftThisWeek > 0 { return "Ochrání streak, když dnes cíl nesplníš. Jde využít \(weeklyLimitText)." }
        return "Další odpočinek půjde využít od pondělí."
    }

    private func buy() {
        do {
            try profile.buyRestDay()
            message = nil
        } catch {
            switch error {
            case .alreadyActive: message = "Dnes už odpočíváš."
            case .weeklyLimit: message = "Odpočinkový den jde využít \(weeklyLimitText)."
            case .spend(.reserved): message = "Medúza si drží porci. Po nakrmení bude volných minut víc."
            case .spend(.insufficientFunds(let missing)): message = "Chybí ti ještě \(MinuteFormatter.words(missing)). Krátká procházka pomůže."
            case .spend(.invalidAmount): message = "Něco se nepovedlo."
            }
        }
    }
}

private struct StreakTrack: View {
    let level: Int
    let maxLevel: Int
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let knob: CGFloat = 20
            let dot: CGFloat = 7
            let trackHeight: CGFloat = 10
            let usable = proxy.size.width - knob
            let positionX: (Int) -> CGFloat = { knob / 2 + usable * CGFloat($0) / CGFloat(max(1, maxLevel)) }
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(tint.opacity(0.18))
                    .frame(height: trackHeight)
                    .offset(y: (knob - trackHeight) / 2)
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: positionX(level), height: trackHeight)
                    .offset(y: (knob - trackHeight) / 2)
                ForEach(0...maxLevel, id: \.self) { index in
                    Circle()
                        .fill(index <= level ? tint : Palette.mist.opacity(0.35))
                        .frame(width: dot, height: dot)
                        .position(x: positionX(index), y: knob + 14)
                }
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .overlay { Circle().strokeBorder(tint, lineWidth: 2) }
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .frame(width: knob, height: knob)
                    .position(x: positionX(level), y: knob / 2)
            }
            .animation(.smooth(duration: 0.6), value: level)
        }
        .frame(height: 20 + 22)
    }
}
