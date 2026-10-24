import KinetDesign
import SwiftUI

struct DecorEntry: Equatable {
    let id: String
    let placement: DecorPlacement
}

struct SceneState {
    var appearance: JellyfishAppearance
    var parameters: SimParameters
    var themeID: String
    var decor: [DecorEntry]
    var experience: SceneExperience?
    var isEngaged: Bool
}

struct DecorSpot {
    let id: String
    let layer: Int
    let base: CGPoint
    let scale: Double
    let halfWidth: Double
    let height: Double
}

struct DuneArt {
    let fill: Path
    let gradient: Gradient
    let start: CGPoint
    let end: CGPoint
    let rim: Path
    let lightSpecks: Path
    let darkSpecks: Path
    let ripples: Path
}

@MainActor
final class AquariumCache {
    private struct LayoutKey: Equatable {
        let size: CGSize
        let decor: [DecorEntry]
    }

    private struct TerrainKey: Equatable {
        let size: CGSize
        let themeID: String
        let dark: Bool
    }

    private var layoutKey: LayoutKey?
    private var terrainKey: TerrainKey?
    private(set) var spots: [DecorSpot] = []
    private(set) var spotInfos: [SpotInfo] = []
    private(set) var interests: [Interest] = []
    private(set) var dunes: [DuneArt] = []

    func prepare(size: CGSize, decor: [DecorEntry], themeID: String, dark: Bool, colors: ThemeColors) {
        let layout = LayoutKey(size: size, decor: decor)
        if layout != layoutKey {
            layoutKey = layout
            spots = AquariumScene.spots(size: size, decor: decor)
            spotInfos = spots.map { SpotInfo(id: $0.id, layer: $0.layer, x: $0.base.x, halfWidth: $0.halfWidth) }
            interests = spots.map { Interest(position: Vec($0.base.x, $0.base.y), depth: AquariumScene.layerDepths[$0.layer]) }
        }
        let terrain = TerrainKey(size: size, themeID: themeID, dark: dark)
        if terrain != terrainKey {
            terrainKey = terrain
            dunes = (0..<AquariumScene.layerCount).map { AquariumScene.duneArt(layer: $0, size: size, colors: colors, dark: dark) }
        }
    }
}

