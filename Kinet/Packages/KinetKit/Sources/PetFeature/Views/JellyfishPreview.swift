import KinetDesign
import SwiftUI

public struct JellyfishPreview: View {
    @State private var sim = JellyfishSimulation()
    private let skinID: String
    private let mood: Mood
    private let scale: Double
    private let isPinned: Bool

    public init(skinID: String = "coralSkin", scale: Double = 1.1, isPinned: Bool = false) {
        self.skinID = skinID
        self.mood = .happy
        self.scale = scale
        self.isPinned = isPinned
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 40.0)) { timeline in
            Canvas { context, size in
                let parameters = SimParameters(scale: scale, frequency: 0.6, tentacles: 7, reduceMotion: false, smile: 0.9, sleepy: false)
                if isPinned { sim.pinPosition = Vec(size.width / 2, size.height / 2 - 10 * scale) }
                sim.step(date: timeline.date, size: size, parameters: parameters)
                let appearance = JellyfishAppearance(skinID: skinID, mood: mood, scale: scale, tentacles: 7, glow: 0.8)
                JellyfishRenderer.draw(in: &context, sim: sim, appearance: appearance, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .accessibilityHidden(true)
    }
}
