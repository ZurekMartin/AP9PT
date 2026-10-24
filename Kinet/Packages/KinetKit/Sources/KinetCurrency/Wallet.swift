import Foundation
import Observation
import SwiftData

@MainActor
@Observable
public final class Wallet {
    public private(set) var today: DayKey
    public private(set) var balance: Int = 0
    public private(set) var donut: [DonutSlice] = []
    public private(set) var recent: [DayStat] = []
    public private(set) var reservations: [Reservation] = []
    public let config: CurrencyConfig
    public let calendar: Calendar

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let clock: any KinetClock
    @ObservationIgnored private var participants: [WeakParticipant] = []
    @ObservationIgnored private var ledger: [String: Transaction] = [:]
    @ObservationIgnored private var entries: [String: LedgerEntry] = [:]
    @ObservationIgnored private var rawRecords: [String: RawIncomeRecord] = [:]
    @ObservationIgnored private var closeRecords: [String: DayCloseRecord] = [:]
    @ObservationIgnored private var isClosing = false
    @ObservationIgnored private var batchDepth = 0
    @ObservationIgnored private var saveScheduled = false

    private struct WeakParticipant {
        weak var value: (any DayCloseParticipant)?
    }

    public static let recentDays = 42

    public init(context: ModelContext, clock: any KinetClock, calendar: Calendar, config: CurrencyConfig) {
        self.context = context
        self.clock = clock
        self.calendar = calendar
        self.config = config
        let day = DayKey(date: clock.now, calendar: calendar)
        self.today = day
        reload()
    }

    public var summary: DayStat {
        recent.last ?? DayStat(day: today, incomeBySource: [:], incomeBySegment: [:], spent: 0, spentBySource: [:])
    }

    public var now: Date { clock.now }

    public func register(_ participant: any DayCloseParticipant) {
        participants.removeAll { $0.value == nil }
        participants.append(WeakParticipant(value: participant))
    }

