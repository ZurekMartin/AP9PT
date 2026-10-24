import Foundation
import KinetCurrency
import KinetDesign
import SwiftData

public struct ProfileConfig: Sendable, Equatable {
    public var ownerID: String
    public var stepsPerMinute: Int
    public var workoutMultiplier: Int
    public var streakPercentPerLevel: Int
    public var streakMaxLevel: Int
    public var streakMissPenalty: Int
    public var defaultStepGoal: Int
    public var stepGoalRange: ClosedRange<Int>
    public var stepGoalStep: Int
    public var restDayPrice: Int
    public var restDaysPerWeek: Int
    public var healthLookbackDays: Int
    public var healthBackfillDays: Int
    public var stepsSource: IncomeSourceID
    public var workoutSource: IncomeSourceID
    public var streakBonusSource: IncomeSourceID

    public init(ownerID: String, stepsPerMinute: Int, workoutMultiplier: Int, streakPercentPerLevel: Int, streakMaxLevel: Int, streakMissPenalty: Int, defaultStepGoal: Int, stepGoalRange: ClosedRange<Int>, stepGoalStep: Int, restDayPrice: Int, restDaysPerWeek: Int, healthLookbackDays: Int, healthBackfillDays: Int, stepsSource: IncomeSourceID, workoutSource: IncomeSourceID, streakBonusSource: IncomeSourceID) {
        self.ownerID = ownerID
        self.stepsPerMinute = stepsPerMinute
        self.workoutMultiplier = workoutMultiplier
        self.streakPercentPerLevel = streakPercentPerLevel
        self.streakMaxLevel = streakMaxLevel
        self.streakMissPenalty = streakMissPenalty
        self.defaultStepGoal = defaultStepGoal
        self.stepGoalRange = stepGoalRange
        self.stepGoalStep = stepGoalStep
        self.restDayPrice = restDayPrice
        self.restDaysPerWeek = restDaysPerWeek
        self.healthLookbackDays = healthLookbackDays
        self.healthBackfillDays = healthBackfillDays
        self.stepsSource = stepsSource
        self.workoutSource = workoutSource
        self.streakBonusSource = streakBonusSource
    }
}

@Model
public final class ActivityRecord {
    @Attribute(.unique) public var dayID: String
    public var healthSteps: Int
    public var healthWorkoutMinutes: Int
    public var demoSteps: Int
    public var demoWorkoutMinutes: Int
    public var updatedAt: Date

    public init(dayID: String) {
        self.dayID = dayID
        self.healthSteps = 0
        self.healthWorkoutMinutes = 0
        self.demoSteps = 0
        self.demoWorkoutMinutes = 0
        self.updatedAt = .now
    }
}

@Model
public final class StreakDay {
    @Attribute(.unique) public var dayID: String
    public var levelAtStart: Int
    public var isRestDay: Bool
    public var outcomeRaw: String?

    public init(dayID: String, levelAtStart: Int) {
        self.dayID = dayID
        self.levelAtStart = levelAtStart
        self.isRestDay = false
        self.outcomeRaw = nil
    }
}

public struct ProfileRawIncome: Sendable, Equatable {
    public let steps: Int
    public let workout: Int
    public let bonusPercent: Int
}

public enum ProfileIncome {
    public static func raw(steps: Int, workoutMinutes: Int, streakLevel: Int, config: ProfileConfig) -> ProfileRawIncome {
        let stepMinutes = max(0, steps) / max(1, config.stepsPerMinute)
        let workout = max(0, workoutMinutes) * config.workoutMultiplier
        return ProfileRawIncome(steps: stepMinutes, workout: workout, bonusPercent: StreakEngine.bonusPercent(level: streakLevel, config: config))
    }
}

public enum DayOutcome: String, Codable, Sendable {
    case goalMet, missed, restDay
}

public enum StreakEngine {
    public static func outcome(steps: Int, goal: Int, isRestDay: Bool) -> DayOutcome {
        if steps >= goal { return .goalMet }
        return isRestDay ? .restDay : .missed
    }

    public static func nextLevel(from level: Int, outcome: DayOutcome, config: ProfileConfig) -> Int {
        switch outcome {
        case .goalMet: min(config.streakMaxLevel, level + 1)
        case .missed: max(0, level - config.streakMissPenalty)
        case .restDay: level
        }
    }

    public static func bonusPercent(level: Int, config: ProfileConfig) -> Int {
        min(config.streakMaxLevel, max(0, level)) * config.streakPercentPerLevel
    }
}

public enum RestDayError: Error, Equatable, Sendable {
    case alreadyActive
    case weeklyLimit
    case spend(SpendError)
}

@MainActor
@Observable
public final class ProfileSettings {
    public var stepGoal: Int {
        didSet { store.save(stepGoal, "profile.stepGoal") }
    }
    public var hasBackfilled: Bool {
        didSet { store.save(hasBackfilled, "profile.backfilled") }
    }

    @ObservationIgnored private let store: SettingsStore

    public init(defaults: UserDefaults, config: ProfileConfig) {
        store = SettingsStore(defaults)
        hasBackfilled = store.value("profile.backfilled", default: false)
        let stored = store.value("profile.stepGoal", default: 0)
        stepGoal = stored == 0 ? config.defaultStepGoal : min(max(stored, config.stepGoalRange.lowerBound), config.stepGoalRange.upperBound)
    }
}
