import Foundation
import KinetCurrency
import KinetDesign
import Observation
import SwiftData

@MainActor
@Observable
public final class StudyModel {
    public private(set) var state: StudyState = .idle
    public private(set) var plan: PomodoroPlan?
    public private(set) var sessionStart: Date?
    public private(set) var pausedAt: Date?
    public private(set) var startedCycles = 1
    public private(set) var todayStudied: Int = 0
    public var selectedMinutes: Int = 25
    public var isDemo: Bool = false
    public let config: StudyConfig

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let wallet: Wallet
    @ObservationIgnored private let feedback: Feedback
    @ObservationIgnored private var activeRecord: StudySessionRecord?
    @ObservationIgnored private var lastPhaseKey: String?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var lastInterim: Int?

    public init(context: ModelContext, wallet: Wallet, feedback: Feedback, config: StudyConfig) {
        self.context = context
        self.wallet = wallet
        self.feedback = feedback
        self.config = config
        self.selectedMinutes = config.studyMinutes
        recomputeToday()
    }

    public var breath: BreathCycle { BreathCycle(config: config) }

    public var isPaused: Bool { pausedAt != nil }

    public func effectiveDate(_ date: Date) -> Date {
        guard let pausedAt else { return date }
        return min(date, pausedAt)
    }

    public var isAwaitingNext: Bool {
        guard let pausedAt, let gate = nextGate() else { return false }
        return gate.start == pausedAt
    }

    private func nextGate() -> PomodoroPhase? {
        guard let plan, let sessionStart, plan.isPomodoro, startedCycles < plan.cycles else { return nil }
        return PomodoroSchedule.phases(start: sessionStart, plan: plan).first { $0.kind == .focus && $0.cycle == startedCycles + 1 }
    }

    private func holdAtGateIfReached(now: Date) -> Bool {
        guard pausedAt == nil, let gate = nextGate(), now >= gate.start, let record = activeRecord else { return false }
        pausedAt = gate.start
        record.pausedAt = gate.start
        try? context.save()
        lastPhaseKey = key(gate)
        state = .running(gate)
        feedback.play(.breakEnd)
        stopTicker()
        return true
    }

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    public func progress(at date: Date) -> Double {
        guard let plan, let sessionStart else { return 0 }
        return PomodoroSchedule.progress(at: date, start: sessionStart, plan: plan)
    }

    public func phaseStarts() -> [Date] {
        guard let plan, let sessionStart else { return [] }
        return PomodoroSchedule.phases(start: sessionStart, plan: plan).dropFirst().map(\.start)
    }

    public func ringReading(at date: Date) -> RingReading {
        guard let plan, let sessionStart else { return .zero }
        return PomodoroSchedule.reading(at: effectiveDate(date), start: sessionStart, plan: plan)
    }

    public func start() throws {
        guard case .idle = state else { return }
        let scale = isDemo ? config.demoTimeScale : 1
        let plan = PomodoroPlan(minutes: selectedMinutes, config: config, timeScale: scale)
        let now = wallet.now
        let record = StudySessionRecord(id: UUID(), dayID: wallet.today.id, start: now, minutes: plan.studyMinutes, timeScale: scale)
        context.insert(record)
        try context.save()
        activeRecord = record
        self.plan = plan
        sessionStart = now
        startedCycles = 1
        lastInterim = nil
        if let phase = PomodoroSchedule.phase(at: now, start: now, plan: plan) {
            lastPhaseKey = key(phase)
            state = .running(phase)
        }
        scheduleTicker()
    }

    public func tick() {
        guard case .running(let current) = state, pausedAt == nil, let plan, let sessionStart else { return }
        let now = wallet.now
        if holdAtGateIfReached(now: now) { return }
        guard let phase = PomodoroSchedule.phase(at: now, start: sessionStart, plan: plan) else {
            try? finish(early: false)
            return
        }
        if key(phase) != lastPhaseKey {
            lastPhaseKey = key(phase)
            feedback.play(phase.kind == .cooldown ? .breathStart : .phaseChange)
        }
        if !plan.isPomodoro && (current.kind == .focus || phase.kind == .focus) { reportInterim(until: now) }
        if phase != current { state = .running(phase) }
        scheduleTicker()
    }

    private func scheduleTicker() {
        ticker?.cancel()
        guard case .running(let phase) = state, pausedAt == nil, let plan else {
            ticker = nil
            return
        }
        var wake = phase.end
        if !plan.isPomodoro, phase.kind == .focus {
            let minute = 60 * plan.timeScale
            let elapsed = wallet.now.timeIntervalSince(phase.start)
            let next = phase.start.addingTimeInterval((elapsed / minute).rounded(.down) * minute + minute)
            if next < wake { wake = next }
        }
        let delay = max(0.02, wake.timeIntervalSince(wallet.now) + 0.02)
        ticker = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(25))
            guard !Task.isCancelled, let self else { return }
            self.tick()
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    public func finish(early: Bool) throws {
        guard let plan, let sessionStart, let record = activeRecord else { return }
        let now = pausedAt ?? wallet.now
        let until = early ? now : min(now, PomodoroSchedule.end(start: sessionStart, plan: plan))
        let credited = PomodoroSchedule.creditedMinutes(start: sessionStart, until: until, plan: plan)
        record.endedAt = wallet.now
        record.pausedAt = nil
        pausedAt = nil
        record.creditedMinutes = credited
        try context.save()
        stopTicker()
        lastInterim = nil
        activeRecord = nil
        startedCycles = 1
        self.plan = nil
        self.sessionStart = nil
        lastPhaseKey = nil
        recomputeToday()
        if let day = DayKey(id: record.dayID) {
            wallet.setRawIncome(totalCredited(dayID: record.dayID), source: config.source, day: day)
        }
        recomputeToday()
        if credited > 0 {
            state = .finished(creditedMinutes: credited)
            feedback.play(.sessionEnd)
        } else {
            state = .idle
        }
    }

