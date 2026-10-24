import CoreHaptics
import Observation
import SwiftUI

public enum HapticEvent: CaseIterable, Sendable {
    case softTap, waterTap, jellyTouch, decorTap, bubbles, purchase, dataReady
    case experienceWarm, experienceLight, experienceBubbles, experienceShoal
    case levelUp, phaseChange, breathStart, breakEnd, sessionEnd, tick, detent, milestone, inhale, exhale
}

@MainActor
@Observable
public final class Feedback {
    public var hapticsEnabled: Bool {
        didSet { store.save(hapticsEnabled, "feedback.haptics") }
    }

    public var soundsEnabled: Bool {
        didSet { store.save(soundsEnabled, "feedback.sounds") }
    }

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let sounds = SoundPlayer()
    @ObservationIgnored private var engine: CHHapticEngine?
    @ObservationIgnored private let supportsHardware: Bool
    @ObservationIgnored private var breathPlayer: CHHapticPatternPlayer?
    @ObservationIgnored private var patterns: [HapticEvent: CHHapticPattern] = [:]

    public init(defaults: UserDefaults) {
        store = SettingsStore(defaults)
        hapticsEnabled = store.value("feedback.haptics", default: true)
        soundsEnabled = store.value("feedback.sounds", default: true)
        self.supportsHardware = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    public func play(_ event: HapticEvent) {
        if soundsEnabled { sounds.play(event) }
        guard supportsHardware, hapticsEnabled else { return }
        guard let engine = prepareEngine(), let built = pattern(for: event) else { return }
        do {
            let player = try engine.makePlayer(with: built)
            if event == .inhale || event == .exhale {
                try? breathPlayer?.stop(atTime: CHHapticTimeImmediate)
                breathPlayer = player
            }
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            self.engine = nil
        }
    }

    public func stopBreathing() {
        try? breathPlayer?.stop(atTime: CHHapticTimeImmediate)
        breathPlayer = nil
    }

    private func prepareEngine() -> CHHapticEngine? {
        if let engine { return engine }
        do {
            let created = try CHHapticEngine()
            created.isAutoShutdownEnabled = true
            created.resetHandler = { [weak self] in
                Task { @MainActor in self?.engine = nil }
            }
            created.stoppedHandler = { [weak self] _ in
                Task { @MainActor in self?.engine = nil }
            }
            try created.start()
            engine = created
            return created
        } catch {
            return nil
        }
    }

    private func pattern(for event: HapticEvent) -> CHHapticPattern? {
        if let cached = patterns[event] { return cached }
        let created = makePattern(event)
        patterns[event] = created
        return created
    }

    private func makePattern(_ event: HapticEvent) -> CHHapticPattern? {
        var events: [CHHapticEvent] = []
        var curves: [CHHapticParameterCurve] = []

        func tap(_ time: TimeInterval, _ intensity: Float, _ sharpness: Float = 0.3) {
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ], relativeTime: time))
        }

        func hum(_ time: TimeInterval, _ duration: TimeInterval, _ intensity: Float, _ sharpness: Float = 0.1) {
            events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ], relativeTime: time, duration: duration))
        }

        func swell(_ duration: TimeInterval, from: Float, to: Float) {
            hum(0, duration, 1, 0.05)
            curves.append(CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                .init(relativeTime: 0, value: from),
                .init(relativeTime: duration, value: to)
            ], relativeTime: 0))
        }

        switch event {
        case .softTap, .waterTap, .jellyTouch, .decorTap, .purchase, .dataReady:
            tap(0, 0.3, 0.15)
            hum(0.03, 0.12, 0.16)
        case .bubbles:
            tap(0, 0.2); tap(0.08, 0.32); tap(0.17, 0.46); tap(0.28, 0.3, 0.2)
        case .experienceWarm, .experienceLight, .experienceBubbles, .experienceShoal:
            swell(1.4, from: 0.15, to: 0.7)
        case .levelUp:
            tap(0, 0.6, 0.4); hum(0.05, 0.4, 0.3)
            tap(0.22, 0.9, 0.6)
        case .phaseChange, .breathStart, .breakEnd:
            hum(0, 0.5, 0.35)
        case .sessionEnd:
            tap(0, 0.7, 0.6)
            hum(0.01, 0.14, 0.3, 0.2)
        case .tick:
            tap(0, 0.2, 0.4)
        case .detent:
            tap(0, 0.62, 0.7)
        case .milestone:
            tap(0, 1, 0.85)
            hum(0.02, 0.1, 0.45, 0.3)
        case .inhale:
            swell(4, from: 0.08, to: 0.55)
        case .exhale:
            swell(6, from: 0.5, to: 0.04)
        }

        guard !events.isEmpty else { return nil }
        return try? CHHapticPattern(events: events, parameterCurves: curves)
    }
}

public struct FeedbackSettingsSection: View {
    @Environment(Feedback.self) private var feedback

    public init() {}

    public var body: some View {
        @Bindable var feedback = feedback
        SettingsGroup("Systém") {
            Toggle("Zvuky", isOn: $feedback.soundsEnabled)
            Toggle("Haptika", isOn: $feedback.hapticsEnabled)
        }
    }
}
