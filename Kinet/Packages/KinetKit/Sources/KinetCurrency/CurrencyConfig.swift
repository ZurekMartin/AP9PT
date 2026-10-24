import Foundation

public struct IncomeSourceID: Hashable, Codable, Sendable, RawRepresentable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let bonusPercent = IncomeSourceID("bonusPercent")
}

public struct IncomeSourceDescriptor: Sendable, Equatable, Identifiable {
    public var id: IncomeSourceID
    public var title: String
    public var symbol: String
    public var tint: String
    public var segment: String
    public var segmentTitle: String
    public var priority: Int
    public var dailyCap: Int?

    public init(id: IncomeSourceID, title: String, symbol: String, tint: String, segment: String, segmentTitle: String, priority: Int, dailyCap: Int?) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.segment = segment
        self.segmentTitle = segmentTitle
        self.priority = priority
        self.dailyCap = dailyCap
    }
}

public struct CurrencyConfig: Sendable, Equatable {
    public var dailyIncomeCap: Int
    public var bonusCap: Int
    public var carryoverCap: Int
    public var sources: [IncomeSourceDescriptor]
    public var bonus: IncomeSourceDescriptor
    public var expiryTint: String
    public var expiryTitle: String
    public var expirySymbol: String

    public init(dailyIncomeCap: Int, bonusCap: Int, carryoverCap: Int, sources: [IncomeSourceDescriptor], bonus: IncomeSourceDescriptor, expiryTint: String, expiryTitle: String, expirySymbol: String) {
        self.dailyIncomeCap = dailyIncomeCap
        self.bonusCap = bonusCap
        self.carryoverCap = carryoverCap
        self.sources = sources.sorted { $0.priority < $1.priority }
        self.bonus = bonus
        self.expiryTint = expiryTint
        self.expiryTitle = expiryTitle
        self.expirySymbol = expirySymbol
    }

    public var maxDailyIncome: Int { dailyIncomeCap + bonusCap }
    public var maxBalance: Int { carryoverCap + maxDailyIncome }

    public func expiry(forBalance balance: Int) -> Int {
        max(0, balance - carryoverCap)
    }

    public var descriptors: [IncomeSourceDescriptor] { sources + [bonus] }

    public var displaySegments: [String] { sources.reversed().map(\.segment) + [bonus.segment] }

    public func segmentTint(for segment: String) -> String {
        descriptors.first { $0.segment == segment }?.tint ?? expiryTint
    }

    public func segmentTitle(for segment: String) -> String {
        return descriptors.first { $0.segment == segment }?.segmentTitle ?? segment
    }

    public func descriptor(for id: IncomeSourceID) -> IncomeSourceDescriptor? {
        if id == bonus.id { return bonus }
        return sources.first { $0.id == id }
    }

    public func segment(for id: IncomeSourceID) -> String {
        descriptor(for: id)?.segment ?? bonus.segment
    }
}
