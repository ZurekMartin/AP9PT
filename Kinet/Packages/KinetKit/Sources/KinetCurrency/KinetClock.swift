import Foundation
import Synchronization

public protocol KinetClock: Sendable {
    var now: Date { get }
}

public struct SystemClock: KinetClock {
    public init() {}
    public var now: Date { Date() }
}

public final class OffsetClock: KinetClock, Sendable {
    private let storage: Mutex<Int>
    private let calendar: Calendar

    public init(dayOffset: Int, calendar: Calendar) {
        self.storage = Mutex(dayOffset)
        self.calendar = calendar
    }

    public var dayOffset: Int {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }

    public var now: Date {
        calendar.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
    }
}

public extension Locale {
    static let czech = Locale(identifier: "cs_CZ")
}

public extension Calendar {
    static var kinet: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .czech
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        calendar.timeZone = .current
        return calendar
    }
}