    public func reload() {
        let fetchedEntries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        entries = Dictionary(fetchedEntries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        ledger = entries.mapValues(\.transaction)
        let fetchedRaw = (try? context.fetch(FetchDescriptor<RawIncomeRecord>())) ?? []
        rawRecords = Dictionary(fetchedRaw.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let fetchedClose = (try? context.fetch(FetchDescriptor<DayCloseRecord>())) ?? []
        closeRecords = Dictionary(fetchedClose.map { ($0.dayID, $0) }, uniquingKeysWith: { first, _ in first })
        publish()
    }

    public func refresh() {
        publish()
    }

    public func batch(_ work: () -> Void) {
        batchDepth += 1
        work()
        batchDepth -= 1
        publish()
    }

    public func performBatch(_ work: () async -> Void) async {
        batchDepth += 1
        await work()
        batchDepth -= 1
        publish()
        save()
    }

    public func setRawIncome(_ minutes: Int, source: IncomeSourceID, day: DayKey) {
        guard !isClosed(day) else { return }
        let value = max(0, minutes)
        let key = "\(source.rawValue).\(day.id)"
        if let record = rawRecords[key] {
            guard record.rawMinutes != value else { return }
            record.rawMinutes = value
        } else {
            guard value > 0 else { return }
            let record = RawIncomeRecord(dayID: day.id, sourceID: source.rawValue, rawMinutes: value)
            context.insert(record)
            rawRecords[key] = record
        }
        reallocate(day)
        commit()
    }

    public func setBonusPercent(_ percent: Int, day: DayKey) {
        setRawIncome(percent, source: .bonusPercent, day: day)
    }

    @discardableResult
    public func spend(_ request: SpendRequest) throws(SpendError) -> Transaction {
        guard request.amount > 0 else { throw .invalidAmount }
        let available = LedgerMath.spendable(balance: balance, reservations: reservations, consumingReservationOf: request.consumesReservationOf)
        guard request.amount <= available else {
            if request.amount <= balance {
                let blocking = reservations.first { $0.ownerID != request.consumesReservationOf }
                throw .reserved(minutes: blocking?.minutes ?? 0, title: blocking?.title ?? "")
            }
            throw .insufficientFunds(missing: request.amount - balance)
        }
        let transaction = post(
            key: "spend.\(request.ownerID).\(request.sourceID).\(UUID().uuidString)",
            day: today,
            date: clock.now,
            kind: .spend,
            sourceID: request.sourceID,
            ownerID: request.ownerID,
            amount: -request.amount,
            title: request.title,
            symbol: request.symbol,
            tint: request.tint,
            itemID: request.itemID
        )
        publish()
        save()
        return transaction
    }

    public func recordDeterministicSpend(_ request: SpendRequest, day: DayKey) {
        guard request.amount > 0 else { return }
        post(
            key: "spend.\(request.ownerID).\(request.sourceID).\(day.id)",
            day: day,
            date: time(on: day, hour: 23),
            kind: .spend,
            sourceID: request.sourceID,
            ownerID: request.ownerID,
            amount: -request.amount,
            title: request.title,
            symbol: request.symbol,
            tint: request.tint,
            itemID: request.itemID
        )
        commit()
    }

    public func recordGrant(_ minutes: Int, sourceID: String, title: String, symbol: String, tint: String, day: DayKey) {
        let key = "grant.\(sourceID).\(day.id)"
        guard minutes > 0 || ledger[key] != nil else { return }
        post(key: key, day: day, date: time(on: day, hour: 22), kind: .income, sourceID: sourceID, amount: minutes, title: title, symbol: symbol, tint: tint)
        enforceCaps(on: day)
        commit()
    }

    public func discardCarryover(before day: DayKey) {
        let previous = day.adding(days: -1, calendar: calendar)
        let amount = balance(through: previous)
        guard amount > 0 else { return }
        post(
            key: "flush.\(previous.id)", day: previous, date: time(on: previous, hour: 23.75), kind: .expiry, sourceID: "expiry",
            amount: -amount, title: config.expiryTitle, symbol: config.expirySymbol, tint: config.expiryTint
        )
        commit()
    }

    public func recordOwnership(itemID: String, ownerID: String, sourceID: String, title: String, symbol: String, tint: String, day: DayKey) {
        post(
            key: "owned.\(ownerID).\(itemID)", day: day, date: time(on: day, hour: 12), kind: .spend, sourceID: sourceID,
            ownerID: ownerID, amount: 0, title: title, symbol: symbol, tint: tint, itemID: itemID
        )
        commit()
    }

    public func grantAmount(sourceID: String, day: DayKey) -> Int {
        ledger["grant.\(sourceID).\(day.id)"]?.amount ?? 0
    }

    public func reserve(_ reservation: Reservation) {
        var next = reservations.filter { $0.ownerID != reservation.ownerID }
        if reservation.minutes > 0 { next.append(reservation) }
        assign(\.reservations, next)
    }

    public func spendable(for ownerID: String?) -> Int {
        LedgerMath.spendable(balance: balance, reservations: reservations, consumingReservationOf: ownerID)
    }

    public func transactions(ownerID: String) -> [Transaction] {
        ledger.values.filter { $0.ownerID == ownerID }
    }

    public func transactions(on day: DayKey) -> [Transaction] {
        ledger.values.filter { $0.day == day }
    }

    public func income(sourceID: String) -> Int {
        ledger.values.reduce(0) { $1.kind == .income && $1.sourceID == sourceID ? $0 + $1.amount : $0 }
    }

    public func balance(through day: DayKey) -> Int {
        LedgerMath.balance(ledger.values, through: day)
    }

    public func isClosed(_ day: DayKey) -> Bool {
        closeRecords[day.id]?.isClosed ?? false
    }

    public func save() {
        context.saveIfNeeded()
    }

    @discardableResult
    public func closePendingDays() async -> Bool {
        guard !isClosing else { return false }
        isClosing = true
        defer { isClosing = false }
        publish()
        let current = today
        var earliest = current
        for id in closeRecords.keys { if let key = DayKey(id: id), key < earliest { earliest = key } }
        for transaction in ledger.values where transaction.day < earliest { earliest = transaction.day }
        var cursor = earliest
        while cursor <= current {
            if closeRecords[cursor.id] == nil {
                let record = DayCloseRecord(dayID: cursor.id)
                context.insert(record)
                closeRecords[cursor.id] = record
            }
            cursor = cursor.adding(days: 1, calendar: calendar)
        }
        let pending = closeRecords.values
            .filter { !$0.isClosed }
            .compactMap { DayKey(id: $0.dayID) }
            .filter { $0 < current }
            .sorted()
        guard !pending.isEmpty else {
            save()
            return false
        }
        participants.removeAll { $0.value == nil }
        let ordered = participants.compactMap(\.value).sorted { $0.closeOrder < $1.closeOrder }
        for participant in ordered { await participant.prepare(days: pending) }
        batch {
            for day in pending {
                for participant in ordered { participant.close(day: day, in: self) }
                let expired = config.expiry(forBalance: balance(through: day))
                if expired > 0 {
                    post(
                        key: "expiry.\(day.id)", day: day, date: time(on: day, hour: 23.5), kind: .expiry, sourceID: "expiry",
                        amount: -expired, title: config.expiryTitle, symbol: config.expirySymbol, tint: config.expiryTint
                    )
                }
                if let record = closeRecords[day.id] {
                    record.isClosed = true
                    record.closedAt = clock.now
                }
            }
        }
        save()
        return true
    }

    private func publish() {
        let day = DayKey(date: clock.now, calendar: calendar)
        assign(\.today, day)
        guard batchDepth == 0 else {
            let current = LedgerMath.balance(ledger.values, through: day)
            assign(\.balance, current)
            return
        }
        let snapshot = LedgerMath.snapshot(ledger.values, today: day, config: config, recentDays: Self.recentDays, calendar: calendar)
        assign(\.balance, snapshot.balance)
        assign(\.donut, snapshot.donut)
        assign(\.recent, snapshot.recent)
    }

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.saveScheduled = false
            self.save()
        }
    }

