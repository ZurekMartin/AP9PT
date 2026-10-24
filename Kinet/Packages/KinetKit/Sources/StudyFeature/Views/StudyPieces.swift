import KinetCurrency
import KinetDesign
import SwiftUI

let ringSize: CGFloat = 280
let ringWidth: CGFloat = 34
private let dialMaximum = 60.0
private let dialTotal = 120.0

struct DonutRing: View {
    let fraction: Double
    var tint: Color = Palette.seaBlue
    var gradient: Gradient?
    var dotColor: Color?
    var showsTrack = true
    var roundsStart = true
    var showsDot = true
    var leadIn = 0.0

    var body: some View {
        let value = min(1, max(0, fraction))
        let colors = gradient ?? Gradient(colors: [tint.opacity(0.62), tint])
        let radius = (ringSize - ringWidth) / 2
        let angle = value * 2 * .pi
        let overlap = min(1, max(0, (value - 0.9) / 0.1))
        ZStack {
            if showsTrack { Circle().stroke(tint.opacity(0.15), lineWidth: ringWidth) }
            if roundsStart, let first = colors.stops.first?.color {
                Circle()
                    .fill(first)
                    .frame(width: ringWidth, height: ringWidth)
                    .offset(y: -radius)
                    .opacity(value > 0.001 ? 1 : 0)
            }
            if value >= 1 {
                Circle()
                    .stroke(
                        AngularGradient(gradient: colors, center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                        lineWidth: ringWidth
                    )
                    .rotationEffect(.degrees(-90))
            } else {
                Circle()
                    .trim(from: 0, to: max(0.0005, value + leadIn))
                    .stroke(
                        AngularGradient(gradient: colors, center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90 - leadIn * 360))
            }
            Circle()
                .fill(dotColor ?? tint)
                .frame(width: ringWidth, height: ringWidth)
                .shadow(color: .black.opacity(0.34 * overlap), radius: 5)
                .offset(y: -radius)
                .rotationEffect(.radians(angle))
                .opacity(value > 0.001 && showsDot ? 1 : 0)
        }
        .padding(ringWidth / 2)
    }
}

struct DialBand: View, Animatable {
    @Environment(\.appTheme) private var theme
    var minutes: Double
    var restWeight: Double
    var finishWeight: Double

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(minutes, AnimatablePair(restWeight, finishWeight)) }
        set {
            minutes = newValue.first
            restWeight = newValue.second.first
            finishWeight = newValue.second.second
        }
    }

    var body: some View {
        let tint = theme.water.mix(with: Palette.sage, by: finishWeight).mix(with: Palette.sage, by: restWeight)
        let total = min(dialTotal, max(0, minutes))
        let steps = 12
        let first = Gradient(colors: (0...steps).map { Self.color(Double($0) / Double(steps) * 0.5, tint: tint) })
        let second = Gradient(colors: (0...steps).map { Self.color(0.5 + Double($0) / Double(steps) * 0.5, tint: tint) })
        if total > dialMaximum {
            let lap = (total - dialMaximum) / dialMaximum
            ZStack {
                DonutRing(fraction: 1, tint: tint, gradient: first, dotColor: Self.color(0.5, tint: tint), roundsStart: false, showsDot: false)
                DonutRing(fraction: lap, tint: tint, gradient: second, dotColor: Self.color(0.5 + lap * 0.5, tint: tint), showsTrack: false, roundsStart: false, leadIn: 0.004)
            }
        } else {
            let lap = total / dialMaximum
            DonutRing(fraction: lap, tint: tint, gradient: first, dotColor: Self.color(lap * 0.5, tint: tint))
        }
    }

    private static func color(_ position: Double, tint: Color) -> Color {
        let t = min(1, max(0, position))
        let light = tint.mix(with: .white, by: 0.32)
        let deep = tint.mix(with: Palette.coral, by: 0.5).mix(with: .black, by: 0.12)
        return t < 0.5 ? light.mix(with: tint, by: t * 2) : tint.mix(with: deep, by: (t - 0.5) * 2)
    }
}

struct DialKnob: View, Animatable {
    @Environment(\.appTheme) private var theme
    var minutes: Double

    var animatableData: Double {
        get { minutes }
        set { minutes = newValue }
    }

