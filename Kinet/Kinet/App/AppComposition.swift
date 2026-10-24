import ProfileFeature
import Foundation
import KinetCurrency
import KinetDesign
import KinetEconomy
import Observation
import PetFeature
import StudyFeature
import SwiftData

@MainActor
@Observable
final class AppComposition {
    private struct Stack {
        let container: ModelContainer
        let wallet: Wallet
        let profile: ProfileModel
        let study: StudyModel
        let pet: PetModel
        let clock: OffsetClock?
        let wasReset: Bool
    }

    let preferences: AppPreferences
    let feedback: Feedback
    private var stack: Stack
    private(set) var isBusy = false

    var container: ModelContainer { stack.container }
    var wallet: Wallet { stack.wallet }
    var profile: ProfileModel { stack.profile }
    var study: StudyModel { stack.study }
    var pet: PetModel { stack.pet }
    var demoClock: OffsetClock? { stack.clock }
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored var isSeeding = false
    @ObservationIgnored private var lastRefresh: Date?
    @ObservationIgnored private var lastRefreshDay: DayKey?

    init() {
        let preferences = AppPreferences(defaults: .standard)
        let feedback = Feedback(defaults: .standard)
        let stack = Self.makeStack(preferences: preferences, feedback: feedback)
        if stack.wasReset && preferences.isDemoMode { preferences.demoSeeded = false }
        self.preferences = preferences
        self.feedback = feedback
        self.stack = stack
    }

    func setBusy(_ value: Bool) {
        isBusy = value
    }

    func refreshAll(force: Bool = false) async {
        guard !isSeeding else { return }
        await refresh(force: force)
    }

    func refreshForSeeding() async {
        while isRefreshing { try? await Task.sleep(for: .milliseconds(20)) }
        await refresh(force: true)
    }

    private func refresh(force: Bool) async {
        guard !isRefreshing else { return }
        let now = Date()
        if !force, let lastRefresh, now.timeIntervalSince(lastRefresh) < 10, lastRefreshDay == DayKey(date: wallet.now, calendar: wallet.calendar) { return }
        isRefreshing = true
        defer { isRefreshing = false }
        wallet.refresh()
        await profile.refresh()
        try? study.resumeIfNeeded()
        if await wallet.closePendingDays() { await profile.refresh() }
        await pet.refresh()
        wallet.refresh()
        lastRefresh = now
        lastRefreshDay = wallet.today
    }

    func requestPermissions() async {
        guard !preferences.permissionsAsked else { return }
        preferences.permissionsAsked = true
        await profile.requestHealthAccess()
        await pet.requestNotificationAccess()
    }

    func setDemoMode(_ enabled: Bool) async {
        guard enabled != preferences.isDemoMode else { return }
        if !enabled {
            setBusy(true)
            wallet.save()
            UserDefaults.standard.removeObject(forKey: "profile.backfilled")
            preferences.isDemoMode = false
            rebuild()
            await refreshAll(force: true)
            setBusy(false)
            return
        }
        preferences.isDemoMode = enabled
        wallet.save()
        rebuild()
        if enabled && (!preferences.demoSeeded || ledgerIsEmpty) {
            await seedDemo()
        } else {
            await refreshAll(force: true)
        }
    }

    private var ledgerIsEmpty: Bool {
        ((try? container.mainContext.fetchCount(FetchDescriptor<LedgerEntry>())) ?? 0) == 0
    }

    func resetDemo() async {
        guard preferences.isDemoMode else { return }
        preferences.demoSeeded = false
        await seedDemo()
    }

    func resetStoreForSeeding() {
        container.deleteAllData()
        rebuild()
    }

    private func rebuild() {
        stack = Self.makeStack(preferences: preferences, feedback: feedback)
    }

    private static func openContainer(named name: String, schema: Schema) -> (container: ModelContainer, wasReset: Bool) {
        let configuration = ModelConfiguration(name, schema: schema)
        if let loaded = try? ModelContainer(for: schema, configurations: configuration) { return (loaded, false) }
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: configuration.url.path + suffix))
        }
        let recreated = (try? ModelContainer(for: schema, configurations: ModelConfiguration(name, schema: schema)))
            ?? (try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        return (recreated, true)
    }

    private static func makeStack(preferences: AppPreferences, feedback: Feedback) -> Stack {
        let isDemo = preferences.isDemoMode
        let schema = Schema([
            LedgerEntry.self, RawIncomeRecord.self, DayCloseRecord.self,
            ActivityRecord.self, StreakDay.self, StudySessionRecord.self, AquariumState.self
        ])
        let (container, wasReset) = openContainer(named: isDemo ? "kinet-demo" : "kinet", schema: schema)
        let calendar = Calendar.kinet
        let clock = isDemo ? OffsetClock(dayOffset: 0, calendar: calendar) : nil
        let kinetClock: any KinetClock = clock ?? SystemClock()
        let context = container.mainContext
        let wallet = Wallet(context: context, clock: kinetClock, calendar: calendar, config: isDemo ? KinetEconomy.demoCurrency : KinetEconomy.currency)
        let profile = ProfileModel(
            context: context,
            wallet: wallet,
            source: isDemo ? DemoActivitySource() : HealthKitActivitySource(),
            settings: ProfileSettings(defaults: .standard, config: KinetEconomy.profile),
            feedback: feedback,
            config: KinetEconomy.profile
        )
        let study = StudyModel(context: context, wallet: wallet, feedback: feedback, config: KinetEconomy.study)
        study.isDemo = isDemo
        let scheduler: any NudgeScheduling = NudgeScheduler()
        let petConfig = isDemo ? KinetEconomy.demoPet : KinetEconomy.pet
        let pet = PetModel(
            context: context,
            wallet: wallet,
            settings: PetSettings(defaults: .standard, config: petConfig),
            scheduler: scheduler,
            feedback: feedback,
            config: petConfig
        )
        pet.isDemo = isDemo
        wallet.register(profile)
        wallet.register(pet)
        return Stack(container: container, wallet: wallet, profile: profile, study: study, pet: pet, clock: clock, wasReset: wasReset)
    }
}
