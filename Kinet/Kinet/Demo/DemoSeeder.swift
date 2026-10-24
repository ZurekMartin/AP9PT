import ProfileFeature
import Foundation
import KinetCurrency
import KinetDesign
import KinetEconomy
import PetFeature
import StudyFeature
import SwiftData

enum DemoSeedData {
    static let steps = [6200, 4300, 7800, 5600, 3900, 8400, 6900, 5200, 7300, 4700, 9100, 6400, 5800, 7600]
    static let workouts: [Int: Int] = [0: 20, 2: 30, 3: 25, 5: 35, 6: 20, 7: 30, 8: 15, 9: 40, 10: 25, 12: 30, 13: 20]
    static let study: [Int: Int] = [0: 30, 1: 45, 3: 60, 4: 40, 5: 25, 6: 50, 8: 60, 9: 35, 10: 45, 11: 20, 12: 55, 13: 40]
    static var historyDays: Int { steps.count }
}

extension AppComposition {
    func seedDemo() async {
        guard !isSeeding else { return }
        isSeeding = true
        defer { isSeeding = false }
        setBusy(true)
        resetStoreForSeeding()
        guard let clock = demoClock else {
            setBusy(false)
            return
        }
        let hapticsWere = feedback.hapticsEnabled
        let soundsWere = feedback.soundsEnabled
        feedback.hapticsEnabled = false
        feedback.soundsEnabled = false
        pet.settings.demoXPOffset = 0
        let steps = DemoSeedData.steps
        let workouts = DemoSeedData.workouts
        let study = DemoSeedData.study

        await wallet.performBatch {
            for index in 0..<steps.count {
                clock.dayOffset = -14 + index
                await refreshForSeeding()
                profile.addDemoActivity(steps: steps[index], workoutMinutes: workouts[index] ?? 0)
                if let minutes = study[index] { recordSeedStudy(minutes: minutes) }
                await pet.refresh()
                try? pet.feed(minutes: 10 + (index % 3) * 5, announce: false)
                await Task.yield()
            }
        }
        clock.dayOffset = 0
        await refreshForSeeding()
        wallet.discardCarryover(before: wallet.today)
        let ownedDay = wallet.today.adding(days: -1, calendar: wallet.calendar)
        for item in KinetEconomy.demoPet.catalog where KinetEconomy.demoOwnedItemIDs.contains(item.id) {
            wallet.recordOwnership(itemID: item.id, ownerID: KinetEconomy.pet.ownerID, sourceID: item.category.rawValue, title: item.title, symbol: item.symbol, tint: "sand", day: ownedDay)
        }
        profile.addDemoActivity(steps: 9_000, workoutMinutes: 30)
        recordSeedStudy(minutes: 30)
        await pet.refresh()
        let bonus = wallet.config.bonus
        let missing = KinetEconomy.demoBalanceToday - wallet.balance
        if missing > 0 {
            wallet.recordGrant(missing, sourceID: bonus.id.rawValue, title: bonus.title, symbol: bonus.symbol, tint: bonus.tint, day: wallet.today)
        }
        pet.setDemoXP(KinetEconomy.demoXP)
        await pet.refresh()
        pet.consumeEvent()
        self.study.refreshToday()
        wallet.refresh()
        wallet.save()
        preferences.demoSeeded = true
        feedback.hapticsEnabled = hapticsWere
        feedback.soundsEnabled = soundsWere
        feedback.play(.dataReady)
        setBusy(false)
    }

    private func recordSeedStudy(minutes: Int) {
        let record = StudySessionRecord(id: UUID(), dayID: wallet.today.id, start: wallet.now, minutes: minutes, timeScale: 1)
        record.endedAt = wallet.now
        record.creditedMinutes = minutes
        container.mainContext.insert(record)
        wallet.setRawIncome(minutes, source: "study", day: wallet.today)
    }
}