    var body: some View {
        let radius = (ringSize - ringWidth) / 2
        let lap = min(dialTotal, max(0, minutes)).truncatingRemainder(dividingBy: dialMaximum)
        let fraction = lap == 0 && minutes > 0 ? 1 : lap / dialMaximum
        Circle()
            .fill(Color.white.opacity(0.92))
            .overlay { Circle().strokeBorder(theme.water.opacity(0.35), lineWidth: 1) }
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            .frame(width: ringWidth - 10, height: ringWidth - 10)
            .offset(y: -radius)
            .rotationEffect(.radians(fraction * 2 * .pi))
            .allowsHitTesting(false)
    }
}

struct RingSchedule: TimelineSchedule {
    var boundaries: [Date] = []
    var anchor: Date?
    var slow: TimeInterval = 1
    var isRunning = false

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(cursor: startDate, schedule: self)
    }

    struct Entries: Sequence, IteratorProtocol {
        var cursor: Date
        let schedule: RingSchedule
        var started = false

        mutating func next() -> Date? {
            guard started else {
                started = true
                return cursor
            }
            guard schedule.isRunning else { return nil }
            let now = cursor
            let blend = RingReading.blendDuration
            if schedule.boundaries.contains(where: { now >= $0 && now < $0.addingTimeInterval(blend) }) {
                cursor = now.addingTimeInterval(1.0 / 60.0)
                return cursor
            }
            var candidate = now.addingTimeInterval(schedule.slow)
            if schedule.slow >= 1, let anchor = schedule.anchor, anchor > now {
                let remaining = anchor.timeIntervalSince(now)
                let aligned = anchor.addingTimeInterval(-(remaining.rounded(.up) - 1) + 0.01)
                if aligned > now.addingTimeInterval(0.001) { candidate = Swift.min(candidate, aligned) }
            }
            if let boundary = schedule.boundaries.first(where: { $0 > now }), boundary < candidate {
                candidate = boundary
            }
            cursor = candidate
            return cursor
        }
    }
}

struct BreathSchedule: TimelineSchedule {
    let start: Date
    let breath: BreathCycle

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(cursor: startDate, start: start, breath: breath)
    }

    struct Entries: Sequence, IteratorProtocol {
        var cursor: Date
        let start: Date
        let breath: BreathCycle
        var started = false

        mutating func next() -> Date? {
            guard started else {
                started = true
                return cursor
            }
            let elapsed = breath.elapsed(at: cursor, since: start)
            let base = cursor.addingTimeInterval(-elapsed)
            let next = elapsed < breath.inhale ? base.addingTimeInterval(breath.inhale) : base.addingTimeInterval(breath.length)
            cursor = next.addingTimeInterval(0.01)
            return cursor
        }
    }
}

struct StudyStage: View {
    @Environment(\.appTheme) private var theme
    @Environment(StudyModel.self) private var study
    @Environment(Feedback.self) private var feedback
    @ScaledMetric private var numberSize: CGFloat = 64
    @ScaledMetric private var timerSize: CGFloat = 54
    @ScaledMetric private var resultSize: CGFloat = 52
    @State private var isDragging = false
    @State private var resultProgress = 0.0
    @State private var shown = 0
    @State private var ripple = false

    var body: some View {
        let state = study.state
        ZStack {
            ticks
                .opacity(isIdle ? 1 : 0)
            ringLayer
                .opacity(isBreathing ? 0 : 1)
            idleCenter
                .opacity(isIdle ? 1 : 0)
                .allowsHitTesting(isIdle)
            resultCenter
                .opacity(isFinished ? 1 : 0)
            if case .running(let phase) = state, phase.kind == .cooldown {
                BreathingGlow(start: phase.start, canResume: study.plan?.isPomodoro == true) { try? study.skipCooldown() }
                    .transition(.opacity)
            }
        }
        .frame(width: ringSize, height: ringSize)
        .contentShape(.circle)
        .gesture(dialGesture, including: isIdle ? .all : .subviews)
        .animation(.smooth(duration: 0.6), value: state)
        .task(id: finishedMinutes) { await presentResult() }
        .accessibilityAdjustableAction { direction in
            guard isIdle else { return }
            switch direction {
            case .increment: study.selectedMinutes = min(study.config.minuteRange.upperBound, study.selectedMinutes + 1)
            case .decrement: study.selectedMinutes = max(study.config.minuteRange.lowerBound, study.selectedMinutes - 1)
            @unknown default: break
            }
        }
    }

