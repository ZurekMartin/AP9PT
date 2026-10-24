import Foundation
import KinetCurrency
import SwiftData

public struct StudyConfig: Sendable, Equatable {
    public var studyMinutes: Int
    public var focusMinutes: Int
    public var cycleMinutes: Int
    public var inhaleSeconds: Double
    public var exhaleSeconds: Double
    public var breathSeconds: Double
    public var restSeconds: Double
    public var minuteRange: ClosedRange<Int>
    public var demoTimeScale: Double
    public var source: IncomeSourceID

    public init(studyMinutes: Int, focusMinutes: Int, cycleMinutes: Int, inhaleSeconds: Double, exhaleSeconds: Double, breathSeconds: Double, restSeconds: Double, minuteRange: ClosedRange<Int>, demoTimeScale: Double, source: IncomeSourceID) {
        self.studyMinutes = studyMinutes
        self.focusMinutes = focusMinutes
        self.cycleMinutes = cycleMinutes
        self.inhaleSeconds = inhaleSeconds
        self.exhaleSeconds = exhaleSeconds
        self.breathSeconds = breathSeconds
        self.restSeconds = restSeconds
        self.minuteRange = minuteRange
        self.demoTimeScale = demoTimeScale
        self.source = source
    }
}

@Model
public final class StudySessionRecord {
    @Attribute(.unique) public var id: UUID
    public var dayID: String
    public var start: Date
    public var minutes: Int
    public var timeScale: Double
    public var endedAt: Date?
    public var creditedMinutes: Int
    public var breathCuts: [Double] = []
    public var pausedAt: Date?
    public var startedCycles: Int = 1

    public init(id: UUID, dayID: String, start: Date, minutes: Int, timeScale: Double) {
        self.id = id
        self.dayID = dayID
        self.start = start
        self.minutes = minutes
        self.timeScale = timeScale
        self.endedAt = nil
        self.creditedMinutes = 0
    }
}

public struct BreathCycle: Sendable, Equatable {
    public let inhale: Double
    public let exhale: Double

    public init(config: StudyConfig) {
        inhale = config.inhaleSeconds
        exhale = config.exhaleSeconds
    }

    public var length: Double { inhale + exhale }

    public func elapsed(at date: Date, since start: Date) -> Double {
        max(0, date.timeIntervalSince(start)).truncatingRemainder(dividingBy: length)
    }

    public func isInhaling(at date: Date, since start: Date) -> Bool {
        elapsed(at: date, since: start) < inhale
    }

    public func progress(at date: Date, since start: Date) -> Double {
        let cycle = elapsed(at: date, since: start)
        let raw = cycle < inhale ? cycle / inhale : 1 - (cycle - inhale) / exhale
        return 0.5 - 0.5 * cos(raw * .pi)
    }
}

public struct PomodoroPlan: Sendable, Equatable, Codable {
    public let focusMinutes: Int
    public let cycleMinutes: Int
    public let studyMinutes: Int
    public let breathSeconds: Double
    public let restSeconds: Double
    public let timeScale: Double
    public var breathCuts: [Double]

    public init(minutes: Int, config: StudyConfig, timeScale: Double, breathCuts: [Double] = []) {
        self.studyMinutes = minutes
        let breathLength = BreathCycle(config: config).length
        self.focusMinutes = config.focusMinutes
        self.cycleMinutes = config.cycleMinutes
        self.breathSeconds = max(breathLength, (config.breathSeconds * min(1, timeScale) / breathLength).rounded(.up) * breathLength)
        self.restSeconds = config.restSeconds * timeScale
        self.timeScale = timeScale
        self.breathCuts = breathCuts
    }

    public var breakSeconds: Double { breathSeconds + restSeconds }
    public var isPomodoro: Bool { studyMinutes % cycleMinutes == 0 }
    public var cycles: Int { isPomodoro ? studyMinutes / cycleMinutes : 1 }
    public var creditableMinutes: Int { isPomodoro ? cycles * cycleMinutes : studyMinutes }
    public var giftMinutes: Int { cycleMinutes - focusMinutes }

    public func breathCut(cycle: Int) -> Double? {
        guard cycle >= 1, cycle <= breathCuts.count, breathCuts[cycle - 1] > 0 else { return nil }
        return breathCuts[cycle - 1]
    }

    public func cutting(cycle: Int, at seconds: Double) -> PomodoroPlan {
        var copy = self
        while copy.breathCuts.count < cycle { copy.breathCuts.append(0) }
        copy.breathCuts[cycle - 1] = max(0.5, seconds)
        return copy
    }
}

public struct RingReading: Sendable, Equatable {
    public static let blendDuration = 1.8
    public static let zero = RingReading(value: 0, restWeight: 0, tide: 0)

    public var value: Double
    public var restWeight: Double
    public var tide: Double

