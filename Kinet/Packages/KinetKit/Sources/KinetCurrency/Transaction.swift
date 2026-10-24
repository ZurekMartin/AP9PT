import Foundation

public enum TransactionKind: String, Codable, Sendable {
    case income, spend, expiry
}

public struct Transaction: Sendable, Equatable, Identifiable {
    public var id: String { key }
    public let key: String
    public let day: DayKey
    public let date: Date
    public let kind: TransactionKind
    public let sourceID: String
    public let ownerID: String
    public let amount: Int
    public let title: String
    public let symbol: String
    public let tint: String
    public let itemID: String?

    public init(key: String, day: DayKey, date: Date, kind: TransactionKind, sourceID: String, ownerID: String, amount: Int, title: String, symbol: String, tint: String, itemID: String?) {
        self.key = key
        self.day = day
        self.date = date
        self.kind = kind
        self.sourceID = sourceID
        self.ownerID = ownerID
        self.amount = amount
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.itemID = itemID
    }
}

public struct SpendRequest: Sendable, Equatable {
    public let ownerID: String
    public let sourceID: String
    public let amount: Int
    public let title: String
    public let symbol: String
    public let tint: String
    public let itemID: String?
    public let consumesReservationOf: String?

    public init(ownerID: String, sourceID: String, amount: Int, title: String, symbol: String, tint: String, itemID: String? = nil, consumesReservationOf: String? = nil) {
        self.ownerID = ownerID
        self.sourceID = sourceID
        self.amount = amount
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.itemID = itemID
        self.consumesReservationOf = consumesReservationOf
    }
}

public struct Reservation: Sendable, Equatable {
    public let ownerID: String
    public let title: String
    public let minutes: Int

    public init(ownerID: String, title: String, minutes: Int) {
        self.ownerID = ownerID
        self.title = title
        self.minutes = minutes
    }
}

public enum SpendError: Error, Equatable, Sendable {
    case insufficientFunds(missing: Int)
    case reserved(minutes: Int, title: String)
    case invalidAmount
}

public struct DonutSlice: Sendable, Equatable, Identifiable {
    public var id: String { isSpent ? segment + ".spent" : segment }
    public let segment: String
    public let tint: String
    public let minutes: Int
    public let isSpent: Bool

    public init(segment: String, tint: String, minutes: Int, isSpent: Bool) {
        self.segment = segment
        self.tint = tint
        self.minutes = minutes
        self.isSpent = isSpent
    }
}

public struct DayStat: Sendable, Equatable, Identifiable {
    public var id: String { day.id }
    public let day: DayKey
    public let incomeBySource: [IncomeSourceID: Int]
    public let incomeBySegment: [String: Int]
    public let spent: Int
    public let spentBySource: [String: Int]
    public var income: Int { incomeBySource.values.reduce(0, +) }

    public init(day: DayKey, incomeBySource: [IncomeSourceID: Int], incomeBySegment: [String: Int], spent: Int, spentBySource: [String: Int]) {
        self.day = day
        self.incomeBySource = incomeBySource
        self.incomeBySegment = incomeBySegment
        self.spent = spent
        self.spentBySource = spentBySource
    }
}

public struct LedgerSnapshot: Sendable {
    public let balance: Int
    public let donut: [DonutSlice]
    public let recent: [DayStat]
}