    public func pause() throws {
        guard case .running(let phase) = state, phase.kind != .cooldown, pausedAt == nil, let record = activeRecord else { return }
        let now = wallet.now
        pausedAt = now
        record.pausedAt = now
        try context.save()
        stopTicker()
    }

    public func resume() throws {
        guard let paused = pausedAt, let sessionStart, let plan, let record = activeRecord else { return }
        let now = wallet.now
        if isAwaitingNext {
            startedCycles += 1
            record.startedCycles = startedCycles
        }
        let shifted = sessionStart.addingTimeInterval(now.timeIntervalSince(paused))
        self.sessionStart = shifted
        record.start = shifted
        record.pausedAt = nil
        pausedAt = nil
        try context.save()
        if let phase = PomodoroSchedule.phase(at: now, start: shifted, plan: plan) {
            lastPhaseKey = key(phase)
            state = .running(phase)
        }
        scheduleTicker()
    }

    public func skipCooldown() throws {
        guard let plan, let sessionStart, let record = activeRecord else { return }
        let now = wallet.now
        guard plan.isPomodoro,
              let phase = PomodoroSchedule.phase(at: now, start: sessionStart, plan: plan),
              phase.kind == .cooldown else {
            try finish(early: true)
            return
        }
        let updated = plan.cutting(cycle: phase.cycle, at: now.timeIntervalSince(phase.start))
        record.breathCuts = updated.breathCuts
        try context.save()
        self.plan = updated
        if let next = PomodoroSchedule.phase(at: now, start: sessionStart, plan: updated) {
            lastPhaseKey = key(next)
            state = .running(next)
            feedback.play(.phaseChange)
        }
        scheduleTicker()
    }

    public func refreshToday() {
        recomputeToday()
    }

    public func resumeIfNeeded() throws {
        recomputeToday()
        guard case .idle = state else { return }
        var descriptor = FetchDescriptor<StudySessionRecord>(predicate: #Predicate { $0.endedAt == nil })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { return }
        let plan = PomodoroPlan(minutes: record.minutes, config: config, timeScale: record.timeScale, breathCuts: record.breathCuts)
        activeRecord = record
        self.plan = plan
        sessionStart = record.start
        pausedAt = record.pausedAt
        startedCycles = record.startedCycles
        let now = pausedAt ?? wallet.now
        if holdAtGateIfReached(now: now) { return }
        if let phase = PomodoroSchedule.phase(at: now, start: record.start, plan: plan) {
            lastPhaseKey = key(phase)
            state = .running(phase)
            scheduleTicker()
        } else {
            try finish(early: false)
        }
    }

    public func dismissSummary() {
        if case .finished = state { state = .idle }
    }

    public func creditedIfEndedNow() -> Int {
        guard let plan, let sessionStart else { return 0 }
        return PomodoroSchedule.creditedMinutes(start: sessionStart, until: pausedAt ?? wallet.now, plan: plan)
    }

    private func key(_ phase: PomodoroPhase) -> String {
        "\(phase.kind.rawValue).\(phase.cycle)"
    }

    private func reportInterim(until date: Date) {
        guard let plan, let sessionStart, let record = activeRecord, let day = DayKey(id: record.dayID) else { return }
        let credited = PomodoroSchedule.creditedMinutes(start: sessionStart, until: date, plan: plan)
        guard credited != lastInterim else { return }
        lastInterim = credited
        wallet.setRawIncome(totalCredited(dayID: record.dayID, excluding: record.id) + credited, source: config.source, day: day)
        let total = totalCredited(dayID: wallet.today.id, excluding: record.id) + (record.dayID == wallet.today.id ? credited : 0)
        assign(\.todayStudied, total)
    }

    public func adjustDemoStudy(by delta: Int) throws {
        let day = wallet.today
        let total = totalCredited(dayID: day.id)
        let target = min(config.minuteRange.upperBound, max(0, total + delta))
        let change = target - total
        guard change != 0 else { return }
        let dayID = day.id
        if change > 0 {
            let record = StudySessionRecord(id: UUID(), dayID: dayID, start: wallet.now, minutes: change, timeScale: 1)
            record.endedAt = wallet.now
            record.creditedMinutes = change
            context.insert(record)
        } else {
            var remaining = -change
            var descriptor = FetchDescriptor<StudySessionRecord>(predicate: #Predicate { $0.dayID == dayID && $0.endedAt != nil })
            descriptor.sortBy = [SortDescriptor(\.start, order: .reverse)]
            for record in (try? context.fetch(descriptor)) ?? [] where remaining > 0 {
                let cut = min(record.creditedMinutes, remaining)
                record.creditedMinutes -= cut
                remaining -= cut
                if record.creditedMinutes == 0 { context.delete(record) }
            }
        }
        try context.save()
        wallet.setRawIncome(target, source: config.source, day: day)
        recomputeToday()
    }

    private func totalCredited(dayID: String, excluding id: UUID? = nil) -> Int {
        let records = (try? context.fetch(FetchDescriptor<StudySessionRecord>(predicate: #Predicate { $0.dayID == dayID && $0.endedAt != nil }))) ?? []
        return records.filter { $0.id != id }.reduce(0) { $0 + $1.creditedMinutes }
    }

    private func recomputeToday() {
        let total = totalCredited(dayID: wallet.today.id)
        assign(\.todayStudied, total)
    }
}

extension StudyModel: ChangeGuarding {}
