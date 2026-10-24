import KinetCurrency
import KinetDesign
import KinetEconomy
import PetFeature
import SwiftUI

enum GuideContent {
    static let steps: [GuideStep] = [
        GuideStep(page: AppPage.profile.rawValue, title: "Vítej v Kinetu", isWelcome: true),
        GuideStep(
            page: AppPage.profile.rawValue,
            title: "Minuty jsou měna",
            rows: [
                GuideRow("figure.walk", "Kroky = \(KinetEconomy.stepsPerMinute) kroků za minutu"),
                GuideRow("figure.run", "Workout = \(MinuteFormatter.short(KinetEconomy.workoutMultiplier)) za minutu"),
                GuideRow("book.fill", "Studium = 1 min za minutu"),
                GuideRow("gauge.with.needle", "Získat lze max \(MinuteFormatter.short(KinetEconomy.dailyIncomeCap)) za den"),
                GuideRow("arrow.turn.down.right", "Přenést do zítřka lze max \(MinuteFormatter.short(KinetEconomy.carryoverCap))")
            ],
            targets: ["donut"]
        ),
        GuideStep(
            page: AppPage.profile.rawValue,
            title: "Streak",
            rows: [
                GuideRow("flame.fill", "Splněný cíl kroků zvyšuje bonus"),
                GuideRow("arrow.down.circle", "Vynechaný den bonus sníží"),
                GuideRow("moon.zzz.fill", "Bonus lze \(KinetEconomy.restDaysPerWeek)× týdně ochránit")
            ],
            targets: ["streak"]
        ),
        GuideStep(
            page: AppPage.study.rawValue,
            title: "Studium",
            rows: [
                GuideRow("timer", "Otoč knoflík a klepni doprostřed"),
                GuideRow("repeat", "\(MinuteFormatter.short(KinetEconomy.pomodoroCycleMinutes)) intervaly = Pomodoro"),
                GuideRow("gauge.with.needle", "Získat lze max \(MinuteFormatter.short(KinetEconomy.studyDailyCap)) za den"),
                GuideRow("stop.circle", "Ukončením získáš poměrnou část"),
                GuideRow("wind", "Po učení následuje \(MinuteFormatter.words(KinetEconomy.breathMinutes)) dýchání")
            ],
            targets: ["studyHeader", "stage"]
        ),
        GuideStep(
            page: AppPage.pet.rawValue,
            title: "Tvoje medúza",
            rows: [
                GuideRow("hand.tap", "Klepni do vody a medúza připlave"),
                GuideRow("hand.tap.fill", "Dvojklik ji přivolá rychleji"),
                GuideRow("face.smiling", "Klepnutím na ni ji rozveselíš"),
                GuideRow("sparkles", "Klepnutím dekorace rozpohybuješ"),
            ],
            targets: ["aquarium"]
        ),
        GuideStep(
            page: AppPage.pet.rawValue,
            title: "Krmení",
            rows: [
                GuideRow("slider.horizontal.3", "Denní porci nastavíš až na \(MinuteFormatter.short(KinetEconomy.maxRation))"),
                GuideRow("moon.fill", "Nedokrmenou porci dostane večer"),
                GuideRow("arrow.up.heart.fill", "Víc minut = štěstí a vyšší úroveň"),
                GuideRow("paintbrush.pointed.fill", "Neváhej se podívat do obchodu")
            ],
            targets: ["mood", "feed", "customize"]
        )
    ]
}

struct GuideWelcome: View {
    @Environment(\.appTheme) private var theme
    let context: GuideWelcomeContext
    let prepare: () async -> Void
    @State private var isWorking = false

    var body: some View {
        ZStack {
            if context.showsMascot {
                JellyfishPreview(scale: 1.0, isPinned: true)
                    .frame(width: context.donut.width * 1.4, height: context.donut.height * 1.4)
                    .position(x: context.donut.midX, y: context.donut.midY)
                    .transition(.opacity)
            }
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    Text("Vítej v Kinetu")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text("Kde se pohyb a učení mění na minuty, kterými krmíš svou medúzu.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, 12)
                }
                Button {
                    guard !isWorking else { return }
                    isWorking = true
                    Task {
                        await prepare()
                        isWorking = false
                        context.advance()
                    }
                } label: {
                    Text("Začít")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: 260)
                        .frame(height: 52)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(theme.water.opacity(0.55)).interactive(), in: .capsule)
            }
            .frame(width: context.textArea.width, height: context.textArea.height)
            .position(x: context.textArea.midX, y: context.textArea.midY)
        }
    }
}