    private func time(on day: DayKey, hour: Double) -> Date {
        day.startDate(in: calendar).addingTimeInterval(hour * 3600)
    }

    private func commit() {
        publish()
        scheduleSave()
    }

    @discardableResult
    private func post(key: String, day: DayKey, date: Date, kind: TransactionKind, sourceID: String, ownerID: String = "wallet", amount: Int, title: String, symbol: String, tint: String, itemID: String? = nil) -> Transaction {
        let transaction = Transaction(key: key, day: day, date: date, kind: kind, sourceID: sourceID, ownerID: ownerID, amount: amount, title: title, symbol: symbol, tint: tint, itemID: itemID)
        store(transaction)
        return transaction
    }

    private func store(_ transaction: Transaction) {
        if let entry = entries[transaction.key] {
            entry.amount = transaction.amount
            entry.title = transaction.title
            entry.symbol = transaction.symbol
            entry.tint = transaction.tint
            ledger[transaction.key] = entry.transaction
        } else {
            let entry = LedgerEntry(transaction: transaction)
            context.insert(entry)
            entries[transaction.key] = entry
            ledger[transaction.key] = transaction
        }
    }

    private func reallocate(_ day: DayKey) {
        let dayID = day.id
        var raw: [IncomeSourceID: Int] = [:]
        for record in rawRecords.values where record.dayID == dayID {
            raw[IncomeSourceID(record.sourceID)] = record.rawMinutes
        }
        let allocated = IncomeAllocator.allocate(raw: raw, bonusPercent: raw[.bonusPercent] ?? 0, config: config)
        for descriptor in config.descriptors {
            let value = allocated[descriptor.id] ?? 0
            let key = "income.\(descriptor.id.rawValue).\(dayID)"
            if let existing = ledger[key] {
                guard existing.amount != value, let entry = entries[key] else { continue }
                entry.amount = value
                ledger[key] = entry.transaction
            } else if value > 0 {
                post(
                    key: key, day: day, date: day == today ? clock.now : time(on: day, hour: 12), kind: .income, sourceID: descriptor.id.rawValue,
                    amount: value, title: descriptor.title, symbol: descriptor.symbol, tint: descriptor.tint
                )
            }
        }
        enforceCaps(on: day)
    }

    private func enforceCaps(on day: DayKey) {
        let grants = ledger.values.filter { $0.day == day && $0.kind == .income && $0.key.hasPrefix("grant.") && $0.amount > 0 }
        guard !grants.isEmpty else { return }
        let income = ledger.values.reduce(0) { $1.day == day && $1.kind == .income ? $0 + $1.amount : $0 }
        var excess = max(income - config.maxDailyIncome, balance(through: day) - config.maxBalance)
        for grant in grants where excess > 0 {
            guard let entry = entries[grant.key] else { continue }
            let cut = min(excess, grant.amount)
            entry.amount = grant.amount - cut
            ledger[grant.key] = entry.transaction
            excess -= cut
        }
    }
}

extension Wallet: ChangeGuarding {}
