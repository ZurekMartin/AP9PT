import Foundation
import KinetCurrency
import KinetDesign
import Observation
import SwiftData
import UserNotifications

public enum ShopCategory: String, Codable, Sendable, CaseIterable {
    case decor, theme, skin, experience

    public var title: String {
        switch self {
        case .decor: "Dekorace"
        case .theme: "Prostředí"
        case .skin: "Medúza"
        case .experience: "Zážitky"
        }
    }
}

public struct DecorPlacement: Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let scale: Double
    public let layer: Int

    public init(x: Double, y: Double, scale: Double, layer: Int) {
        self.x = x
        self.y = y
        self.scale = scale
        self.layer = layer
    }
}

public struct ShopItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let category: ShopCategory
    public let title: String
    public let symbol: String
    public let price: Int
    public let requiredLevel: Int
    public let xpReward: Int
    public let moodBoost: Double
    public let placement: DecorPlacement?
    public let isDefault: Bool

    public init(id: String, category: ShopCategory, title: String, symbol: String, price: Int, requiredLevel: Int, xpReward: Int = 0, moodBoost: Double = 0, placement: DecorPlacement? = nil, isDefault: Bool = false) {
        self.id = id
        self.category = category
        self.title = title
        self.symbol = symbol
        self.price = price
        self.requiredLevel = requiredLevel
        self.xpReward = xpReward
        self.moodBoost = moodBoost
        self.placement = placement
        self.isDefault = isDefault
    }
}

public struct PetConfig: Sendable, Equatable {
    public var ownerID: String
    public var maxDailyFeed: Int
    public var defaultRation: Int
    public var rationRange: ClosedRange<Int>
    public var rationStep: Int
    public var feedIncrement: Int
    public var xpPerFedMinute: Int
    public var xpPerBonusMinute: Int
    public var bonusSourceID: String
    public var levelXPFactor: Int
    public var maxLevel: Int
    public var experiencesPerDay: Int
    public var moodWeights: [Double]
    public var moodThresholds: [Double]
    public var defaultNudgeMinuteOfDay: Int
    public var sleepStartHour: Int
    public var sleepEndHour: Int
    public var moodVisuals: [Mood: MoodVisual]
    public var catalog: [ShopItem]

    public init(ownerID: String, maxDailyFeed: Int, defaultRation: Int, rationRange: ClosedRange<Int>, rationStep: Int, feedIncrement: Int, xpPerFedMinute: Int, xpPerBonusMinute: Int, bonusSourceID: String, levelXPFactor: Int, maxLevel: Int, experiencesPerDay: Int, moodWeights: [Double], moodThresholds: [Double], defaultNudgeMinuteOfDay: Int, sleepStartHour: Int, sleepEndHour: Int, moodVisuals: [Mood: MoodVisual], catalog: [ShopItem]) {
        self.ownerID = ownerID
        self.maxDailyFeed = maxDailyFeed
        self.defaultRation = defaultRation
        self.rationRange = rationRange
        self.rationStep = rationStep
        self.feedIncrement = feedIncrement
        self.xpPerFedMinute = xpPerFedMinute
        self.xpPerBonusMinute = xpPerBonusMinute
        self.bonusSourceID = bonusSourceID
        self.levelXPFactor = levelXPFactor
        self.maxLevel = maxLevel
        self.experiencesPerDay = experiencesPerDay
        self.moodWeights = moodWeights
        self.moodThresholds = moodThresholds
        self.defaultNudgeMinuteOfDay = defaultNudgeMinuteOfDay
        self.sleepStartHour = sleepStartHour
        self.sleepEndHour = sleepEndHour
        self.moodVisuals = moodVisuals
        self.catalog = catalog.enumerated().sorted { ($0.element.price, $0.offset) < ($1.element.price, $1.offset) }.map(\.element)
    }

    public func item(_ id: String) -> ShopItem? {
        catalog.first { $0.id == id }
    }
}

@Model
public final class AquariumState {
    @Attribute(.unique) public var singletonKey: String = "main"
    public var activeThemeID: String
    public var activeSkinID: String
    public var hiddenDecorIDs: [String]
    public var lastSeenLevel: Int
    public var ration: Int

    public init(defaultThemeID: String, defaultSkinID: String, ration: Int) {
        self.singletonKey = "main"
        self.activeThemeID = defaultThemeID
        self.activeSkinID = defaultSkinID
        self.hiddenDecorIDs = []
        self.lastSeenLevel = 1
        self.ration = ration
    }
}

public enum Mood: String, Sendable, CaseIterable, Codable, Comparable {
    case sleepy, calm, content, happy, radiant

    public var title: String {
        switch self {
        case .sleepy: "Ospalá"
        case .calm: "Klidná"
        case .content: "Spokojená"
        case .happy: "Šťastná"
        case .radiant: "Zářivá"
        }
    }

    var rank: Int { Mood.allCases.firstIndex(of: self) ?? 0 }

    public static func < (lhs: Mood, rhs: Mood) -> Bool { lhs.rank < rhs.rank }
}

public struct MoodVisual: Sendable, Equatable {
    public let smile: Double
    public let pulse: Double
    public let glow: Double

    public init(smile: Double, pulse: Double, glow: Double) {
        self.smile = smile
        self.pulse = pulse
        self.glow = glow
    }
}

public struct JellyfishVitals: Sendable, Equatable {
    public let moodScore: Double
    public let mood: Mood
    public let xp: Int
    public let level: Int
    public let xpIntoLevel: Int
    public let xpForNextLevel: Int?
}

