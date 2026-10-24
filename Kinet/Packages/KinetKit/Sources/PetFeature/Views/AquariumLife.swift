import KinetDesign
import SwiftUI

struct SpotInfo {
    var id: String
    var layer: Int
    var x: Double
    var halfWidth: Double
}

struct SchoolFish {
    var offset: Vec
    var phase: Double
}

struct FishSchool {
    var leader: Vec
    var direction: Double
    var speed: Double
    var baseY: Double
    var depth: Double
    var phase: Double
    var fish: [SchoolFish]
    var scale: Double
    var fear = 0.0
    var boost = 1.0
    var fleeing = false
}

struct JellyThreat {
    var position: Vec
    var depth: Double
    var isActive: Bool
}

struct Shrimp {
    var x: Double
    var layer: Int
    var direction: Double
    var speed: Double
    var phase = Double.random(in: 0...6.28)
    var cleaningLeft = 0.0
    var restLeft = 0.0
    var nextRest = Double.random(in: 4...9)
    var visited: Set<String> = []
    var entered = false
    var cleaningSide = 1.0
    var fear = 0.0
    var boost = 1.0
    var fleeing = false
}

final class AquariumLife {
    private(set) var schools: [FishSchool] = []
    private(set) var shrimps: [Shrimp] = []
    private(set) var time = 0.0
    private var lastDate: Date?
    private var schoolTimer = Double.random(in: 16...48)
    private var shrimpTimer = Double.random(in: 8...32)

    static let maxSchools = 2
    static let maxShrimps = 5

    func step(date: Date, size: CGSize, topY: Double, spots: [SpotInfo], layerBases: [Double], layerDepths: [Double], baseline: (Int, Double) -> Double, reduceMotion: Bool, jelly: JellyThreat) {
        let previous = lastDate ?? date
        lastDate = date
        let dt = min(0.05, max(0.001, date.timeIntervalSince(previous)))
        time += dt
        let width = Double(size.width)
        let height = Double(size.height)
        guard width > 0, height > 0 else { return }

        if !reduceMotion {
            schoolTimer -= dt
            if schoolTimer <= 0 {
                schoolTimer = Double.random(in: 16...48)
                if schools.count < Self.maxSchools { spawnSchool(width: width, height: height, topY: topY, layerBases: layerBases, layerDepths: layerDepths) }
            }
            shrimpTimer -= dt
            if shrimpTimer <= 0 {
                shrimpTimer = Double.random(in: 8...32)
                if shrimps.count < Self.maxShrimps { spawnShrimp(width: width) }
            }
        }

        if jelly.isActive {
            for index in schools.indices where !schools[index].fleeing && abs(schools[index].depth - jelly.depth) < 0.35 {
                let center = Vec(schools[index].leader.x - schools[index].direction * 40 * schools[index].scale, schools[index].leader.y)
                guard (center - jelly.position).length < 150 else { continue }
                schools[index].fear = 2.8
                schools[index].fleeing = true
                if (jelly.position.x - schools[index].leader.x) * schools[index].direction > 0 {
                    schools[index].direction *= -1
                    for fishIndex in schools[index].fish.indices { schools[index].fish[fishIndex].offset.x *= -1 }
                }
            }
        }
        for index in schools.indices {
            schools[index].fear = max(0, schools[index].fear - dt)
            schools[index].boost += ((schools[index].fleeing ? 3.0 : 1.0) - schools[index].boost) * min(1, dt * 6)
            let tremble = schools[index].fear > 2.3
            schools[index].leader.x += schools[index].direction * schools[index].speed * (tremble ? 0.1 : schools[index].boost) * dt
            schools[index].leader.y = schools[index].baseY + sin(time * 0.42 + schools[index].phase) * 16 * schools[index].scale
        }
        schools.removeAll { school in
            let trail = school.fish.reduce(0) { max($0, abs($1.offset.x)) } + 60
            return school.direction > 0 ? school.leader.x - trail > width : school.leader.x + trail < 0
        }

        let unit = width / 390
        for index in shrimps.indices {
            if jelly.isActive, !shrimps[index].fleeing, abs(layerDepths[shrimps[index].layer] - jelly.depth) < 0.4 {
                let ground = Vec(shrimps[index].x, baseline(shrimps[index].layer, shrimps[index].x))
                if (ground - jelly.position).length < 150 {
                    shrimps[index].fear = 2.2
                    shrimps[index].fleeing = true
                    shrimps[index].cleaningLeft = 0
                    shrimps[index].restLeft = 0
                    shrimps[index].direction = shrimps[index].x < jelly.position.x ? -1 : 1
                }
            }
            stepShrimp(&shrimps[index], dt: dt, width: width, unit: unit, spots: spots, layerScale: AquariumLife.layerScale(shrimps[index].layer))
        }
        shrimps.removeAll { shrimp in
            shrimp.entered && (shrimp.x < -50 || shrimp.x > width + 50)
        }
    }