    private var isIdle: Bool {
        if case .idle = study.state { return true }
        return false
    }

    private var isFinished: Bool {
        if case .finished = study.state { return true }
        return false
    }

    private var isBreathing: Bool {
        if case .running(let phase) = study.state { return phase.kind == .cooldown }
        return false
    }

    private var finishedMinutes: Int? {
        if case .finished(let minutes) = study.state { return minutes }
        return nil
    }

    private var tint: Color {
        isFinished ? Palette.sage : theme.water
    }

    private func reading(at date: Date) -> RingReading {
        switch study.state {
        case .idle:
            let value = Double(study.selectedMinutes)
            return RingReading(value: value, restWeight: 0, tide: value)
        case .finished:
            let value = resultProgress * dialTotal
            return RingReading(value: value, restWeight: 0, tide: value)
        case .running:
            return study.ringReading(at: date)
        }
    }

    private var ringSchedule: RingSchedule {
        guard study.isRunning, !study.isPaused, case .running(let phase) = study.state else { return RingSchedule() }
        let demo = (study.plan?.timeScale ?? 1) < 1
        return RingSchedule(boundaries: study.phaseStarts(), anchor: phase.end, slow: demo ? 1.0 / 30.0 : 1, isRunning: true)
    }

    private var ringLayer: some View {
        TimelineView(ringSchedule) { timeline in
            let date = study.effectiveDate(timeline.date)
            let reading = reading(at: date)
            let ringTint = tint.mix(with: Palette.sage, by: reading.restWeight)
            ZStack {
                DialBand(minutes: reading.value, restWeight: reading.restWeight, finishWeight: isFinished ? 1 : 0)
                TideFill(level: reading.tide / dialTotal, tint: ringTint, isFrozen: study.isPaused)
                    .padding(ringWidth + 10)
                DialKnob(minutes: reading.value)
                    .opacity(isIdle ? 1 : 0)
                if case .running(let phase) = study.state, phase.kind != .cooldown {
                    Text(clock(max(0, phase.end.timeIntervalSince(date))))
                        .font(.system(size: timerSize, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(phase.kind == .rest ? ringTint : Palette.ink)
                        .opacity(study.isPaused ? 0.45 : 1)
                        .animation(.smooth(duration: 0.3), value: study.isPaused)
                }
            }
            .animation(study.isRunning || isDragging ? nil : .smooth(duration: 0.9), value: reading)
            .animation(.smooth(duration: 0.9), value: isFinished)
        }
    }

    private var idleCenter: some View {
        Button {
            try? study.start()
        } label: {
            VStack(spacing: 0) {
                Text("\(study.selectedMinutes)")
                    .font(.system(size: numberSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(study.selectedMinutes)))
                    .foregroundStyle(Palette.ink)
                Text(MinuteFormatter.word(study.selectedMinutes).prefix(1).uppercased() + MinuteFormatter.word(study.selectedMinutes).dropFirst())
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
            }
            .frame(width: 150, height: 150)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Začít studium, \(study.selectedMinutes) minut")
        .animation(.smooth(duration: 0.25), value: study.selectedMinutes)
    }

    private var resultCenter: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .stroke(Palette.sage.opacity(0.28), lineWidth: 1.5)
                    .frame(width: ringSize - 40, height: ringSize - 40)
                    .scaleEffect(ripple ? 1.35 + Double(index) * 0.14 : 0.9)
                    .opacity(ripple ? 0 : 0.7)
                    .animation(.easeOut(duration: 2.6).delay(Double(index) * 0.5), value: ripple)
            }
            VStack(spacing: 2) {
                Text("+\(shown)")
                    .font(.system(size: resultSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(shown)))
                    .foregroundStyle(Palette.ink)
                Text("Připsáno")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .allowsHitTesting(false)
    }

    private var ticks: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                Capsule()
                    .fill(Palette.ink.opacity(0.18))
                    .frame(width: 2, height: 5)
                    .offset(y: -(ringSize / 2 + 9))
                    .rotationEffect(.degrees(Double(index) * 30))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var dialGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let startDx = drag.startLocation.x - ringSize / 2
                let startDy = drag.startLocation.y - ringSize / 2
                guard (startDx * startDx + startDy * startDy).squareRoot() > 84 else { return }
                isDragging = true
                let dx = drag.location.x - ringSize / 2
                let dy = drag.location.y - ringSize / 2
                var angle = atan2(dx, -dy)
                if angle < 0 { angle += .pi * 2 }
                apply(Int((angle / (.pi * 2) * dialMaximum).rounded()) % Int(dialMaximum))
            }
            .onEnded { _ in isDragging = false }
    }

