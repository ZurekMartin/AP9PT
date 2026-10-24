import Foundation
import HealthKit
import KinetCurrency

public struct HealthDay: Sendable, Equatable {
    public let steps: Int
    public let workoutMinutes: Int

    public init(steps: Int, workoutMinutes: Int) {
        self.steps = steps
        self.workoutMinutes = workoutMinutes
    }
}

public enum HealthAccess: Sendable, Equatable {
    case unavailable, notDetermined, requested
}

public protocol ActivitySource: Sendable {
    var isDemo: Bool { get }
    func access() async -> HealthAccess
    func requestAuthorization() async throws
    func activity(for days: [DayKey], calendar: Calendar) async throws -> [DayKey: HealthDay]
}

public struct DemoActivitySource: ActivitySource {
    private let health = HealthKitActivitySource()

    public init() {}
    public var isDemo: Bool { true }
    public func access() async -> HealthAccess { await health.access() }
    public func requestAuthorization() async throws { try await health.requestAuthorization() }
    public func activity(for days: [DayKey], calendar: Calendar) async throws -> [DayKey: HealthDay] { [:] }
}

public struct HealthKitActivitySource: ActivitySource {
    public init() {}

    public var isDemo: Bool { false }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        return types
    }

    private static let store = HKHealthStore()

    public func access() async -> HealthAccess {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        guard let status = try? await Self.store.statusForAuthorizationRequest(toShare: [], read: readTypes) else { return .notDetermined }
        return status == .unnecessary ? .requested : .notDetermined
    }

    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await Self.store.requestAuthorization(toShare: [], read: readTypes)
    }

    public func activity(for days: [DayKey], calendar: Calendar) async throws -> [DayKey: HealthDay] {
        guard HKHealthStore.isHealthDataAvailable(), let first = days.min(), let last = days.max() else { return [:] }
        let store = Self.store
        let start = first.startDate(in: calendar)
        let end = last.adding(days: 1, calendar: calendar).startDate(in: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        var steps: [DayKey: Int] = [:]
        var workouts: [DayKey: Int] = [:]

        if let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            let descriptor = HKStatisticsCollectionQueryDescriptor(
                predicate: HKSamplePredicate.quantitySample(type: stepType, predicate: predicate),
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: DateComponents(day: 1)
            )
            if let collection = try? await descriptor.result(for: store) {
                collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let value = statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    steps[DayKey(date: statistics.startDate, calendar: calendar), default: 0] += Int(value)
                }
            }
        }

        let workoutDescriptor = HKSampleQueryDescriptor(
            predicates: [HKSamplePredicate.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        if let samples = try? await workoutDescriptor.result(for: store) {
            var seconds: [DayKey: Double] = [:]
            for workout in samples {
                seconds[DayKey(date: workout.startDate, calendar: calendar), default: 0] += workout.duration
            }
            for (day, value) in seconds { workouts[day] = Int(value / 60) }
        }

        var result: [DayKey: HealthDay] = [:]
        for day in days {
            result[day] = HealthDay(steps: steps[day] ?? 0, workoutMinutes: workouts[day] ?? 0)
        }
        return result
    }
}
