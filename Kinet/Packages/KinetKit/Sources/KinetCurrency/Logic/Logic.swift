import Foundation

public enum IncomeAllocator {
    public static func allocate(raw: [IncomeSourceID: Int], bonusPercent: Int, config: CurrencyConfig) -> [IncomeSourceID: Int] {
        var remaining = config.dailyIncomeCap
        var regular = 0
        var result: [IncomeSourceID: Int] = [:]
        for source in config.sources {
            var value = max(0, raw[source.id] ?? 0)
            if let cap = source.dailyCap { value = min(value, cap) }
            value = min(value, remaining)
            remaining -= value
            regular += value
            result[source.id] = value
        }
        result[config.bonus.id] = min(bonus(regular: regular, percent: bonusPercent, config: config), max(0, config.maxDailyIncome - regular))
        return result
    }

    public static func bonus(regular: Int, percent: Int, config: CurrencyConfig) -> Int {
        guard regular > 0, percent > 0 else { return 0 }
        let value = Int((Double(regular) * Double(percent) / 100).rounded())
        return min(config.bonusCap, max(0, value))
    }
}

public enum LedgerMath {
    public static func balance<S: Sequence>(_ transactions: S, through day: DayKey) -> Int where S.Element == Transaction {
        transactions.reduce(0) { $1.day <= day ? $0 + $1.amount : $0 }
    }

    public static func snapshot<S: Sequence>(_ transactions: S, today: DayKey, config: CurrencyConfig, recentDays: Int, calendar: Calendar) -> LedgerSnapshot where S.Element == Transaction {
        let keys = (0..<recentDays).map { today.adding(days: $0 - recentDays + 1, calendar: calendar) }
        let wanted = Set(keys)
        var balance = 0
        var earlier = 0
        var todays: [Transaction] = []
        var bySource: [DayKey: [IncomeSourceID: Int]] = [:]
        var bySegment: [DayKey: [String: Int]] = [:]
        var spentByDay: [DayKey: Int] = [:]
        var spentBySource: [DayKey: [String: Int]] = [:]
        for transaction in transactions {
            guard transaction.day <= today else { continue }
            balance += transaction.amount
            if transaction.day < today { earlier += transaction.amount } else { todays.append(transaction) }
            if wanted.contains(transaction.day) {
                switch transaction.kind {
                case .income:
                    let source = IncomeSourceID(transaction.sourceID)
                    bySource[transaction.day, default: [:]][source, default: 0] += transaction.amount
                    bySegment[transaction.day, default: [:]][config.segment(for: source), default: 0] += transaction.amount
                case .spend:
                    spentByDay[transaction.day, default: 0] += -transaction.amount
                    spentBySource[transaction.day, default: [:]][transaction.sourceID, default: 0] += -transaction.amount
                case .expiry: break
                }
            }
        }
        if earlier > 0 { bySegment[today, default: [:]][config.bonus.segment, default: 0] += earlier }
        return LedgerSnapshot(
            balance: balance,
            donut: donut(todays, earlier: earlier, config: config),
            recent: keys.map { DayStat(day: $0, incomeBySource: bySource[$0] ?? [:], incomeBySegment: bySegment[$0] ?? [:], spent: spentByDay[$0] ?? 0, spentBySource: spentBySource[$0] ?? [:]) }
        )
    }

    private static func donut(_ todays: [Transaction], earlier: Int, config: CurrencyConfig) -> [DonutSlice] {
        let ordered = todays.sorted { lhs, rhs in
            let lhsIncome = lhs.kind == .income
            if lhsIncome != (rhs.kind == .income) { return lhsIncome }
            return lhs.date < rhs.date
        }
        var lots: [(segment: String, minutes: Int)] = []
        if earlier > 0 { lots.append((config.bonus.segment, earlier)) }
        var spentBySegment: [String: Int] = [:]
        for transaction in ordered {
            switch transaction.kind {
            case .income:
                guard transaction.amount > 0 else { continue }
                lots.append((config.segment(for: IncomeSourceID(transaction.sourceID)), transaction.amount))
            case .spend, .expiry:
                var remaining = -transaction.amount
                var index = 0
                while remaining > 0, index < lots.count {
                    let taken = min(lots[index].minutes, remaining)
                    lots[index].minutes -= taken
                    remaining -= taken
                    if transaction.kind == .spend { spentBySegment[lots[index].segment, default: 0] += taken }
                    index += 1
                }
                lots.removeAll { $0.minutes == 0 }
            }
        }
        var left: [String: Int] = [:]
        for lot in lots { left[lot.segment, default: 0] += lot.minutes }
        var slices: [DonutSlice] = []
        for descriptor in config.descriptors where !slices.contains(where: { $0.segment == descriptor.segment }) {
            let spent = spentBySegment[descriptor.segment] ?? 0
            let remaining = left[descriptor.segment] ?? 0
            if spent > 0 { slices.append(DonutSlice(segment: descriptor.segment, tint: descriptor.tint, minutes: spent, isSpent: true)) }
            if remaining > 0 { slices.append(DonutSlice(segment: descriptor.segment, tint: descriptor.tint, minutes: remaining, isSpent: false)) }
        }
        return slices
    }

    public static func spendable(balance: Int, reservations: [Reservation], consumingReservationOf ownerID: String?) -> Int {
        let held = reservations.filter { $0.ownerID != ownerID }.reduce(0) { $0 + $1.minutes }
        return max(0, balance - held)
    }
}

public enum MinuteFormatter {
    public static func word(_ minutes: Int) -> String {
        switch abs(minutes) {
        case 1: "minuta"
        case 2...4: "minuty"
        default: "minut"
        }
    }

    public static func short(_ minutes: Int) -> String {
        "\(minutes) min"
    }

    public static func words(_ minutes: Int) -> String {
        "\(minutes) \(word(minutes))"
    }

    public static func number(_ value: Int) -> String {
        value.formatted(.number.locale(.czech))
    }

    public static func compact(_ minutes: Int) -> String {
        guard minutes >= 1000 else { return "\(minutes)" }
        let hundreds = minutes / 100
        let whole = hundreds / 10
        let tenth = hundreds % 10
        return tenth == 0 ? "\(whole)k" : "\(whole),\(tenth)k"
    }

    public static func string(_ minutes: Int) -> String {
        let value = max(0, minutes)
        if value < 60 { return short(value) }
        let hours = value / 60
        let rest = value % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(short(rest))"
    }

}
