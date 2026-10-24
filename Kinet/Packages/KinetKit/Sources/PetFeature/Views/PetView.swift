import KinetCurrency
import KinetDesign
import SwiftUI

public struct PetView: View {
    @Environment(PetModel.self) private var model
    @Environment(Feedback.self) private var feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pageActive) private var pageActive
    @State private var sim = JellyfishSimulation()
    @State private var reactions = DecorReactions()
    @State private var life = AquariumLife()
    @State private var lastTap: (point: CGPoint, time: Date)?
    @State private var experienceID: String?
    @State private var experienceStart = Date()
    @State private var levelBanner: Int?
    @State private var isEngaged = false
    @State private var engageToken = 0
    @State private var engagedUntil = Date.distantPast

    public init() {}

    public var body: some View {
        ZStack {
            AquariumScene(sceneState: sceneState, sim: sim, life: life, reactions: reactions, onTap: { location, depth in
                handleTap(location, depth: depth)
            }, onDecor: { _, point, depth in
                feedback.play(.decorTap)
                sim.callToDecor(at: Vec(point.x, point.y), depth: depth)
                engage(8)
            })
            VStack(spacing: 10) {
                MoodBar()
                    .guideTarget("mood")
                    .padding(.horizontal, KinetLayout.pageMargin)
                if model.isDemo {
                    DemoAquariumPanel(sim: sim, engage: { engage(3) })
                        .padding(.horizontal, KinetLayout.pageMargin)
                }
                Spacer()
            }
            VStack(spacing: 0) {
                Color.clear.frame(height: 150)
                Color.clear.frame(maxHeight: .infinity).padding(.horizontal, 12).guideTarget("aquarium")
                Color.clear.frame(height: 150)
            }
            .allowsHitTesting(false)
            if let level = levelBanner {
                LevelBanner(level: level)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.55, bounce: 0.25), value: levelBanner)
        .onChange(of: model.lastEvent, initial: true) { _, event in handle(event) }
        .onChange(of: pageActive) { _, active in
            if active, levelBanner != nil { feedback.play(.levelUp) }
        }
        .onChange(of: experienceID, initial: true) { _, id in sim.depthLocked = id != nil }
        .task(id: experienceID.map { "\($0).\(experienceStart.timeIntervalSinceReferenceDate)" }) {
            guard let id = experienceID else { return }
            try? await Task.sleep(for: .seconds(ExperienceTiming.duration(for: id)))
            if !Task.isCancelled { withAnimation(.smooth(duration: 0.8)) { experienceID = nil } }
        }
        .onChange(of: model.feedToken) { _, _ in
            sim.dropFood(count: min(12, max(1, (model.lastFeedAmount + 9) / 10)))
            sim.thrustBoost = 1
            engage(15)
        }
        .task(id: engageToken) {
            guard isEngaged else { return }
            try? await Task.sleep(for: .seconds(max(0, engagedUntil.timeIntervalSinceNow)))
            if !Task.isCancelled { isEngaged = false }
        }
    }

    private func engage(_ seconds: Double) {
        engagedUntil = max(engagedUntil, Date().addingTimeInterval(seconds))
        if !isEngaged { isEngaged = true }
        engageToken &+= 1
    }

    private var sceneState: SceneState {
        let displayMood = experienceID == nil ? model.effectiveMood : Mood.radiant
        let scale = 1.05
        let visual = model.config.moodVisuals[displayMood] ?? MoodVisual(smile: 0.5, pulse: 0.48, glow: 0.4)
        let decor = model.config.catalog
            .filter { $0.category == .decor && model.ownedIDs.contains($0.id) && !model.hiddenDecorIDs.contains($0.id) }
            .compactMap { item in item.placement.map { DecorEntry(id: item.id, placement: $0) } }
        return SceneState(
            appearance: JellyfishAppearance(
                skinID: model.activeSkinID,
                mood: displayMood,
                scale: scale,
                tentacles: JellyfishCare.tentacleCount,
                glow: visual.glow
            ),
            parameters: SimParameters(
                scale: scale,
                frequency: visual.pulse,
                tentacles: JellyfishCare.tentacleCount,
                reduceMotion: reduceMotion,
                smile: visual.smile,
                sleepy: displayMood == .sleepy,
                sleeping: model.isSleepingTime && experienceID == nil
            ),
            themeID: model.activeThemeID,
            decor: decor,
            experience: experienceID.map { SceneExperience(id: $0, start: experienceStart) },
            isEngaged: isEngaged
        )
    }

    private func handleTap(_ location: CGPoint, depth: Double) {
        let point = Vec(location.x, location.y)
        if sim.distanceToBody(point) < 85 * sim.effectiveScale {
            sim.poke()
            feedback.play(.jellyTouch)
            sim.spawnBubbles(at: point, count: 3)
            engage(4)
        } else {
            let now = Date()
            var isDouble = false
            if let lastTap, now.timeIntervalSince(lastTap.time) < 0.7, hypot(lastTap.point.x - location.x, lastTap.point.y - location.y) < 48 {
                isDouble = true
            }
            lastTap = isDouble ? nil : (location, now)
            sim.steer(to: point, depth: depth, turbo: isDouble)
            sim.spawnBubbles(at: point, count: isDouble ? 9 : 5)
            feedback.play(.waterTap)
            engage(8)
        }
    }

    private func handle(_ event: PetEvent?) {
        guard let event else { return }
        switch event {
        case .levelUp(let level):
            levelBanner = level
            if pageActive { feedback.play(.levelUp) }
            Task {
                try? await Task.sleep(for: .seconds(3))
                levelBanner = nil
            }
        case .experience(let id):
            experienceStart = Date()
            withAnimation(.smooth(duration: 0.8)) { experienceID = id }
        case .fed:
            break
        }
        model.consumeEvent()
    }
}