    static func layerScale(_ layer: Int) -> Double {
        AquariumScene.layerScales[min(AquariumScene.layerCount - 1, max(0, layer))]
    }

    private func spawnSchool(width: Double, height: Double, topY: Double, layerBases: [Double], layerDepths: [Double]) {
        let layer = Int.random(in: 0..<layerDepths.count)
        let depth = max(0.05, layerDepths[layer] - 0.1)
        let scale = 1.3 * (1 - 0.4 * depth)
        let direction: Double = Bool.random() ? 1 : -1
        let low = topY + 50
        let high = max(low + 20, height * layerBases[layer] - 30)
        let count = Int.random(in: 3...5)
        let spacing = 36 * scale
        let fish = (0..<count).map { index in
            SchoolFish(
                offset: Vec(-direction * (Double(index) * spacing + Double.random(in: 0...12 * scale)), Double.random(in: -28...28) * scale),
                phase: Double.random(in: 0...6.28)
            )
        }
        schools.append(FishSchool(
            leader: Vec(direction > 0 ? -60 : width + 60, Double.random(in: low...high)),
            direction: direction,
            speed: Double.random(in: 30...52) * scale,
            baseY: Double.random(in: low...high),
            depth: depth,
            phase: Double.random(in: 0...6.28),
            fish: fish,
            scale: scale
        ))
    }

    private func spawnShrimp(width: Double) {
        let direction: Double = Bool.random() ? 1 : -1
        shrimps.append(Shrimp(
            x: direction > 0 ? -28 : width + 28,
            layer: Int.random(in: 0..<AquariumScene.layerCount),
            direction: direction,
            speed: Double.random(in: 12...18)
        ))
    }

    private func stepShrimp(_ shrimp: inout Shrimp, dt: Double, width: Double, unit: Double, spots: [SpotInfo], layerScale: Double) {
        if shrimp.x > 0 && shrimp.x < width { shrimp.entered = true }
        shrimp.nextRest -= dt
        if shrimp.fleeing {
            shrimp.fear = max(0, shrimp.fear - dt)
            shrimp.phase += dt * 16
            if shrimp.fear <= 1.75 {
                shrimp.x += shrimp.direction * shrimp.speed * 4.2 * unit * layerScale * dt
            }
            return
        }
        if shrimp.cleaningLeft > 0 {
            shrimp.cleaningLeft -= dt
            shrimp.phase += dt * 9
            return
        }
        if shrimp.restLeft > 0 {
            shrimp.restLeft -= dt
            shrimp.phase += dt * 2
            return
        }
        if shrimp.nextRest <= 0, shrimp.entered {
            shrimp.restLeft = Double.random(in: 0.8...2.2)
            shrimp.nextRest = Double.random(in: 5...12)
            return
        }
        let pulse = 0.55 + 0.45 * sin(shrimp.phase * 0.5)
        shrimp.phase += dt * 7
        shrimp.x += shrimp.direction * shrimp.speed * unit * layerScale * pulse * dt
        for spot in spots where spot.layer == shrimp.layer && !shrimp.visited.contains(spot.id) {
            let ahead = (spot.x - shrimp.x) * shrimp.direction
            if ahead > 0 && ahead < spot.halfWidth * 0.7 + 10 * unit {
                shrimp.visited.insert(spot.id)
                if Double.random(in: 0...1) < 0.7 {
                    shrimp.cleaningLeft = Double.random(in: 3...5)
                    shrimp.cleaningSide = shrimp.direction
                }
                break
            }
        }
    }
}

