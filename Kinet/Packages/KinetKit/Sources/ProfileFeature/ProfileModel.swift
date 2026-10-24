import Foundation
import KinetCurrency
import KinetDesign
import Observation
import SwiftData

@MainActor
@Observable
public final class ProfileModel: DayCloseParticipant {
    public private(set) var todaySteps: Int = 0
    public private(set) var todayWorkoutMinutes: Int = 0
    public private(set) var streakLevel: Int = 0
    public private(set) var streakBonusPercent: Int = 0
    public private(set) var isRestDayToday: Bool = false
    public private(set) var restDaysLeftThisWeek: Int = 1
    public private(set) var healthAccess: HealthAccess = .notDetermined
    public let settings: ProfileSettings
    public let config: ProfileConfig
    public let closeOrder: Int = 10

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let wallet: Wallet
    @ObservationIgnored private let source: any ActivitySource
    @ObservationIgnored private let feedback: Feedback
    @ObservationIgnored private let activities: DayRecordStore<ActivityRecord>
    @ObservationIgnored private let streaks: DayRecordStore<StreakDay>

    public init(context: ModelContext, wallet: Wallet, source: any ActivitySource, settings: ProfileSettings, feedback: Feedback, config: ProfileConfig) {
        self.context = context
        self.wallet = wallet
        self.source = source
        self.settings = settings
        self.feedback = feedback
        self.config = config
        activities = DayRecordStore(
            context: context,
            dayID: \.dayID,
            fetchOne: { id in FetchDescriptor(predicate: #Predicate { $0.dayID == id }) },
            fetchMany: { ids in FetchDescriptor(predicate: #Predicate { ids.contains($0.dayID) }) }
        )
        streaks = DayRecordStore(
            context: context,
            dayID: \.dayID,
            fetchOne: { id in FetchDescriptor(predicate: #Predicate { $0.dayID == id }) },
            fetchMany: { ids in FetchDescriptor(predicate: #Predicate { ids.contains($0.dayID) }) }
        )
    }

    public func refresh() async {
        let access = await source.access()
        assign(\.healthAccess, access)
        let days = openDays()
        await syncHealth(days: days)
        wallet.batch {
            for day in days { reportIncome(for: day) }
        }
        if healthAccess == .requested, !source.isDemo, !settings.hasBackfilled { settings.hasBackfilled = true }
        updatePublished()
        save()
    }

    public func requestHealthAccess() async {
        try? await source.requestAuthorization()
        await refresh()
    }

    public func buyRestDay() throws(RestDayError) {
        let today = wallet.today
        let day = streakDay(for: today)
        guard !day.isRestDay else { throw .alreadyActive }
        guard restDaysUsedThisWeek() < config.restDaysPerWeek else { throw .weeklyLimit }
        do {
            try wallet.spend(SpendRequest(
                ownerID: config.ownerID,
                sourceID: "restDay",
                amount: config.restDayPrice,
                title: "Odpočinkový den",
                symbol: "bed.double.fill",
                tint: "sand"
            ))
        } catch {
            throw .spend(error)
        }
        day.isRestDay = true
        save()
        updatePublished()
    }

    public func addDemoActivity(steps: Int, workoutMinutes: Int) {
        let today = wallet.today
        let record = activityRecord(for: today)
        record.demoSteps = max(0, record.demoSteps + steps)
        record.demoWorkoutMinutes = max(0, record.demoWorkoutMinutes + workoutMinutes)
        record.updatedAt = wallet.now
        reportIncome(for: today)
        save()
        updatePublished()
    }

    public func prepare(days: [DayKey]) async {
        await syncHealth(days: days)
    }

    public func close(day: DayKey, in wallet: Wallet) {
        let streak = streakDay(for: day)
        let record = activityRecord(for: day)
        let steps = totalSteps(record)
        let raw = ProfileIncome.raw(steps: steps, workoutMinutes: totalWorkout(record), streakLevel: streak.levelAtStart, config: config)
        wallet.setRawIncome(raw.steps, source: config.stepsSource, day: day)
        wallet.setRawIncome(raw.workout, source: config.workoutSource, day: day)
        wallet.setBonusPercent(raw.bonusPercent, day: day)
        let outcome = StreakEngine.outcome(steps: steps, goal: settings.stepGoal, isRestDay: streak.isRestDay)
        if streak.outcomeRaw != outcome.rawValue { streak.outcomeRaw = outcome.rawValue }
        let next = StreakEngine.nextLevel(from: streak.levelAtStart, outcome: outcome, config: config)
        let nextDay = streakDay(for: day.adding(days: 1, calendar: wallet.calendar), defaultLevel: next)
        if nextDay.levelAtStart != next { nextDay.levelAtStart = next }
    }

    private func openDays() -> [DayKey] {
        let today = wallet.today
        var days = [today]
        let lookback = settings.hasBackfilled ? config.healthLookbackDays : config.healthBackfillDays
        for offset in 1...max(1, lookback) {
            let day = today.adding(days: -offset, calendar: wallet.calendar)
            if !wallet.isClosed(day) { days.append(day) }
        }
        return days
    }

    private func syncHealth(days: [DayKey]) async {
        guard !source.isDemo, !days.isEmpty else { return }
        guard let activity = try? await source.activity(for: days, calendar: wallet.calendar) else { return }
        preload(days)
        for (day, value) in activity {
            let record = activityRecord(for: day)
            guard record.healthSteps != value.steps || record.healthWorkoutMinutes != value.workoutMinutes else { continue }
            record.healthSteps = value.steps
            record.healthWorkoutMinutes = value.workoutMinutes
            record.updatedAt = wallet.now
        }
    }

    private func reportIncome(for day: DayKey) {
        let streak = streakDay(for: day)
        let record = activityRecord(for: day)
        let raw = ProfileIncome.raw(steps: totalSteps(record), workoutMinutes: totalWorkout(record), streakLevel: streak.levelAtStart, config: config)
        wallet.setRawIncome(raw.steps, source: config.stepsSource, day: day)
        wallet.setRawIncome(raw.workout, source: config.workoutSource, day: day)
        wallet.setBonusPercent(raw.bonusPercent, day: day)
    }

    private func totalSteps(_ record: ActivityRecord) -> Int {
        source.isDemo ? record.demoSteps : record.healthSteps + record.demoSteps
    }

    private func totalWorkout(_ record: ActivityRecord) -> Int {
        source.isDemo ? record.demoWorkoutMinutes : record.healthWorkoutMinutes + record.demoWorkoutMinutes
    }

    private func updatePublished() {
        let today = wallet.today
        let record = activityRecord(for: today)
        let streak = streakDay(for: today)
        let steps = totalSteps(record)
        assign(\.todaySteps, steps)
        let workout = totalWorkout(record)
        assign(\.todayWorkoutMinutes, workout)
        assign(\.streakLevel, streak.levelAtStart)
        let percent = StreakEngine.bonusPercent(level: streak.levelAtStart, config: config)
        assign(\.streakBonusPercent, percent)
        assign(\.isRestDayToday, streak.isRestDay)
        let left = max(0, config.restDaysPerWeek - restDaysUsedThisWeek())
        assign(\.restDaysLeftThisWeek, left)
    }

    private func save() {
        context.saveIfNeeded()
    }

    private func restDaysUsedThisWeek() -> Int {
        let week = wallet.today.weekKey(calendar: wallet.calendar)
        let days = (try? context.fetch(FetchDescriptor<StreakDay>(predicate: #Predicate { $0.isRestDay }))) ?? []
        return days.filter { DayKey(id: $0.dayID)?.weekKey(calendar: wallet.calendar) == week }.count
    }

    private func preload(_ days: [DayKey]) {
        activities.preload(days.map(\.id))
    }

    private func activityRecord(for day: DayKey) -> ActivityRecord {
        activities.record(for: day.id) { ActivityRecord(dayID: day.id) }
    }

    @discardableResult
    private func streakDay(for day: DayKey, defaultLevel: Int = 0) -> StreakDay {
        streaks.record(for: day.id) { StreakDay(dayID: day.id, levelAtStart: defaultLevel) }
    }
}

extension ProfileModel: ChangeGuarding {}
