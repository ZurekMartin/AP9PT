import Foundation
import SwiftData

@Model
public final class LedgerEntry {
    @Attribute(.unique) public var key: String
    public var dayID: String
    public var date: Date
    public var kindRaw: String
    public var sourceID: String
    public var ownerID: String
    public var amount: Int
    public var title: String
    public var symbol: String
    public var tint: String
    public var itemID: String?

    public init(transaction: Transaction) {
        self.key = transaction.key
        self.dayID = transaction.day.id
        self.date = transaction.date
        self.kindRaw = transaction.kind.rawValue
        self.sourceID = transaction.sourceID
        self.ownerID = transaction.ownerID
        self.amount = transaction.amount
        self.title = transaction.title
        self.symbol = transaction.symbol
        self.tint = transaction.tint
        self.itemID = transaction.itemID
    }

    public var transaction: Transaction {
        Transaction(
            key: key,
            day: DayKey(id: dayID) ?? DayKey(year: 1970, month: 1, day: 1),
            date: date,
            kind: TransactionKind(rawValue: kindRaw) ?? .income,
            sourceID: sourceID,
            ownerID: ownerID,
            amount: amount,
            title: title,
            symbol: symbol,
            tint: tint,
            itemID: itemID
        )
    }
}

@Model
public final class RawIncomeRecord {
    @Attribute(.unique) public var key: String
    public var dayID: String
    public var sourceID: String
    public var rawMinutes: Int

    public init(dayID: String, sourceID: String, rawMinutes: Int) {
        self.key = "\(sourceID).\(dayID)"
        self.dayID = dayID
        self.sourceID = sourceID
        self.rawMinutes = rawMinutes
    }
}

@Model
public final class DayCloseRecord {
    @Attribute(.unique) public var dayID: String
    public var isClosed: Bool
    public var closedAt: Date?

    public init(dayID: String) {
        self.dayID = dayID
        self.isClosed = false
        self.closedAt = nil
    }
}