struct FishColors {
    let orange: Color
    let deep: Color
    let white: Color
    let fin: Color

    init(haze: Color, mix: Double) {
        orange = Color(red: 0.96, green: 0.52, blue: 0.22).mix(with: haze, by: mix)
        deep = Color(red: 0.78, green: 0.34, blue: 0.14).mix(with: haze, by: mix)
        white = Color.white.mix(with: haze, by: mix * 0.8)
        fin = orange.mix(with: .white, by: 0.15)
    }
}

struct ShrimpColors {
    let body: Color
    let back: Color
    let dark: Color
    let light: Color

    init(haze: Color, mix: Double) {
        body = Color(red: 0.95, green: 0.55, blue: 0.40).mix(with: haze, by: mix)
        back = Color(red: 0.99, green: 0.74, blue: 0.62).mix(with: haze, by: mix)
        dark = Color(red: 0.80, green: 0.36, blue: 0.28).mix(with: haze, by: mix)
        light = Color(red: 1.0, green: 0.82, blue: 0.72).mix(with: haze, by: mix * 0.5)
    }
}

enum FishShapes {
    static let body = Path(ellipseIn: CGRect(x: -14, y: -7.5, width: 28, height: 15))
    static let stripes: Path = {
        var bands = Path()
        bands.addRect(CGRect(x: -6, y: -9, width: 4.5, height: 18))
        bands.addRect(CGRect(x: 4, y: -9, width: 3.2, height: 18))
        return bands.intersection(body)
    }()
    static let seams: Path = {
        var lines = Path()
        lines.move(to: CGPoint(x: -6, y: -8))
        lines.addLine(to: CGPoint(x: -6, y: 8))
        lines.move(to: CGPoint(x: -1.5, y: -8))
        lines.addLine(to: CGPoint(x: -1.5, y: 8))
        return lines.strokedPath(StrokeStyle(lineWidth: 0.8)).intersection(body)
    }()
    static let dorsal: Path = {
        var path = Path()
        path.move(to: CGPoint(x: -4, y: -6))
        path.addQuadCurve(to: CGPoint(x: 8, y: -6), control: CGPoint(x: 2, y: -13))
        return path
    }()
    static let ink = Color(red: 0.08, green: 0.12, blue: 0.16)
}

enum ShrimpShapes {
    static let spine: [CGPoint] = [CGPoint(x: 7, y: -13), CGPoint(x: -1, y: -17), CGPoint(x: -9, y: -16), CGPoint(x: -15, y: -11), CGPoint(x: -17, y: -5), CGPoint(x: -13, y: -1)]

    static func spinePoint(_ t: Double) -> CGPoint {
        let scaled = t * Double(spine.count - 1)
        let index = min(spine.count - 2, Int(scaled))
        let f = scaled - Double(index)
        return CGPoint(x: spine[index].x + (spine[index + 1].x - spine[index].x) * f, y: spine[index].y + (spine[index + 1].y - spine[index].y) * f)
    }

    static let fan: Path = {
        var fan = Path()
        let tailBase = spinePoint(1)
        for lobe in 0..<3 {
            let angle = -0.35 + Double(lobe) * 0.45
            let tip = CGPoint(x: tailBase.x + cos(angle) * 10, y: tailBase.y + sin(angle) * 10 + 1.5)
            fan.move(to: tailBase)
            fan.addQuadCurve(to: tip, control: CGPoint(x: tailBase.x + cos(angle) * 6, y: tailBase.y + sin(angle) * 3 - 2.5))
            fan.addQuadCurve(to: tailBase, control: CGPoint(x: tailBase.x + cos(angle) * 5, y: tailBase.y + sin(angle) * 8 + 2.5))
        }
        return fan
    }()