struct AquariumScene: View {
    let sceneState: SceneState
    let sim: JellyfishSimulation
    let life: AquariumLife
    let reactions: DecorReactions
    let onTap: (CGPoint, Double) -> Void
    let onDecor: (String, CGPoint, Double) -> Void
    @State private var cache = AquariumCache()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pageActive) private var pageActive
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.screenInsets) private var insets
    @Environment(\.appTheme) private var theme

    var body: some View {
        let paused = !pageActive || scenePhase != .active
        let interval = sceneState.isEngaged || sceneState.experience != nil ? 1.0 / 60.0 : 1.0 / 30.0
        GeometryReader { proxy in
            let colors = ThemeColors.resolve(sceneState.themeID, dark: scheme == .dark)
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: paused || reduceMotion)) { timeline in
                    mesh(colors: colors, t: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate)
                }
                TimelineView(.animation(minimumInterval: interval, paused: paused)) { timeline in
                    Canvas { context, size in
                        draw(&context, size: size, colors: colors, date: timeline.date)
                    }
                }
            }
            .contentShape(.rect)
            .onTapGesture { location in handleTap(location, size: proxy.size) }
        }
        .mask { AquariumMask() }
        .ignoresSafeArea()
    }

    private func mesh(colors: ThemeColors, t: Double) -> some View {
        func w(_ speed: Double, _ phase: Double) -> Float { Float(sin(t * speed + phase)) }
        let points: [SIMD2<Float>] = [
            [0, 0], [0.5 + 0.06 * w(0.12, 0), 0], [1, 0],
            [0, 0.5 + 0.05 * w(0.1, 1)], [0.5 + 0.1 * w(0.15, 2), 0.5 + 0.07 * w(0.13, 3)], [1, 0.5 + 0.05 * w(0.11, 4)],
            [0, 1], [0.5 + 0.06 * w(0.09, 5), 1], [1, 1]
        ]
        let glow = colors.mid.mix(with: Palette.seaBlue, by: 0.25)
        return MeshGradient(width: 3, height: 3, points: points, colors: [
            colors.top, colors.top, colors.top,
            colors.mid, glow, colors.mid,
            colors.bottom, colors.bottom, colors.bottom
        ], smoothsColors: true)
    }

    nonisolated static let layerBases = [0.60, 0.65, 0.70, 0.75, 0.80]
    nonisolated static let layerScales = [0.72, 0.86, 1.0, 1.14, 1.3]
    nonisolated static let layerDepths = [1.0, 0.8, 0.6, 0.4, 0.2]
    nonisolated static let layerCount = 5
    nonisolated static let hazes = [0.34, 0.24, 0.14, 0.06, 0]

    private static func renderLayer(of spot: DecorSpot) -> Int {
        spot.id == "shells" ? min(layerCount - 1, spot.layer + 1) : spot.layer
    }

    private static let extents: [String: (Double, Double)] = [
        "seaweed": (26, 95), "pebbles": (36, 16), "shells": (32, 20), "bubbler": (20, 22), "coral": (30, 72),
        "glowMushroom": (24, 48), "amphora": (24, 66), "moonstone": (18, 32), "shipwreck": (62, 95),
        "starfish": (20, 18), "chest": (26, 42), "anemone": (26, 40)
    ]

    private static func peakX(layer: Int, near desired: Double, size: CGSize) -> Double {
        var bestX = desired
        var bestY = Double.infinity
        for step in -12...12 {
            let x = min(max(desired + Double(step) * size.width * 0.005, 14), size.width - 14)
            let y = baseline(layer: layer, x: x, size: size)
            if y < bestY {
                bestY = y
                bestX = x
            }
        }
        return bestX
    }

    static func spots(size: CGSize, decor: [DecorEntry]) -> [DecorSpot] {
        let unit = Double(size.width) / 390
        return decor.map { item in
            let layer = min(layerCount - 1, max(0, item.placement.layer))
            let onSlope = item.id == "pebbles"
            let rawX = onSlope ? size.width * item.placement.x : peakX(layer: layer, near: size.width * item.placement.x, size: size)
            let scale = item.placement.scale * unit * layerScales[layer]
            let extent = extents[item.id] ?? (28, 50)
            let margin = extent.0 * scale + 8
            let x = min(max(rawX, margin), max(margin, size.width - margin))
            let slopeShift = onSlope ? size.height * 0.045 : 0
            return DecorSpot(
                id: item.id, layer: layer,
                base: CGPoint(x: x, y: baseline(layer: layer, x: x, size: size) + 3 * unit + slopeShift),
                scale: scale, halfWidth: extent.0 * scale, height: extent.1 * scale
            )
        }
    }

    private func handleTap(_ location: CGPoint, size: CGSize) {
        if sim.distanceToBody(Vec(location.x, location.y)) < 85 * sim.effectiveScale {
            onTap(location, 0)
            return
        }
        let spots = cache.spots.isEmpty ? Self.spots(size: size, decor: sceneState.decor) : cache.spots
        for spot in spots.sorted(by: { $0.layer > $1.layer }) {
            let rect = CGRect(x: spot.base.x - spot.halfWidth, y: spot.base.y - spot.height, width: spot.halfWidth * 2, height: spot.height + 12)
            if rect.contains(location) {
                if reactions.trigger(spot.id, at: Date().timeIntervalSinceReferenceDate) {
                    onDecor(spot.id, spot.base, max(0, Self.layerDepths[spot.layer]))
                }
                return
            }
        }
        onTap(location, tapDepth(at: location, size: size))
    }

    private func tapDepth(at location: CGPoint, size: CGSize) -> Double {
        var tapped: Int?
        for layer in 0..<Self.layerCount where location.y >= Self.baseline(layer: layer, x: location.x, size: size) {
            tapped = layer
        }
        guard let tapped else { return 0 }
        return max(0, Self.layerDepths[tapped] - 0.1)
    }

    nonisolated static func baseline(layer: Int, x: Double, size: CGSize) -> Double {
        let base = layerBases[layer]
        let l = Double(layer)
        let wave = sin(x / size.width * .pi * 2 * (1 + l * 0.4) + l * 1.7) * 0.012 + sin(x / size.width * .pi * 5 + l) * 0.004
        return size.height * (base + wave) + 20
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, colors: ThemeColors, date timeline: Date) {
        let t = timeline.timeIntervalSinceReferenceDate
        let dark = scheme == .dark
        cache.prepare(size: size, decor: sceneState.decor, themeID: sceneState.themeID, dark: dark, colors: colors)
        let layout = cache.spots

        var parameters = sceneState.parameters
        parameters.topLimit = insets.top + 8 + 52 + 12
        parameters.bottomLimit = size.height - (KinetLayout.pageMargin + KinetLayout.barHeight + 12)
        parameters.terrain = { x, depth in
            guard let layer = Self.layerDepths.firstIndex(where: { depth >= $0 }) else { return nil }
            return Self.baseline(layer: layer, x: x, size: size)
        }
        parameters.interests = cache.interests
        sim.step(date: timeline, size: size, parameters: parameters)
        life.step(
            date: timeline, size: size, topY: parameters.topLimit,
            spots: cache.spotInfos,
            layerBases: Self.layerBases, layerDepths: Self.layerDepths,
            baseline: { Self.baseline(layer: $0, x: $1, size: size) }, reduceMotion: reduceMotion,
            jelly: JellyThreat(position: sim.position, depth: sim.depth, isActive: sim.isRushingFast)
        )

        let experience = ExperienceFrame(sceneState.experience, now: timeline)
        let lighting = experience?.id == "lightShow"
        let shoal = experience.flatMap { $0.id == "silverShoal" ? shoalPath(size: size, frame: $0) : nil }
        drawRays(&context, size: size, t: t, dark: dark, boost: lighting ? 1 + 3.4 * (experience?.e ?? 0) : 1, tint: lighting ? Self.lightTint(experience?.t ?? 0) : .white)
        drawAmbient(&context, size: size, t: t, dark: dark)
        if let experience { drawExperienceBackdrop(&context, size: size, frame: experience, dark: dark) }

        let hazeTop = size.height * 0.28
        let hazeBottom = size.height * 0.78
        let hazeRect = Path(CGRect(x: 0, y: hazeTop, width: size.width, height: size.height - hazeTop))
        func haze(_ amount: Double) {
            guard amount > 0 else { return }
            context.fill(hazeRect, with: .linearGradient(
                Gradient(colors: [colors.mid.opacity(0), colors.mid.opacity(amount)]),
                startPoint: CGPoint(x: 0, y: hazeTop), endPoint: CGPoint(x: 0, y: hazeBottom)
            ))
        }

        var sprites: [(depth: Double, school: Int?)] = [(sim.depth, nil)]
        for index in life.schools.indices { sprites.append((life.schools[index].depth, index)) }
        sprites.sort { $0.depth > $1.depth }
        var nextSprite = 0
        func drawSprite(_ sprite: (depth: Double, school: Int?), _ target: inout GraphicsContext) {
            if let index = sprite.school {
                drawFishSchool(&target, school: life.schools[index], time: t, haze: colors.mid)
            } else {
                if let experience { drawJellyHalo(&target, frame: experience) }
                drawJelly(&target, t: t, colors: colors, size: size)
            }
        }
        if let experience, let shoal { drawExperienceShoal(&context, size: size, frame: experience, path: shoal, haze: colors.mid, pass: -1) }
        for layer in 0..<Self.layerCount {
            while nextSprite < sprites.count && sprites[nextSprite].depth >= Self.layerDepths[layer] {
                drawSprite(sprites[nextSprite], &context)
                nextSprite += 1
            }
            if let experience {
                drawExperienceLayer(&context, layer: layer, size: size, frame: experience, dark: dark, haze: colors.mid, topY: parameters.topLimit)
                if let shoal { drawExperienceShoal(&context, size: size, frame: experience, path: shoal, haze: colors.mid, pass: layer) }
            }
            if layer < cache.dunes.count { drawDune(&context, art: cache.dunes[layer], dark: dark) }
            if let experience { drawExperienceGround(&context, layer: layer, size: size, frame: experience) }
            for spot in layout where Self.renderLayer(of: spot) == layer {
                drawDecor(&context, spot: spot, size: size, t: t, dark: dark)
            }
            drawShrimps(&context, layer: layer, life: life, size: size, time: t, haze: colors.mid)
            haze(Self.hazes[layer])
        }
        while nextSprite < sprites.count {
            drawSprite(sprites[nextSprite], &context)
            nextSprite += 1
        }
        if let experience, let shoal { drawExperienceShoal(&context, size: size, frame: experience, path: shoal, haze: colors.mid, pass: Self.layerCount) }
        drawPlankton(&context, t: t)
        drawBubbles(&context)
        if let experience { drawExperienceOverlay(&context, size: size, frame: experience, dark: dark) }

        if !dark { drawCaustics(&context, size: size, t: t, floorY: size.height * 0.7) }
    }

    private func drawDecor(_ context: inout GraphicsContext, spot: DecorSpot, size: CGSize, t: Double, dark: Bool) {
        let base = spot.base
        let scale = spot.scale
        var clipped = context
        clipped.clip(to: Path(CGRect(x: base.x - 4000, y: base.y - 2000, width: 8000, height: 2000 + 3 * scale)))
        DecorRenderer.draw(
            id: spot.id, in: &clipped, base: CGPoint(x: base.x, y: base.y + 2 * scale), scale: scale, time: t, isDark: dark,
            age: reactions.age(spot.id, at: t), width: size.width
        )
    }

    private func drawJelly(_ context: inout GraphicsContext, t: Double, colors: ThemeColors, size: CGSize) {
        let u = min(1, max(0, sim.position.x / max(1, size.width)))
        let v = min(1, max(0, sim.position.y / max(1, size.height)))
        let glow = colors.mid.mix(with: theme.water, by: 0.25)
        let row0 = colors.top
        let row1 = (u < 0.5 ? colors.mid.mix(with: glow, by: u * 2) : glow.mix(with: colors.mid, by: (u - 0.5) * 2))
        let row2 = colors.bottom
        let local = v < 0.5 ? row0.mix(with: row1, by: v * 2) : row1.mix(with: row2, by: (v - 0.5) * 2)
        JellyfishRenderer.draw(in: &context, sim: sim, appearance: sceneState.appearance, time: t, haze: local.mix(with: theme.water, by: 0.3))
    }

    private static func duneColor(layer: Int, colors: ThemeColors) -> Color {
        colors.floor.mix(with: colors.bottom, by: [0.7, 0.52, 0.34, 0.17, 0.0][min(4, layer)])
    }

    static func duneArt(layer: Int, size: CGSize, colors: ThemeColors, dark: Bool) -> DuneArt {
        var surface: [CGPoint] = []
        var x = 0.0
        while x <= size.width + 6 {
            surface.append(CGPoint(x: x, y: baseline(layer: layer, x: x, size: size)))
            x += 6
        }
        var fill = Path()
        fill.move(to: CGPoint(x: 0, y: size.height))
        for point in surface { fill.addLine(to: point) }
        fill.addLine(to: CGPoint(x: size.width, y: size.height))
        fill.closeSubpath()
        let top = duneColor(layer: layer, colors: colors)
        let top0 = baseline(layer: layer, x: size.width / 2, size: size)
        var rim = Path()
        rim.move(to: surface[0])
        for point in surface.dropFirst() { rim.addLine(to: point) }

        var lightSpecks = Path()
        var darkSpecks = Path()
        for index in 0..<20 {
            let seed = Double(index) + Double(layer) * 40
            let fx = fract(sin(seed * 12.9898) * 43758.5453)
            let fy = fract(sin(seed * 78.233) * 12345.6789)
            let px = size.width * fx
            let py = baseline(layer: layer, x: px, size: size) + 5 + fy * size.height * 0.07
            let r = 0.8 + 2.0 * fract(sin(seed * 9.1) * 777.7)
            let rect = CGRect(x: px, y: py, width: r * 2, height: r * 1.3)
            if index % 3 != 0 { lightSpecks.addEllipse(in: rect) } else { darkSpecks.addEllipse(in: rect) }
        }
        var ripples = Path()
        for index in 0..<3 {
            let y = top0 + 14 + Double(index) * 11
            ripples.move(to: CGPoint(x: 0, y: y))
            for step in 1...12 {
                let px = size.width * Double(step) / 12
                ripples.addLine(to: CGPoint(x: px, y: y + sin(px * 0.045 + Double(index) * 2 + Double(layer)) * 2.6))
            }
        }
        return DuneArt(
            fill: fill,
            gradient: Gradient(colors: [top.mix(with: .white, by: dark ? 0.06 : 0.12), top, top.mix(with: .black, by: dark ? 0.35 : 0.14)]),
            start: CGPoint(x: 0, y: top0 - 14),
            end: CGPoint(x: 0, y: size.height),
            rim: rim,
            lightSpecks: lightSpecks,
            darkSpecks: darkSpecks,
            ripples: ripples
        )
    }

    private func drawDune(_ context: inout GraphicsContext, art: DuneArt, dark: Bool) {
        context.fill(art.fill, with: .linearGradient(art.gradient, startPoint: art.start, endPoint: art.end))
        context.stroke(art.rim, with: .color(.white.opacity(dark ? 0.10 : 0.28)), lineWidth: 1.5)
        context.fill(art.lightSpecks, with: .color(.white.opacity(dark ? 0.10 : 0.22)))
        context.fill(art.darkSpecks, with: .color(.black.opacity(0.10)))
        context.stroke(art.ripples, with: .color(.white.opacity(dark ? 0.05 : 0.14)), lineWidth: 1)
    }

    private func drawBubbles(_ context: inout GraphicsContext) {
        for bubble in sim.bubbles {
            let fade = 1 - bubble.age / 2.4
            let rect = CGRect(x: bubble.position.x - bubble.radius, y: bubble.position.y - bubble.radius, width: bubble.radius * 2, height: bubble.radius * 2)
            let shape = Path(ellipseIn: rect)
            context.fill(shape, with: .color(.white.opacity(0.12 * fade)))
            context.stroke(shape, with: .color(.white.opacity(0.7 * fade)), lineWidth: 1)
            context.fill(Path(ellipseIn: CGRect(x: rect.minX + bubble.radius * 0.3, y: rect.minY + bubble.radius * 0.3, width: bubble.radius * 0.5, height: bubble.radius * 0.5)), with: .color(.white.opacity(0.8 * fade)))
        }
    }

    private func drawRays(_ context: inout GraphicsContext, size: CGSize, t: Double, dark: Bool, boost: Double = 1, tint: Color = .white) {
        let strength = dark ? 0.06 : 0.24
        let gradient = Gradient(colors: [tint.opacity(min(0.5, strength * boost)), tint.opacity(0)])
        for index in 0..<4 {
            let base = size.width * (0.1 + 0.25 * Double(index))
            let sway = reduceMotion ? 0 : sin(t * 0.18 + Double(index) * 1.7) * 18
            var path = Path()
            path.move(to: CGPoint(x: base + sway, y: -10))
            path.addLine(to: CGPoint(x: base + 50 + sway, y: -10))
            path.addLine(to: CGPoint(x: base + 190 + sway * 2, y: size.height * 0.7))
            path.addLine(to: CGPoint(x: base + 80 + sway * 2, y: size.height * 0.7))
            path.closeSubpath()
            context.fill(path, with: .linearGradient(gradient, startPoint: CGPoint(x: base, y: 0), endPoint: CGPoint(x: base + 120, y: size.height * 0.7)))
        }
    }

    private func drawAmbient(_ context: inout GraphicsContext, size: CGSize, t: Double, dark: Bool) {
        var outlines = Path()
        for index in 0..<12 {
            let seed = Double(index) + 40
            let sx = Self.fract(sin(seed * 12.9898) * 43758.5453)
            let sy = Self.fract(sin(seed * 78.233) * 12345.6789)
            let speed = 0.015 + 0.02 * Self.fract(sin(seed * 3.7) * 999.1)
            let radius = 1.5 + 2.6 * Self.fract(sin(seed * 9.1) * 777.7)
            let y = size.height * 0.66 * (1 - Self.fract(sy + (reduceMotion ? 0 : t) * speed))
            let x = size.width * sx + sin(t * 0.4 + seed) * 8
            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            if dark {
                let twinkle = 0.55 + 0.45 * sin(t * 0.9 + seed * 2)
                context.fill(Path(ellipseIn: rect.insetBy(dx: -radius, dy: -radius)), with: .color(Palette.seaBlue.opacity(0.12 * twinkle)))
                context.fill(Path(ellipseIn: rect), with: .color(Palette.sage.opacity(0.7 * twinkle)))
            } else {
                outlines.addEllipse(in: rect)
            }
        }
        if !dark { context.stroke(outlines, with: .color(.white.opacity(0.6)), lineWidth: 1) }
    }

    private func drawPlankton(_ context: inout GraphicsContext, t: Double) {
        guard !sim.plankton.isEmpty else { return }
        var cores = Path()
        for piece in sim.plankton {
            let twinkle = 0.7 + 0.3 * sin(t * 6 + piece.phase)
            let rect = CGRect(x: piece.position.x - 2.6, y: piece.position.y - 2.6, width: 5.2, height: 5.2)
            context.fill(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(Palette.sand.opacity(0.22 * twinkle)))
            cores.addEllipse(in: rect)
        }
        context.fill(cores, with: .color(Palette.sand.opacity(0.95)))
    }

    private func drawCaustics(_ context: inout GraphicsContext, size: CGSize, t: Double, floorY: Double) {
        var spots = Path()
        for index in 0..<7 {
            let i = Double(index)
            let x = size.width * (0.08 + 0.14 * i) + sin(t * 0.5 + i) * 14
            let y = floorY + 18 + sin(t * 0.4 + i * 2) * 8 + (i.truncatingRemainder(dividingBy: 2)) * 26
            spots.addEllipse(in: CGRect(x: x, y: y, width: 54, height: 12))
        }
        context.fill(spots, with: .color(.white.opacity(0.14)))
    }

    nonisolated static func fract(_ value: Double) -> Double { value - value.rounded(.down) }
}

