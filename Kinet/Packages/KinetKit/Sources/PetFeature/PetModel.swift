import Foundation
import KinetCurrency
import KinetDesign
import Observation
import SwiftData

typealias Transaction = KinetCurrency.Transaction

@MainActor
@Observable
public final class PetModel: DayCloseParticipant {
    public private(set) var vitals: JellyfishVitals
    public private(set) var fedToday: Int = 0
    public private(set) var ration: Int
    public private(set) var maxFeedableNow: Int = 0
    public private(set) var ownedIDs: Set<String> = []
    public private(set) var experiencesToday: Int = 0
    public private(set) var activeThemeID: String
    public private(set) var activeSkinID: String
    public private(set) var hiddenDecorIDs: Set<String> = []
    public private(set) var lastEvent: PetEvent?
    public private(set) var feedToken = 0
    public private(set) var lastFeedAmount = 0
    public var isDemo = false
    public var demoMoodOverride: Mood?

    public var demoSleepOverride: Bool?

    public var effectiveMood: Mood {
        demoMoodOverride ?? vitals.mood
    }

    public private(set) var isNightTime: Bool = false

    public var isSleepingTime: Bool {
        demoSleepOverride ?? isNightTime
    }
    public let settings: PetSettings
    public let config: PetConfig
    public let closeOrder: Int = 20

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let wallet: Wallet
    @ObservationIgnored private let scheduler: any NudgeScheduling
    @ObservationIgnored private let feedback: Feedback
    @ObservationIgnored private let state: AquariumState
    @ObservationIgnored private var scheduledNudge: Nudge??
    @ObservationIgnored private var scheduledMinute: Int?
    @ObservationIgnored private var clockTask: Task<Void, Never>?

    public init(context: ModelContext, wallet: Wallet, settings: PetSettings, scheduler: any NudgeScheduling, feedback: Feedback, config: PetConfig) {
        self.context = context
        self.wallet = wallet
        self.settings = settings
        self.scheduler = scheduler
        self.feedback = feedback
        self.config = config
        let existing = try? context.fetch(FetchDescriptor<AquariumState>()).first
        let theme = config.catalog.first { $0.category == .theme && $0.isDefault }?.id ?? ""
        let skin = config.catalog.first { $0.category == .skin && $0.isDefault }?.id ?? ""
        let state = existing ?? AquariumState(defaultThemeID: theme, defaultSkinID: skin, ration: config.defaultRation)
        if existing == nil {
            context.insert(state)
            context.saveIfNeeded()
        }
        self.state = state
        self.ration = state.ration
        self.activeThemeID = state.activeThemeID
        self.activeSkinID = state.activeSkinID
        self.hiddenDecorIDs = Set(state.hiddenDecorIDs)
        self.vitals = JellyfishVitals(moodScore: 0, mood: .sleepy, xp: 0, level: 1, xpIntoLevel: 0, xpForNextLevel: nil)
        recompute()
        updateNight()
        startClock()
    }