    static let body: Path = {
        var body = Path()
        for step in 0...16 {
            let t = 1 - Double(step) / 16
            let center = spinePoint(t)
            let radius = t < 0.12 ? 7.0 : (3.2 + 3.0 * (1 - t))
            body.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        var head = Path()
        head.move(to: CGPoint(x: 9, y: -19))
        head.addLine(to: CGPoint(x: 24, y: -11.5))
        head.addQuadCurve(to: CGPoint(x: 10, y: -7), control: CGPoint(x: 17, y: -8))
        head.closeSubpath()
        body.addPath(head)
        return body
    }()

    static let segments: Path = {
        var path = Path()
        for index in 1..<5 {
            let t = 0.22 + Double(index) * 0.15
            let center = spinePoint(t)
            let next = spinePoint(t + 0.02)
            let normal = CGPoint(x: -(next.y - center.y), y: next.x - center.x)
            let length = max(0.001, hypot(normal.x, normal.y))
            let r = 3.2 + 3.0 * (1 - t)
            path.move(to: CGPoint(x: center.x + normal.x / length * r, y: center.y + normal.y / length * r))
            path.addLine(to: CGPoint(x: center.x - normal.x / length * r, y: center.y - normal.y / length * r))
        }
        return path
    }()

    static let ridge: Path = {
        var ridge = Path()
        for step in 0...12 {
            let point = spinePoint(0.1 + Double(step) / 12 * 0.8)
            let next = spinePoint(0.1 + Double(step) / 12 * 0.8 + 0.02)
            let normal = CGPoint(x: (next.y - point.y), y: -(next.x - point.x))
            let length = max(0.001, hypot(normal.x, normal.y))
            let r = 3.2 + 3.0 * (1 - (0.1 + Double(step) / 12 * 0.8)) - 1.6
            let lifted = CGPoint(x: point.x + normal.x / length * r, y: point.y + normal.y / length * r)
            if step == 0 { ridge.move(to: lifted) } else { ridge.addLine(to: lifted) }
        }
        return ridge
    }()

    static let crest: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 8, y: -19))
        path.addLine(to: CGPoint(x: 24, y: -11.5))
        return path
    }()

    static let ink = Color(red: 0.07, green: 0.1, blue: 0.14)
}

extension AquariumScene {
    func drawFishSchool(_ context: inout GraphicsContext, school: FishSchool, time: Double, haze: Color) {
        let colors = FishColors(haze: haze, mix: min(0.5, school.depth * 0.5))
        for fish in school.fish {
            let wobble = Vec(sin(time * 0.9 + fish.phase) * 4, cos(time * 0.7 + fish.phase) * 4) * school.scale
            let position = school.leader + fish.offset + wobble
            let swing = sin(time * 7 * (0.6 + school.speed * school.boost / 60) + fish.phase)
            let shake = school.fear > 2.3 ? Vec(sin(time * 70 + fish.phase) * 1.6, cos(time * 83 + fish.phase) * 1.2) * school.scale : Vec(0, 0)
            Self.drawFish(&context, at: (position + shake).point, direction: school.direction, scale: school.scale, swing: swing, colors: colors, scared: school.fleeing)
        }
    }