private struct AquariumMask: View {
    @Environment(PageTracker.self) private var tracker: PageTracker?

    var body: some View {
        let position = tracker?.position ?? 2
        let fade = LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.16)], startPoint: .top, endPoint: .bottom)
        if abs(position - 2) < 0.0005 {
            fade
        } else {
            fade.mask(edge(position))
        }
    }

    private func edge(_ position: Double) -> LinearGradient {
        let entering = min(1, max(0, 2 - position))
        let overscroll = max(0, position - 2)
        let leading = entering < 0.001 ? 0.001 : 0.04 + 0.9 * entering
        let trailing = min(0.6, overscroll * 3)
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: leading),
                .init(color: .black, location: max(leading, 1 - trailing)),
                .init(color: trailing > 0.001 ? .clear : .black, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

final class DecorReactions {
    private var starts: [String: Double] = [:]

    private static let durations: [String: Double] = [
        "seaweed": 6, "pebbles": 3, "shells": 5, "bubbler": 5, "coral": 6, "glowMushroom": 5,
        "amphora": 3, "moonstone": 8, "shipwreck": 6.2, "starfish": 5, "chest": 5, "anemone": 6
    ]

    private static func duration(_ id: String) -> Double { durations[id] ?? 6 }

    @discardableResult
    func trigger(_ id: String, at time: Double) -> Bool {
        if let start = starts[id], time - start < Self.duration(id) { return false }
        starts[id] = time
        return true
    }

    func age(_ id: String, at time: Double) -> Double? {
        guard let start = starts[id] else { return nil }
        let age = time - start
        if age > Self.duration(id) {
            starts[id] = nil
            return nil
        }
        return max(0, age)
    }
}
