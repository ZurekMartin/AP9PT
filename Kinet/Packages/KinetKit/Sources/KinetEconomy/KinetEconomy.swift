import ProfileFeature
import KinetCurrency
import PetFeature
import StudyFeature

public enum KinetEconomy {
    public static let currency = CurrencyConfig(
        dailyIncomeCap: 180,
        bonusCap: 63,
        carryoverCap: 120,
        sources: [
            IncomeSourceDescriptor(id: "study", title: "Studium", symbol: "book.fill", tint: "seaBlue", segment: "study", segmentTitle: "Studium", priority: 1, dailyCap: 120),
            IncomeSourceDescriptor(id: "workout", title: "Workout", symbol: "figure.run", tint: "coral", segment: "workout", segmentTitle: "Workout", priority: 2, dailyCap: nil),
            IncomeSourceDescriptor(id: "steps", title: "Kroky", symbol: "figure.walk", tint: "sage", segment: "steps", segmentTitle: "Kroky", priority: 3, dailyCap: nil)
        ],
        bonus: IncomeSourceDescriptor(id: "streakBonus", title: "Bonus za sérii", symbol: "flame.fill", tint: "sand", segment: "bonus", segmentTitle: "Bonus", priority: 4, dailyCap: nil),
        expiryTint: "mist",
        expiryTitle: "Rozplynulo se v moři",
        expirySymbol: "sparkle"
    )

    public static let stepsPerMinute = profile.stepsPerMinute
    public static let workoutMultiplier = profile.workoutMultiplier
    public static let dailyIncomeCap = currency.dailyIncomeCap
    public static let carryoverCap = currency.carryoverCap
    public static let studyDailyCap = currency.sources.first { $0.id == study.source }?.dailyCap ?? study.minuteRange.upperBound
    public static let restDaysPerWeek = profile.restDaysPerWeek
    public static let pomodoroCycleMinutes = study.cycleMinutes
    public static let breathMinutes = max(1, Int((study.breathSeconds / 60).rounded()))
    public static let maxRation = pet.rationRange.upperBound
    public static let stepsSegment = currency.segment(for: profile.stepsSource)
    public static let workoutSegment = currency.segment(for: profile.workoutSource)
    public static let studySegment = currency.segment(for: study.source)

    public static let demoOwnedItemIDs: Set<String> = [
        "seaweed", "starfish", "bubbler", "anemone", "glowMushroom", "moonstone", "shipwreck",
        "coralReef", "bioluminescence", "opalSkin", "sandSkin"
    ]

    public static let demoBalanceToday = demoPet.catalog.filter { !demoOwnedItemIDs.contains($0.id) }.reduce(0) { $0 + $1.price } + pet.maxDailyFeed + profile.restDayPrice
    public static let demoMaxBonus = demoBalanceToday - currency.dailyIncomeCap
    public static let demoMaxSteps = currency.dailyIncomeCap * profile.stepsPerMinute
    public static let demoMaxWorkout = currency.dailyIncomeCap / profile.workoutMultiplier
    public static let demoMaxStudy = study.minuteRange.upperBound

    public static let demoXP = LevelCurve.xpRequired(forLevel: pet.maxLevel, config: pet)

    public static var demoCurrency: CurrencyConfig {
        var config = currency
        config.bonusCap = demoMaxBonus
        return config
    }

    public static let profile = ProfileConfig(
        ownerID: "profile",
        stepsPerMinute: 100,
        workoutMultiplier: 2,
        streakPercentPerLevel: 5,
        streakMaxLevel: 7,
        streakMissPenalty: 2,
        defaultStepGoal: 5_000,
        stepGoalRange: 4_000...18_000,
        stepGoalStep: 500,
        restDayPrice: 20,
        restDaysPerWeek: 1,
        healthLookbackDays: 7,
        healthBackfillDays: 28,
        stepsSource: "steps",
        workoutSource: "workout",
        streakBonusSource: "streakBonus"
    )

    public static let study = StudyConfig(
        studyMinutes: 30,
        focusMinutes: 25,
        cycleMinutes: 30,
        inhaleSeconds: 4,
        exhaleSeconds: 6,
        breathSeconds: 60,
        restSeconds: 240,
        minuteRange: 1...120,
        demoTimeScale: 1.0 / 60.0,
        source: "study"
    )