public enum JellyfishCare {
    public static func moodScore(fedToday: Int, fedYesterday: Int, fedDayBefore: Int, experienceBoostToday: Double, config: PetConfig) -> Double {
        let cap = Double(max(1, config.maxDailyFeed))
        let weights = config.moodWeights
        let today = Double(max(fedToday, fedYesterday))
        let base = weights[0] * today / cap + weights[1] * Double(fedYesterday) / cap + weights[2] * Double(fedDayBefore) / cap
        return min(1, base + experienceBoostToday)
    }

    public static func mood(for score: Double, config: PetConfig) -> Mood {
        let index = config.moodThresholds.filter { score >= $0 }.count
        return Mood.allCases[min(index, Mood.allCases.count - 1)]
    }

    public static func xp(fedMinutes: Int, bonusMinutes: Int, experienceXP: Int, config: PetConfig) -> Int {
        fedMinutes * config.xpPerFedMinute + bonusMinutes * config.xpPerBonusMinute + experienceXP
    }

    public static let tentacleCount = 7
}

public enum LevelCurve {
    public static func xpRequired(forLevel level: Int, config: PetConfig) -> Int {
        config.levelXPFactor * level * (level - 1)
    }

    public static func level(forXP xp: Int, config: PetConfig) -> Int {
        var level = 1
        while level < config.maxLevel, xp >= xpRequired(forLevel: level + 1, config: config) { level += 1 }
        return level
    }
}

public enum FeedRules {
    public static func maxFeedable(balance: Int, fedToday: Int, config: PetConfig) -> Int {
        max(0, min(balance, config.maxDailyFeed - fedToday))
    }

    public static func reservation(ration: Int, fedToday: Int) -> Int {
        max(0, ration - fedToday)
    }

    public static func autoFeed(ration: Int, fedOnDay: Int, balance: Int, config: PetConfig) -> Int {
        max(0, min(max(0, ration - fedOnDay), balance, config.maxDailyFeed - fedOnDay))
    }
}

public struct PurchaseContext: Sendable, Equatable {
    public let spendable: Int
    public let level: Int
    public let ownedIDs: Set<String>
    public let experiencesToday: Int
    public let experiencesPerDay: Int
}

public enum PurchaseError: Error, Equatable, Sendable {
    case levelTooLow(required: Int)
    case alreadyOwned
    case dailyExperienceLimit
    case spend(SpendError)
}

public enum PurchaseRules {
    public static func validate(_ item: ShopItem, context: PurchaseContext) throws(PurchaseError) {
        if context.level < item.requiredLevel { throw .levelTooLow(required: item.requiredLevel) }
        if item.category == .experience {
            if context.experiencesToday >= context.experiencesPerDay { throw .dailyExperienceLimit }
        } else if context.ownedIDs.contains(item.id) {
            throw .alreadyOwned
        }
    }
}

public struct Nudge: Sendable, Equatable {
    public let day: DayKey
    public let available: Int
    public let ration: Int
    public let title: String
    public let body: String
}

public enum NudgePlanner {
    public static func nudge(day: DayKey, fedToday: Int, balance: Int, ration: Int, isEnabled: Bool) -> Nudge? {
        guard isEnabled, fedToday + balance < ration else { return nil }
        let available = fedToday + max(0, balance)
        let variant = (day.month * 31 + day.day) % 3
        let title: String
        let body: String
        switch variant {
        case 0:
            title = "Medúza se chystá ke spánku"
            body = "Na noc má připraveno \(available) z \(ration) minut. Zítra stačí krátká procházka a bude zase zářit."
        case 1:
            title = "Klidný večer v akváriu"
            body = "Dnes to bylo \(available) z \(ration) minut. Zítra spolu doplaveme víc."
        default:
            title = "Kinet tě zdraví"
            body = "Medúza je v pohodě, jen by zítra ráda pár minut navíc. Třeba při procházce?"
        }
        return Nudge(day: day, available: available, ration: ration, title: title, body: body)
    }
}

@MainActor
public protocol NudgeScheduling {
    func requestAuthorization() async -> Bool
    func isDenied() async -> Bool
    func reschedule(_ nudge: Nudge?, minuteOfDay: Int, calendar: Calendar) async
}

public struct NudgeScheduler: NudgeScheduling {
    public init() {}

    public func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    public func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    public func reschedule(_ nudge: Nudge?, minuteOfDay: Int, calendar: Calendar) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("nudge.") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard let nudge, calendar.isDateInToday(nudge.day.startDate(in: calendar)) else { return }
        var parts = DateComponents()
        parts.year = nudge.day.year
        parts.month = nudge.day.month
        parts.day = nudge.day.day
        parts.hour = minuteOfDay / 60
        parts.minute = minuteOfDay % 60
        guard let fire = calendar.date(from: parts), fire > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = nudge.title
        content.body = nudge.body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "nudge.\(nudge.day.id)", content: content, trigger: trigger))
    }
}

@MainActor
@Observable
public final class PetSettings {
    public var notificationsEnabled: Bool {
        didSet { store.save(notificationsEnabled, "pet.notifications") }
    }
    public var nudgeMinuteOfDay: Int {
        didSet { store.save(nudgeMinuteOfDay, "pet.nudgeMinute") }
    }
    public var demoXPOffset: Int {
        didSet { store.save(demoXPOffset, "pet.demoXPOffset") }
    }

    @ObservationIgnored private let store: SettingsStore

    public init(defaults: UserDefaults, config: PetConfig) {
        store = SettingsStore(defaults)
        notificationsEnabled = store.value("pet.notifications", default: true)
        nudgeMinuteOfDay = store.value("pet.nudgeMinute", default: config.defaultNudgeMinuteOfDay)
        demoXPOffset = store.value("pet.demoXPOffset", default: 0)
    }
}

public enum PetEvent: Equatable {
    case levelUp(Int)
    case experience(String)
    case fed(Int)
}