struct LevelBanner: View {
    @Environment(\.appTheme) private var theme
    let level: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Palette.sand)
                .frame(width: 52, height: 52)
                .background(Palette.sand.opacity(0.18), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("Úroveň \(level)")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Palette.ink)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 28)
        .padding(.vertical, 16)
        .background(.black.opacity(0.28), in: .rect(cornerRadius: 30, style: .continuous))
        .glassEffect(.regular.tint(theme.water.opacity(0.3)), in: .rect(cornerRadius: 30))
    }
}

struct DemoAquariumPanel: View {
    @Environment(\.appTheme) private var theme
    @Environment(PetModel.self) private var model
    let sim: JellyfishSimulation
    let engage: () -> Void
    @State private var index = 0

    private struct Entry {
        let title: String
        let mood: Mood?
        let expression: JellyfishSimulation.Expression?
        var sleeping = false
    }

    private static let entries: [Entry] = [
        Entry(title: "Automaticky", mood: nil, expression: nil),
        Entry(title: "Spící", mood: nil, expression: nil, sleeping: true),
        Entry(title: "Ospalá", mood: .sleepy, expression: nil),
        Entry(title: "Klidná", mood: .calm, expression: nil),
        Entry(title: "Spokojená", mood: .content, expression: nil),
        Entry(title: "Šťastná", mood: .happy, expression: nil),
        Entry(title: "Zářivá", mood: .radiant, expression: nil),
        Entry(title: "Přemýšlení", mood: nil, expression: .thinking),
        Entry(title: "Snění", mood: nil, expression: .dreaming),
        Entry(title: "Údiv", mood: nil, expression: .astonished),
        Entry(title: "Zvědavost", mood: nil, expression: .curious),
        Entry(title: "Radost", mood: nil, expression: .joy)
    ]