    private func apply(_ lap: Int) {
        let range = study.config.minuteRange
        let current = study.selectedMinutes
        let lapSize = Int(dialMaximum)
        var delta = (lap - current % lapSize) % lapSize
        if delta > lapSize / 2 { delta -= lapSize }
        if delta < -lapSize / 2 { delta += lapSize }
        var value = current + delta
        let nearest = (value + 5) / 10 * 10
        if abs(value - nearest) <= 1 && range.contains(nearest) { value = nearest }
        value = min(max(value, range.lowerBound), range.upperBound)
        guard value != current else { return }
        study.selectedMinutes = value
        if value % 5 == 0 {
            feedback.play(.detent)
        } else {
            feedback.play(.tick)
        }
    }

    private func presentResult() async {
        guard let minutes = finishedMinutes else {
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { resultProgress = 0; shown = 0; ripple = false }
            return
        }
        shown = 0
        ripple = false
        withAnimation(.easeInOut(duration: RingReading.blendDuration)) { resultProgress = min(1, Double(minutes) / dialTotal) }
        ripple = true
        let steps = 24
        for step in 1...steps {
            try? await Task.sleep(for: .milliseconds(45))
            if Task.isCancelled { return }
            withAnimation(.smooth(duration: 0.2)) { shown = minutes * step / steps }
        }
        try? await Task.sleep(for: .seconds(3.6))
        if !Task.isCancelled { study.dismissSummary() }
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

struct BreathingGlow: View {
    @Environment(\.appTheme) private var theme
    let start: Date
    let canResume: Bool
    let finish: () -> Void
    @Environment(StudyModel.self) private var study
    @Environment(Feedback.self) private var feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tints = [theme.water, Palette.sage, theme.water.mix(with: .white, by: 0.55)]
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            let progress = reduceMotion ? 0.6 : study.breath.progress(at: timeline.date, since: start)
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let spread = 16 + 40 * progress
                let radius = 64 * (0.72 + 0.28 * progress)
                for index in 0..<3 {
                    let angle = Double(index) / 3 * .pi * 2 + progress * 0.9 - .pi / 2
                    let point = CGPoint(x: center.x + cos(angle) * spread, y: center.y + sin(angle) * spread)
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                        with: .radialGradient(
                            Gradient(stops: [.init(color: tints[index].opacity(0.55), location: 0), .init(color: tints[index].opacity(0.42), location: 0.62), .init(color: tints[index].opacity(0.2), location: 0.82), .init(color: tints[index].opacity(0), location: 1)]),
                            center: point, startRadius: 0, endRadius: radius
                        )
                    )
                }
                let halo = 92 + 30 * progress
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - halo, y: center.y - halo, width: halo * 2, height: halo * 2)),
                    with: .radialGradient(Gradient(colors: [Palette.seaBlue.opacity(0.12), Palette.seaBlue.opacity(0)]), center: center, startRadius: 0, endRadius: halo)
                )
            }
            .frame(width: 360, height: 360)
        }
        .frame(width: ringSize, height: ringSize)
        .contentShape(.circle)
        .onTapGesture(perform: finish)
        .onDisappear { feedback.stopBreathing() }
        .task {
            while !Task.isCancelled {
                let now = Date()
                if study.breath.isInhaling(at: now, since: start) {
                    feedback.play(.inhale)
                    try? await Task.sleep(for: .seconds(study.breath.inhale - study.breath.elapsed(at: now, since: start)))
                } else {
                    feedback.play(.exhale)
                    try? await Task.sleep(for: .seconds(study.breath.length - study.breath.elapsed(at: now, since: start)))
                }
            }
        }
        .accessibilityLabel(canResume ? "Dýchání. Klepnutím ho ukončíš." : "Dýchání. Klepnutím skončíš.")
    }
}