    static func lerp(_ a: RingReading, _ b: RingReading, _ t: Double) -> RingReading {
        RingReading(value: a.value + (b.value - a.value) * t, restWeight: a.restWeight + (b.restWeight - a.restWeight) * t, tide: a.tide + (b.tide - a.tide) * t)
    }
}

public enum PomodoroPhaseKind: String, Sendable, Codable {
    case focus, cooldown, rest
}

public struct PomodoroPhase: Sendable, Equatable, Codable {
    public let kind: PomodoroPhaseKind
    public let cycle: Int
    public let start: Date
    public let end: Date

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public enum PomodoroSchedule {
    public static func phases(start: Date, plan: PomodoroPlan) -> [PomodoroPhase] {
        var result: [PomodoroPhase] = []
        var cursor = start
        func append(_ kind: PomodoroPhaseKind, cycle: Int, seconds: TimeInterval) {
            let end = cursor.addingTimeInterval(seconds)
            result.append(PomodoroPhase(kind: kind, cycle: cycle, start: cursor, end: end))
            cursor = end
        }
        let focus = Double(plan.isPomodoro ? plan.focusMinutes : plan.studyMinutes) * 60 * plan.timeScale
        for cycle in 1...plan.cycles {
            append(.focus, cycle: cycle, seconds: focus)
            if plan.isPomodoro {
                let breath = min(plan.breathCut(cycle: cycle) ?? plan.breathSeconds, plan.breathSeconds)
                append(.cooldown, cycle: cycle, seconds: breath)
                append(.rest, cycle: cycle, seconds: plan.breakSeconds - breath)
            } else {
                append(.cooldown, cycle: cycle, seconds: plan.breathSeconds)
            }
        }
        return result
    }

    public static func reading(at date: Date, start: Date, plan: PomodoroPlan) -> RingReading {
        let all = phases(start: start, plan: plan)
        guard let index = all.firstIndex(where: { date >= $0.start && date < $0.end }) ?? all.indices.last else { return .zero }
        let live = raw(all, index, at: date, plan: plan)
        guard index > 0 else { return live }
        if plan.isPomodoro, all[index].kind == .focus, all[index].cycle > 1 { return live }
        let elapsed = date.timeIntervalSince(all[index].start)
        guard elapsed < RingReading.blendDuration else { return live }
        let previous = raw(all, index - 1, at: all[index - 1].end, plan: plan)
        let t = elapsed / RingReading.blendDuration
        return RingReading.lerp(previous, live, t * t * t * (t * (6 * t - 15) + 10))
    }

    private static func raw(_ all: [PomodoroPhase], _ index: Int, at date: Date, plan: PomodoroPlan) -> RingReading {
        let phase = all[index]
        let d = min(max(date, phase.start), phase.end)
        let gift = Double(plan.giftMinutes)
        let later = Double(max(0, plan.cycles - phase.cycle) * plan.cycleMinutes)
        switch phase.kind {
        case .focus:
            let left = max(0, phase.end.timeIntervalSince(d)) / plan.timeScale / 60
            let value = plan.isPomodoro ? left + gift + later : left
            return RingReading(value: value, restWeight: 0, tide: value)
        case .cooldown, .rest:
            guard plan.isPomodoro,
                  let breakStart = all.first(where: { $0.cycle == phase.cycle && $0.kind == .cooldown })?.start,
                  let breakEnd = all.last(where: { $0.cycle == phase.cycle })?.end else { return .zero }
            let total = breakEnd.timeIntervalSince(breakStart)
            let fraction = total > 0 ? max(0, min(1, breakEnd.timeIntervalSince(d) / total)) : 0
            return RingReading(value: 60 * fraction, restWeight: 1, tide: later + gift * fraction)
        }
    }

    public static func phase(at date: Date, start: Date, plan: PomodoroPlan) -> PomodoroPhase? {
        phases(start: start, plan: plan).first { date >= $0.start && date < $0.end }
    }

    public static func end(start: Date, plan: PomodoroPlan) -> Date {
        phases(start: start, plan: plan).last?.end ?? start
    }

    public static func creditedMinutes(start: Date, until date: Date, plan: PomodoroPlan) -> Int {
        var seconds = 0.0
        for phase in phases(start: start, plan: plan) where phase.kind == .focus {
            let upper = min(date, phase.end)
            if upper > phase.start { seconds += upper.timeIntervalSince(phase.start) }
        }
        let real = seconds / plan.timeScale / 60
        var total = Int((real + 1e-6).rounded(.down))
        if plan.isPomodoro {
            let finished = phases(start: start, plan: plan).filter { $0.kind == .focus && date >= $0.end }.count
            total += finished * plan.giftMinutes
        }
        return min(plan.creditableMinutes, total)
    }

    public static func progress(at date: Date, start: Date, plan: PomodoroPlan) -> Double {
        let total = end(start: start, plan: plan).timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / total))
    }
}

public enum StudyState: Equatable {
    case idle
    case running(PomodoroPhase)
    case finished(creditedMinutes: Int)
}