    static func drawFish(_ context: inout GraphicsContext, at point: CGPoint, direction: Double, scale: Double, swing: Double, colors: FishColors, scared: Bool = false) {
        var c = context
        c.translateBy(x: point.x, y: point.y)
        c.scaleBy(x: direction * scale, y: scale)
        c.rotate(by: .radians(swing * 0.04))

        var tail = Path()
        tail.move(to: CGPoint(x: -11, y: 0))
        tail.addQuadCurve(to: CGPoint(x: -22 + swing * 1.5, y: -8 + swing * 3), control: CGPoint(x: -17, y: -5 + swing * 2))
        tail.addQuadCurve(to: CGPoint(x: -22 + swing * 1.5, y: 8 + swing * 3), control: CGPoint(x: -19 + swing, y: 0 + swing * 3))
        tail.addQuadCurve(to: CGPoint(x: -11, y: 0), control: CGPoint(x: -17, y: 5 + swing * 2))
        tail.addPath(FishShapes.dorsal)
        c.fill(tail, with: .color(colors.deep))

        let flutter = sin(swing * 1.4 + 1) * 0.35
        var farFin = Path()
        farFin.move(to: CGPoint(x: 3, y: 0.5))
        farFin.addQuadCurve(to: CGPoint(x: -4 - flutter, y: -1.2 + flutter * 0.8), control: CGPoint(x: -1, y: -2.2))
        farFin.addQuadCurve(to: CGPoint(x: 3, y: 0.5), control: CGPoint(x: -1, y: 0.8))
        c.fill(farFin, with: .color(colors.deep.opacity(0.8)))

        c.fill(FishShapes.body, with: .color(colors.orange))
        c.fill(FishShapes.stripes, with: .color(colors.white))
        c.fill(FishShapes.seams, with: .color(colors.deep.opacity(0.7)))
        var nearFin = Path()
        nearFin.move(to: CGPoint(x: 4, y: 1.8))
        nearFin.addQuadCurve(to: CGPoint(x: -4 - flutter, y: 3.6 + flutter * 1.2), control: CGPoint(x: 0, y: 4.4))
        nearFin.addQuadCurve(to: CGPoint(x: 4, y: 1.8), control: CGPoint(x: -1, y: 2.2))
        c.fill(nearFin, with: .color(colors.fin))
        c.stroke(nearFin, with: .color(colors.deep.opacity(0.6)), lineWidth: 0.5)
        if scared {
            c.fill(Path(ellipseIn: CGRect(x: 8.0, y: -3.9, width: 4.8, height: 4.8)), with: .color(.white))
            c.fill(Path(ellipseIn: CGRect(x: 8.0 + 1.75, y: -3.9 + 1.75, width: 1.3, height: 1.3)), with: .color(FishShapes.ink))
        } else {
            c.fill(Path(ellipseIn: CGRect(x: 8.0, y: -3.9, width: 3.6, height: 3.6)), with: .color(colors.deep.opacity(0.55)))
            c.fill(Path(ellipseIn: CGRect(x: 8.4, y: -3.5, width: 2.8, height: 2.8)), with: .color(FishShapes.ink))
            c.fill(Path(ellipseIn: CGRect(x: 9.7, y: -3.3, width: 0.9, height: 0.9)), with: .color(.white.opacity(0.7)))
        }
    }

    func drawShrimps(_ context: inout GraphicsContext, layer: Int, life: AquariumLife, size: CGSize, time: Double, haze: Color) {
        guard life.shrimps.contains(where: { $0.layer == layer }) else { return }
        let unit = Double(size.width) / 390
        let colors = ShrimpColors(haze: haze, mix: 0.12 * Double(4 - layer) / 4)
        for shrimp in life.shrimps where shrimp.layer == layer {
            let scale = unit * Self.layerScales[layer] * 0.72
            let x = shrimp.x
            let y = Self.baseline(layer: layer, x: x, size: size) + 5 * scale
            let slope = (Self.baseline(layer: layer, x: x + 4, size: size) - Self.baseline(layer: layer, x: x - 4, size: size)) / 8
            let scared = shrimp.fleeing
            let shake = shrimp.fear > 1.75 ? sin(time * 75) * 1.3 * scale : 0
            Self.drawShrimp(
                &context, at: CGPoint(x: x + shake, y: y), direction: shrimp.direction, scale: scale, tilt: atan(slope) * shrimp.direction,
                phase: shrimp.phase, cleaning: shrimp.cleaningLeft > 0, resting: shrimp.restLeft > 0, playing: scared && shrimp.fear > 1.75,
                scared: scared, time: time, colors: colors
            )
        }
    }

