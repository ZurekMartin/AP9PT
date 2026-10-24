import Foundation
import KinetCurrency
import KinetDesign
import KinetEconomy
import PetFeature
import ProfileFeature
import StudyFeature
import SwiftUI

struct DemoValues: Equatable {
    var steps = 0
    var workout = 0
    var study = 0
    var bonus = 0
}

struct DemoControlsSection: View {
    @Environment(AppComposition.self) private var app
    @State private var settled = DemoValues()

    private var current: DemoValues {
        DemoValues(
            steps: app.demoValue(.steps),
            workout: app.demoValue(.workout),
            study: app.demoValue(.study),
            bonus: app.demoValue(.bonus)
        )
    }

    var body: some View {
        let values = settled
        SettingsGroup("Ukázkový režim", hint: "Ukázková data a \(DemoSeedData.historyDays) dní historie.") {
            Toggle("Ukázkový režim", isOn: Binding(
                get: { app.preferences.isDemoMode },
                set: { value in Task { await app.setDemoMode(value) } }
            ))
            if app.preferences.isDemoMode {
                metricStepper(number: values.steps, metric: .steps)
                metricStepper(number: values.workout, isMinutes: true, metric: .workout)
                metricStepper(number: values.study, isMinutes: true, metric: .study)
                    .disabled(app.study.isRunning)
                metricStepper(number: values.bonus, isMinutes: true, metric: .bonus)
                Button {
                    Task { await app.resetDemo() }
                } label: {
                    Text("Obnovit ukázková data").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
        }
        .animation(.smooth, value: app.preferences.isDemoMode)
        .onChange(of: current, initial: true) { _, new in
            if !app.isBusy { withAnimation(.smooth) { settled = new } }
        }
        .onChange(of: app.isBusy) { _, busy in
            if !busy { withAnimation(.smooth) { settled = current } }
        }
    }

    private func metricStepper(number: Int, isMinutes: Bool = false, metric: DemoMetric) -> some View {
        Stepper {
            Text("\(app.demoTitle(metric)): \(isMinutes ? MinuteFormatter.short(number) : MinuteFormatter.number(number))")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(number)))
        } onIncrement: {
            Task { await app.demoAdjust(metric, direction: 1) }
        } onDecrement: {
            Task { await app.demoAdjust(metric, direction: -1) }
        }
    }
}

enum DemoMetric {
    case steps, workout, study, bonus

    var step: Int {
        switch self {
        case .steps: 1000
        case .workout: 10
        case .study: 30
        case .bonus: 250
        }
    }

    var limit: Int {
        switch self {
        case .steps: KinetEconomy.demoMaxSteps
        case .workout: KinetEconomy.demoMaxWorkout
        case .study: KinetEconomy.demoMaxStudy
        case .bonus: KinetEconomy.demoMaxBonus
        }
    }
}

extension AppComposition {
    func demoTitle(_ metric: DemoMetric) -> String {
        let segment = switch metric {
        case .steps: KinetEconomy.stepsSegment
        case .workout: KinetEconomy.workoutSegment
        case .study: KinetEconomy.studySegment
        case .bonus: wallet.config.bonus.segment
        }
        return wallet.config.segmentTitle(for: segment)
    }

    func demoValue(_ metric: DemoMetric) -> Int {
        switch metric {
        case .steps: profile.todaySteps
        case .workout: profile.todayWorkoutMinutes
        case .study: study.todayStudied
        case .bonus: wallet.summary.incomeBySource[wallet.config.bonus.id] ?? 0
        }
    }

    func demoAdjust(_ metric: DemoMetric, direction: Int) async {
        guard preferences.isDemoMode, !isSeeding else { return }
        let value = demoValue(metric)
        let xp = pet.vitals.xp
        let bonus = wallet.config.bonus
        let manualBonus = wallet.grantAmount(sourceID: bonus.id.rawValue, day: wallet.today)
        let (reducible, apply): (Int, (Int) -> Void) = switch metric {
        case .steps: (value, { self.profile.addDemoActivity(steps: $0, workoutMinutes: 0) })
        case .workout: (value, { self.profile.addDemoActivity(steps: 0, workoutMinutes: $0) })
        case .study: (value, { try? self.study.adjustDemoStudy(by: $0) })
        case .bonus: (manualBonus, { self.wallet.recordGrant(manualBonus + $0, sourceID: bonus.id.rawValue, title: bonus.title, symbol: bonus.symbol, tint: bonus.tint, day: self.wallet.today) })
        }
        let delta = direction > 0 ? min(metric.step, max(0, metric.limit - value)) : -min(metric.step, reducible)
        guard delta != 0 else { return }
        apply(delta)
        await pet.refresh()
        pet.setDemoXP(xp)
        wallet.refresh()
    }
}