    public static let pet = PetConfig(
        ownerID: "pet",
        maxDailyFeed: 120,
        defaultRation: 30,
        rationRange: 10...120,
        rationStep: 10,
        feedIncrement: 10,
        xpPerFedMinute: 1,
        xpPerBonusMinute: 2,
        bonusSourceID: "streakBonus",
        levelXPFactor: 35,
        maxLevel: 10,
        experiencesPerDay: 1,
        moodWeights: [0.5, 0.3, 0.2],
        moodThresholds: [0.20, 0.45, 0.70, 0.95],
        defaultNudgeMinuteOfDay: 20 * 60,
        sleepStartHour: 22,
        sleepEndHour: 6,
        moodVisuals: [
            .sleepy: MoodVisual(smile: 0.1, pulse: 0.32, glow: 0.22),
            .calm: MoodVisual(smile: 0.4, pulse: 0.48, glow: 0.4),
            .content: MoodVisual(smile: 0.65, pulse: 0.58, glow: 0.58),
            .happy: MoodVisual(smile: 0.9, pulse: 0.72, glow: 0.8),
            .radiant: MoodVisual(smile: 1.0, pulse: 0.88, glow: 1.0)
        ],
        catalog: [
            ShopItem(id: "lagoon", category: .theme, title: "Laguna", symbol: "water.waves", price: 0, requiredLevel: 1, isDefault: true),
            ShopItem(id: "coralSkin", category: .skin, title: "Tyrkysová", symbol: "drop.fill", price: 0, requiredLevel: 1, isDefault: true),
            ShopItem(id: "pebbles", category: .decor, title: "Oblázky", symbol: "circle.grid.2x2.fill", price: 30, requiredLevel: 1, placement: DecorPlacement(x: 0.34, y: 0.95, scale: 1.0, layer: 4)),
            ShopItem(id: "shells", category: .decor, title: "Mušle", symbol: "fossil.shell.fill", price: 40, requiredLevel: 1, placement: DecorPlacement(x: 0.15, y: 0.93, scale: 0.9, layer: 3)),
            ShopItem(id: "seaweed", category: .decor, title: "Mořská tráva", symbol: "leaf.fill", price: 50, requiredLevel: 1, placement: DecorPlacement(x: 0.12, y: 0.85, scale: 1.0, layer: 0)),
            ShopItem(id: "starfish", category: .decor, title: "Hvězdice", symbol: "star.fill", price: 60, requiredLevel: 2, placement: DecorPlacement(x: 0.22, y: 0.95, scale: 1.0, layer: 4)),
            ShopItem(id: "sageSkin", category: .skin, title: "Karamelová", symbol: "drop.fill", price: 60, requiredLevel: 2),
            ShopItem(id: "amphora", category: .decor, title: "Amfora", symbol: "wineglass.fill", price: 80, requiredLevel: 3, placement: DecorPlacement(x: 0.07, y: 0.92, scale: 0.9, layer: 1)),
            ShopItem(id: "sandSkin", category: .skin, title: "Břidlicová", symbol: "drop.fill", price: 80, requiredLevel: 4),
            ShopItem(id: "bubbler", category: .decor, title: "Bublinkovač", symbol: "bubbles.and.sparkles.fill", price: 90, requiredLevel: 3, placement: DecorPlacement(x: 0.26, y: 0.92, scale: 0.9, layer: 2)),
            ShopItem(id: "coralReef", category: .theme, title: "Korálový útes", symbol: "sun.haze.fill", price: 100, requiredLevel: 3),
            ShopItem(id: "coral", category: .decor, title: "Korál", symbol: "tree.fill", price: 110, requiredLevel: 4, placement: DecorPlacement(x: 0.84, y: 0.82, scale: 1.0, layer: 1)),
            ShopItem(id: "anemone", category: .decor, title: "Sasanka", symbol: "camera.macro", price: 120, requiredLevel: 4, placement: DecorPlacement(x: 0.86, y: 0.88, scale: 1.0, layer: 3)),
            ShopItem(id: "glowMushroom", category: .decor, title: "Svítící houba", symbol: "sparkle", price: 130, requiredLevel: 5, placement: DecorPlacement(x: 0.66, y: 0.90, scale: 0.8, layer: 2)),
            ShopItem(id: "polarDeep", category: .theme, title: "Polární hlubina", symbol: "snowflake", price: 130, requiredLevel: 5),
            ShopItem(id: "moonstone", category: .decor, title: "Měsíční kámen", symbol: "moon.fill", price: 150, requiredLevel: 6, placement: DecorPlacement(x: 0.55, y: 0.88, scale: 0.8, layer: 4)),
            ShopItem(id: "opalSkin", category: .skin, title: "Ametystová", symbol: "drop.fill", price: 150, requiredLevel: 7),
            ShopItem(id: "bioluminescence", category: .theme, title: "Bioluminiscence", symbol: "sparkles", price: 170, requiredLevel: 8),
            ShopItem(id: "chest", category: .decor, title: "Truhla s pokladem", symbol: "shippingbox.fill", price: 180, requiredLevel: 9, placement: DecorPlacement(x: 0.4, y: 0.80, scale: 0.95, layer: 1)),
            ShopItem(id: "shipwreck", category: .decor, title: "Vrak lodi", symbol: "sailboat.fill", price: 240, requiredLevel: 10, placement: DecorPlacement(x: 0.7, y: 0.80, scale: 1.3, layer: 0)),
            ShopItem(id: "warmCurrent", category: .experience, title: "Teplý proud", symbol: "wind", price: 15, requiredLevel: 1, xpReward: 10, moodBoost: 0.05),
            ShopItem(id: "lightShow", category: .experience, title: "Světelná show", symbol: "sparkles", price: 25, requiredLevel: 2, xpReward: 20, moodBoost: 0.10),
            ShopItem(id: "bubbleSky", category: .experience, title: "Bublinkové nebe", symbol: "bubbles.and.sparkles", price: 40, requiredLevel: 3, xpReward: 30, moodBoost: 0.15),
            ShopItem(id: "silverShoal", category: .experience, title: "Stříbrné hejno", symbol: "fish.fill", price: 60, requiredLevel: 5, xpReward: 45, moodBoost: 0.20)
        ]
    )

    public static var demoPet: PetConfig {
        var config = pet
        config.experiencesPerDay = .max
        return config
    }
}