    static func drawShrimp(_ context: inout GraphicsContext, at point: CGPoint, direction: Double, scale: Double, tilt: Double, phase: Double, cleaning: Bool, resting: Bool, playing: Bool, scared: Bool = false, time: Double, colors: ShrimpColors) {
        var c = context
        c.translateBy(x: point.x, y: point.y)
        c.scaleBy(x: direction * scale, y: scale)
        c.rotate(by: .radians(tilt))
        if cleaning { c.rotate(by: .radians(sin(phase * 0.8) * 0.05)) }
        let moving = (!cleaning && !resting && !playing) || scared

        var legs = Path()
        for index in 0..<5 {
            let x = 11.0 - Double(index) * 2.8
            let reach = index == 0 ? 6.0 : 3.0
            let swing = moving ? sin(phase + Double(index) * 1.3) * 3 : (cleaning ? sin(phase * 0.5 + Double(index)) * 0.8 : 0)
            legs.move(to: CGPoint(x: x, y: -9))
            legs.addQuadCurve(to: CGPoint(x: x + reach + swing, y: 0), control: CGPoint(x: x + reach + 3, y: -6))
        }
        c.stroke(legs, with: .color(colors.back), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))

        c.fill(ShrimpShapes.fan, with: .color(colors.dark))
        c.fill(ShrimpShapes.body, with: .color(colors.body))
        c.stroke(ShrimpShapes.segments, with: .color(colors.dark.opacity(0.7)), lineWidth: 0.9)
        c.stroke(ShrimpShapes.ridge, with: .color(colors.light.opacity(0.8)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        c.stroke(ShrimpShapes.crest, with: .color(colors.light.opacity(0.7)), lineWidth: 1)
        let eyeR = scared ? 6.0 : 4.2
        c.fill(Path(ellipseIn: CGRect(x: 11.5 - (eyeR - 4.2) / 2, y: -16 - (eyeR - 4.2) / 2, width: eyeR, height: eyeR)), with: .color(scared ? .white : ShrimpShapes.ink))
        if scared { c.fill(Path(ellipseIn: CGRect(x: 12.7, y: -15.2, width: 2.0, height: 2.0)), with: .color(ShrimpShapes.ink)) } else { c.fill(Path(ellipseIn: CGRect(x: 13.2, y: -15.4, width: 1.4, height: 1.4)), with: .color(.white)) }

        let wiggle = scared ? 4.5 : (cleaning ? 3.0 : (resting ? 1.8 : 1.2))
        var antennae = Path()
        for side in 0..<2 {
            let reach = side == 0 ? 1.0 : 0.75
            antennae.move(to: CGPoint(x: 22, y: -12.5))
            antennae.addCurve(
                to: CGPoint(x: 22 + 30 * reach, y: -26 - 4 * Double(side) + sin(time * 2.4 + Double(side) * 1.9) * wiggle),
                control1: CGPoint(x: 30, y: -13 + sin(time * 2.8 + Double(side)) * wiggle),
                control2: CGPoint(x: 40 * reach, y: -20 + cos(time * 2.2 + Double(side)) * wiggle)
            )
        }
        c.stroke(antennae, with: .color(colors.light), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))

        var arms = Path()
        var claws = Path()
        for index in 0..<2 {
            let lift = cleaning ? sin(phase * 1.3 + Double(index) * 1.4) * 3.2 : sin(time * 1.6 + Double(index)) * 0.8
            arms.move(to: CGPoint(x: 15, y: -8))
            arms.addQuadCurve(to: CGPoint(x: 25 + Double(index) * 3 + lift, y: -3 + Double(index) * 2.5 + lift * 0.4), control: CGPoint(x: 20, y: -10))
            claws.addEllipse(in: CGRect(x: 24 + Double(index) * 3 + lift, y: -4.2 + Double(index) * 2.5 + lift * 0.4, width: 2.6, height: 2.6))
        }
        c.stroke(arms, with: .color(colors.back), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        c.fill(claws, with: .color(colors.back))
    }
}