    var body: some View {
        HStack(spacing: 6) {
            action("Kotoul") { sim.triggerPlay(.somersault); engage() }
            arrow("chevron.left") { move(-1) }
            Text(Self.entries[index].title)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
            arrow("chevron.right") { move(1) }
            action("Pirueta") { sim.triggerPlay(.pirouette); engage() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func move(_ step: Int) {
        let count = Self.entries.count
        index = (index + step + count) % count
        let entry = Self.entries[index]
        model.demoMoodOverride = entry.mood
        model.demoSleepOverride = index == 0 ? nil : entry.sleeping
        sim.forcedExpression = entry.expression
        if entry.expression == nil { sim.expression = nil }
    }

    private func arrow(_ symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.water)
                .frame(width: 26, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func action(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(theme.water.opacity(0.18), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

struct MoodBar: View {
    @Environment(\.appTheme) private var theme
    @Environment(PetModel.self) private var model
    @State private var expanded = false

    var body: some View {
        let vitals = model.vitals
        let mood = model.effectiveMood
        let isSleeping = model.isSleepingTime
        let progress = vitals.xpForNextLevel.map { Double(vitals.xpIntoLevel) / Double(max(1, $0)) } ?? 1
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(isSleeping ? Palette.mist : tint(mood)).frame(width: 8, height: 8)
                Text(isSleeping ? "Spící" : mood.title)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                Text("·").foregroundStyle(Palette.inkSecondary)
                Text("Úroveň \(vitals.level)")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
                Spacer(minLength: 8)
                Text("Nakrmeno \(model.fedToday) / \(model.config.maxDailyFeed)")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.inkSecondary)
            }
            .lineLimit(1)
            Capsule()
                .fill(theme.accent.opacity(0.2))
                .frame(height: 3)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(theme.accent).frame(width: max(3, proxy.size.width * min(1, progress)))
                    }
                }
            if expanded {
                HStack(spacing: 4) {
                    ForEach(Mood.allCases, id: \.self) { entry in
                        let isCurrent = !isSleeping && entry == mood
                        VStack(spacing: 3) {
                            Circle().fill(tint(entry)).frame(width: 9, height: 9)
                            Text(entry.title)
                                .font(.system(.caption2, design: .rounded, weight: isCurrent ? .bold : .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .opacity(isCurrent ? 1 : 0.55)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 6)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .contentShape(.rect)
        .onTapGesture { withAnimation(.spring(duration: 0.4, bounce: 0.2)) { expanded.toggle() } }
        .task(id: expanded) {
            guard expanded else { return }
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { withAnimation(.spring(duration: 0.4, bounce: 0.2)) { expanded = false } }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .animation(.smooth, value: vitals)
        .accessibilityElement(children: .combine)
    }

    private func tint(_ mood: Mood) -> Color {
        switch mood {
        case .sleepy: Palette.mist
        case .calm: Palette.seaBlue
        case .content: Palette.sage
        case .happy: Palette.sand
        case .radiant: theme.accent
        }
    }
}

public struct PetSettingsSection: View {
    @Environment(PetModel.self) private var model

    public init() {}

    public var body: some View {
        @Bindable var settings = model.settings
        SettingsGroup("Notifikace", hint: "Večerní připomenutí přijde jen když medúza nedostane celou porci.") {
            Toggle("Večerní připomenutí", isOn: Binding(
                get: { settings.notificationsEnabled },
                set: { value in Task { await model.setNotifications(enabled: value) } }
            ))
            if settings.notificationsEnabled {
                DatePicker("Čas", selection: timeBinding(settings), displayedComponents: .hourAndMinute)
            }
        }
    }

    private func timeBinding(_ settings: PetSettings) -> Binding<Date> {
        Binding {
            Calendar.kinet.date(bySettingHour: settings.nudgeMinuteOfDay / 60, minute: settings.nudgeMinuteOfDay % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.kinet.dateComponents([.hour, .minute], from: date)
            settings.nudgeMinuteOfDay = (parts.hour ?? 20) * 60 + (parts.minute ?? 0)
        }
    }
}