    private func startClock() {
        guard clockTask == nil else { return }
        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.tickNight() else { return }
                try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(2))
            }
        }
    }

    private func tickNight() -> Double {
        updateNight()
        return 60.5 - Double(wallet.calendar.component(.second, from: wallet.now))
    }

    private func updateNight() {
        let hour = wallet.calendar.component(.hour, from: wallet.now)
        let night = hour >= config.sleepStartHour || hour < config.sleepEndHour
        assign(\.isNightTime, night)
    }

    public var rawXP: Int {
        let scan = scanLedger()
        return JellyfishCare.xp(fedMinutes: scan.totalFed, bonusMinutes: wallet.income(sourceID: config.bonusSourceID), experienceXP: scan.experienceXP, config: config)
    }

    public func setDemoXP(_ target: Int) {
        guard isDemo else { return }
        settings.demoXPOffset = target - rawXP
        recompute()
    }

    public func refresh() async {
        if settings.notificationsEnabled, await scheduler.isDenied() { settings.notificationsEnabled = false }
        updateNight()
        recompute()
        updateReservation()
        await scheduleNudge()
    }

    public func feed(minutes: Int, announce: Bool = true) throws(SpendError) {
        let amount = min(minutes, config.maxDailyFeed - fedToday)
        guard amount > 0 else { throw .invalidAmount }
        try wallet.spend(SpendRequest(
            ownerID: config.ownerID,
            sourceID: "feed",
            amount: amount,
            title: "Krmení",
            symbol: "drop.fill",
            tint: "coral",
            consumesReservationOf: config.ownerID
        ))
        if announce {
            lastFeedAmount = amount
            feedToken += 1
            feedback.play(.bubbles)
        }
        afterChange(event: announce ? .fed(amount) : nil)
    }

    public func setRation(_ minutes: Int) {
        let clamped = min(max(minutes, config.rationRange.lowerBound), config.rationRange.upperBound)
        state.ration = clamped
        context.saveIfNeeded()
        afterChange(event: nil)
    }

    public func purchase(_ itemID: String) throws(PurchaseError) {
        guard let item = config.item(itemID) else { return }
        try PurchaseRules.validate(item, context: purchaseContext())
        let isExperience = item.category == .experience
        let prefix = switch item.category {
        case .decor: "Dekorace: "
        case .theme: "Prostředí: "
        case .skin: "Vzhled: "
        case .experience: "Zážitek: "
        }
        do {
            try wallet.spend(SpendRequest(
                ownerID: config.ownerID,
                sourceID: isExperience ? "experience" : item.category.rawValue,
                amount: item.price,
                title: prefix + item.title,
                symbol: isExperience ? "sparkles" : item.symbol,
                tint: "sand",
                itemID: item.id
            ))
        } catch {
            throw .spend(error)
        }
        switch item.category {
        case .theme: state.activeThemeID = item.id
        case .skin: state.activeSkinID = item.id
        default: break
        }
        context.saveIfNeeded()
        feedback.play(.purchase)
        if isExperience { feedback.play(Self.experienceCue(item.id)) }
        afterChange(event: isExperience ? .experience(item.id) : nil)
    }

    private static func experienceCue(_ id: String) -> HapticEvent {
        switch id {
        case "warmCurrent": .experienceWarm
        case "lightShow": .experienceLight
        case "bubbleSky": .experienceBubbles
        default: .experienceShoal
        }
    }

    public func setTheme(_ id: String) {
        guard ownedIDs.contains(id) else { return }
        state.activeThemeID = id
        context.saveIfNeeded()
        afterChange(event: nil)
    }

    public func setSkin(_ id: String) {
        guard ownedIDs.contains(id) else { return }
        state.activeSkinID = id
        context.saveIfNeeded()
        afterChange(event: nil)
    }

    public func setDecor(_ id: String, hidden: Bool) {
        var ids = Set(state.hiddenDecorIDs)
        if hidden { ids.insert(id) } else { ids.remove(id) }
        state.hiddenDecorIDs = Array(ids)
        context.saveIfNeeded()
        afterChange(event: nil)
    }

    public func requestNotificationAccess() async {
        settings.notificationsEnabled = await scheduler.requestAuthorization()
        await refresh()
    }

    public func setNotifications(enabled: Bool) async {
        if enabled {
            settings.notificationsEnabled = await scheduler.requestAuthorization()
        } else {
            settings.notificationsEnabled = false
        }
        await refresh()
    }

    public func consumeEvent() {
        lastEvent = nil
    }

    public func prepare(days: [DayKey]) async {}

    public func close(day: DayKey, in wallet: Wallet) {
        let fed = fedAmount(on: day, in: wallet.transactions(ownerID: config.ownerID))
        let amount = FeedRules.autoFeed(ration: state.ration, fedOnDay: fed, balance: wallet.balance(through: day), config: config)
        guard amount > 0 else { return }
        wallet.recordDeterministicSpend(SpendRequest(
            ownerID: config.ownerID,
            sourceID: "feed",
            amount: amount,
            title: "Večerní krmení",
            symbol: "moon.fill",
            tint: "coral"
        ), day: day)
    }

    private func afterChange(event: PetEvent?) {
        recompute()
        updateReservation()
        if let event {
            if case .levelUp = lastEvent {} else { lastEvent = event }
        }
        Task { await scheduleNudge() }
    }

    private func fedAmount(on day: DayKey, in transactions: [Transaction]) -> Int {
        -transactions.filter { $0.day == day && $0.sourceID == "feed" }.reduce(0) { $0 + $1.amount }
    }

    private func purchaseContext() -> PurchaseContext {
        PurchaseContext(
            spendable: wallet.spendable(for: nil),
            level: vitals.level,
            ownedIDs: ownedIDs,
            experiencesToday: experiencesToday,
            experiencesPerDay: isDemo ? Int.max : config.experiencesPerDay
        )
    }

    private struct LedgerScan {
        var fed: [DayKey: Int] = [:]
        var totalFed = 0
        var experienceXP = 0
        var boost = 0.0
        var experiencesNow = 0
        var owned: Set<String> = []
    }

    private func scanLedger() -> LedgerScan {
        let today = wallet.today
        let dayBefore = today.adding(days: -2, calendar: wallet.calendar)
        var scan = LedgerScan(owned: Set(config.catalog.filter(\.isDefault).map(\.id)))
        for transaction in wallet.transactions(ownerID: config.ownerID) {
            switch transaction.sourceID {
            case "feed":
                scan.totalFed -= transaction.amount
                if transaction.day >= dayBefore { scan.fed[transaction.day, default: 0] -= transaction.amount }
            case "experience":
                let item = config.item(transaction.itemID ?? "")
                scan.experienceXP += item?.xpReward ?? 0
                if transaction.day == today {
                    scan.boost += item?.moodBoost ?? 0
                    scan.experiencesNow += 1
                }
            default:
                if transaction.kind == .spend, let id = transaction.itemID { scan.owned.insert(id) }
            }
        }
        return scan
    }

    private func recompute() {
        if UserDefaults.standard.string(forKey: "pet.activeThemeID") != state.activeThemeID {
            UserDefaults.standard.set(state.activeThemeID, forKey: "pet.activeThemeID")
        }
        let today = wallet.today
        let yesterday = today.adding(days: -1, calendar: wallet.calendar)
        let dayBefore = today.adding(days: -2, calendar: wallet.calendar)
        let scan = scanLedger()
        let fed = scan.fed
        let totalFed = scan.totalFed
        let experienceXP = scan.experienceXP
        let boost = scan.boost
        let experiencesNow = scan.experiencesNow
        let owned = scan.owned
        let fedNow = fed[today] ?? 0
        assign(\.fedToday, fedNow)
        assign(\.experiencesToday, experiencesNow)
        assign(\.ownedIDs, owned)

        let score = JellyfishCare.moodScore(fedToday: fedNow, fedYesterday: fed[yesterday] ?? 0, fedDayBefore: fed[dayBefore] ?? 0, experienceBoostToday: boost, config: config)
        let bonusXP = wallet.income(sourceID: config.bonusSourceID)
        let xp = max(0, JellyfishCare.xp(fedMinutes: totalFed, bonusMinutes: bonusXP, experienceXP: experienceXP, config: config) + (isDemo ? settings.demoXPOffset : 0))
        let level = LevelCurve.level(forXP: xp, config: config)
        let currentFloor = LevelCurve.xpRequired(forLevel: level, config: config)
        let next = level < config.maxLevel ? LevelCurve.xpRequired(forLevel: level + 1, config: config) - currentFloor : nil
        let nextVitals = JellyfishVitals(
            moodScore: score,
            mood: JellyfishCare.mood(for: score, config: config),
            xp: xp,
            level: level,
            xpIntoLevel: xp - currentFloor,
            xpForNextLevel: next
        )
        assign(\.vitals, nextVitals)
        if level > state.lastSeenLevel {
            state.lastSeenLevel = level
            context.saveIfNeeded()
            lastEvent = .levelUp(level)
        }
        assign(\.ration, state.ration)
        assign(\.activeThemeID, state.activeThemeID)
        assign(\.activeSkinID, state.activeSkinID)
        let hidden = Set(state.hiddenDecorIDs)
        assign(\.hiddenDecorIDs, hidden)
        let feedable = FeedRules.maxFeedable(balance: wallet.balance, fedToday: fedNow, config: config)
        assign(\.maxFeedableNow, feedable)
    }

    private func updateReservation() {
        wallet.reserve(Reservation(
            ownerID: config.ownerID,
            title: "Porce medúzy",
            minutes: FeedRules.reservation(ration: ration, fedToday: fedToday)
        ))
    }

    private func scheduleNudge() async {
        let nudge = NudgePlanner.nudge(day: wallet.today, fedToday: fedToday, balance: wallet.balance, ration: ration, isEnabled: settings.notificationsEnabled)
        let minute = settings.nudgeMinuteOfDay
        if let scheduledNudge, scheduledNudge == nudge, scheduledMinute == minute { return }
        scheduledNudge = .some(nudge)
        scheduledMinute = minute
        await scheduler.reschedule(nudge, minuteOfDay: minute, calendar: wallet.calendar)
    }
}

extension PetModel: ChangeGuarding {}
