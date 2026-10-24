import KinetDesign
import SwiftUI

struct JellyfishAppearance {
    var skinID: String
    var mood: Mood
    var scale: Double
    var tentacles: Int
    var glow: Double
}

enum JellyfishRenderer {
    static let ink = Color(red: 0.06, green: 0.15, blue: 0.19)

    private static func rgb(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    static func colors(skinID: String, time: Double, mood: Mood) -> (primary: Color, secondary: Color) {
        var pair: (Color, Color)
        switch skinID {
        case "sageSkin": pair = (rgb(0xC8896A), rgb(0xEBBE9C))
        case "sandSkin": pair = (rgb(0x7A92AD), rgb(0xB6C8D8))
        case "opalSkin": pair = (rgb(0x8A78DA), rgb(0xBBA8F2))
        default: pair = (rgb(0x3E9C9A), rgb(0x86CCC2))
        }
        let shimmer = 0.5 + 0.5 * sin(time * 0.35)
        var primary = pair.0.mix(with: pair.1, by: 0.12 + 0.28 * shimmer)
        var secondary = pair.1.mix(with: .white, by: 0.25)
        switch mood {
        case .sleepy:
            primary = primary.mix(with: Palette.mist, by: 0.32)
            secondary = secondary.mix(with: Palette.mist, by: 0.25)
        case .radiant:
            primary = primary.mix(with: .white, by: 0.18)
            secondary = secondary.mix(with: .white, by: 0.3)
        default: break
        }
        return (primary, secondary)
    }

    static func smoothClosed(_ points: [CGPoint]) -> Path {
        var path = Path()
        let count = points.count
        guard count > 3 else { return path }
        path.move(to: points[0])
        for index in 0..<count {
            let p0 = points[(index - 1 + count) % count]
            let p1 = points[index]
            let p2 = points[(index + 1) % count]
            let p3 = points[(index + 2) % count]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }

    static func draw(in canvas: inout GraphicsContext, sim: JellyfishSimulation, appearance: JellyfishAppearance, time: Double, haze: Color = Palette.seaBlue) {
        var context = canvas
        let scale = sim.effectiveScale
        let distance = sim.depth
        context.opacity = 1 - 0.3 * distance
        var palette = colors(skinID: appearance.skinID, time: time, mood: appearance.mood)
        palette = (palette.primary.mix(with: haze, by: 0.16 + 0.4 * distance), palette.secondary.mix(with: haze, by: 0.16 + 0.4 * distance))
        let half = 50 * scale * sim.widthFactor()
        let height = 70 * scale * sim.heightFactor()
        let center = sim.world(Vec(0, -height * 0.5), scale: scale)

        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 130 * scale, y: center.y - 130 * scale, width: 260 * scale, height: 260 * scale)),
            with: .radialGradient(
                Gradient(colors: [palette.primary.opacity(0.42 * appearance.glow), palette.primary.opacity(0)]),
                center: center.point, startRadius: 4, endRadius: 130 * scale
            )
        )


        var outline: [CGPoint] = []
        let topSteps = 16
        for index in 0...topSteps {
            let u = Double(index) / Double(topSteps)
            let theta = Double.pi - u * Double.pi
            let local = Vec(cos(theta) * half, -pow(sin(theta), 0.8) * height)
            let weight = 1 - 0.78 * sin(theta)
            let point = sim.world(local, scale: scale) + sim.rimDisplacement(at: cos(theta)) * weight + sim.wobble * (0.3 * sin(theta))
            outline.append(point.point)
        }
        let rimSteps = 24
        for index in 1..<rimSteps {
            let t = 1 - 2 * Double(index) / Double(rimSteps)
            let scallop = sin(t * .pi * 4 + time * 1.6) * 2.4 * scale * (1 - 0.5 * sim.contraction) + 2 * scale
            let point = sim.world(Vec(t * half, scallop), scale: scale) + sim.rimDisplacement(at: t)
            outline.append(point.point)
        }
        let bell = smoothClosed(outline)
        var chainContext = context
        chainContext.clip(to: bell, options: .inverse)
        drawChains(in: &chainContext, sim: sim, palette: palette, front: false)

        var brain = context
        brain.clip(to: bell)
        let cubeAmount = abs(sin(sim.spin / 2))
        let yaw = sim.spin
        let tilt = 0.45 * cubeAmount
        var cube: [(x: Double, y: Double, z: Double, back: Bool)] = []
        for sx in [-1.0, 1.0] {
            for sy in [-1.0, 1.0] {
                for sz in [-1.0, 1.0] {
                    let x1 = sx * cos(yaw) + sz * sin(yaw)
                    let z1 = -sx * sin(yaw) + sz * cos(yaw)
                    let y1 = sy * cos(tilt) - z1 * sin(tilt)
                    let z2 = sy * sin(tilt) + z1 * cos(tilt)
                    cube.append((x1, y1, z2, sz < 0))
                }
            }
        }
        for corner in cube.sorted(by: { $0.z < $1.z }) {
            let visibility = corner.back ? min(1, cubeAmount * 4) : 1
            guard visibility > 0.01 else { continue }
            let depth = (corner.z + 1.7) / 3.4
            let local = Vec(corner.x * half * 0.2, -height * 0.55 + corner.y * height * 0.12)
            let anchor = sim.world(local, scale: scale) + sim.rimDisplacement(at: local.x / max(half, 1)) * 0.45
            let radius = half * (0.085 + 0.03 * depth * cubeAmount)
            let dot = Path(ellipseIn: CGRect(x: anchor.x - radius, y: anchor.y - radius, width: radius * 2, height: radius * 2))
            brain.fill(dot, with: .color(.white.opacity((0.2 + 0.08 * cubeAmount * depth) * visibility)))
        }

        context.fill(bell, with: .radialGradient(
            Gradient(stops: [
                .init(color: palette.secondary.opacity(0.5), location: 0),
                .init(color: palette.primary.opacity(0.78), location: 0.62),
                .init(color: palette.primary.opacity(0.96), location: 1)
            ]),
            center: center.point, startRadius: 0, endRadius: half * 1.4
        ))

        let stripeFacing = cos(sim.spin - 0.35)
        if stripeFacing > 0.02 {
            var stripe = Path()
            let steps = 12
            for index in 0...steps {
                let f = Double(index) / Double(steps)
                let theta = 2.5 - f * 0.86
                let weight = 1 - 0.78 * sin(theta)
                let k = 0.88
                let base = sim.world(Vec(cos(theta) * half * cos(sim.spin) * k, -pow(sin(theta), 0.8) * height * k), scale: scale)
                let point = (base + sim.rimDisplacement(at: cos(theta)) * (weight * k) + sim.wobble * (0.3 * sin(theta) * k)).point
                if index == 0 { stripe.move(to: point) } else { stripe.addLine(to: point) }
            }
            var clipped = context
            clipped.clip(to: bell)
            clipped.stroke(stripe, with: .color(.white.opacity(0.5 * min(1, stripeFacing * 3))), style: StrokeStyle(lineWidth: 3.4 * scale, lineCap: .round, lineJoin: .round))
        }
        context.stroke(bell, with: .color(palette.secondary.opacity(0.7)), lineWidth: 1.4)

        drawChains(in: &chainContext, sim: sim, palette: palette, front: true)
        drawFace(in: &context, sim: sim, appearance: appearance, half: half, height: height, time: time)
    }

    static func place(_ path: Path, local: Vec, sim: JellyfishSimulation, scale: Double) -> Path {
        let half = 50 * scale * sim.widthFactor()
        var local = local
        var shape = path
        if sim.spin != 0 {
            let projected = sim.spinProject(local.x / max(half, 1))
            guard projected.depth > 0.05 else { return Path() }
            local.x = projected.t * half
            shape = path.applying(CGAffineTransform(scaleX: max(0.2, projected.depth), y: 1))
        }
        let anchor = sim.world(local, scale: scale) + sim.rimDisplacement(at: local.x / max(half, 1)) * 0.45
        return shape.applying(CGAffineTransform(rotationAngle: sim.renderAngle).concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y)))
    }

    private static func drawChains(in context: inout GraphicsContext, sim: JellyfishSimulation, palette: (primary: Color, secondary: Color), front: Bool) {
        let scale = sim.effectiveScale
        guard sim.chains.count == sim.specs.count else { return }
        let order = sim.specs.indices.filter { index in
            let spec = sim.specs[index]
            let isFront = !spec.isArm && spec.layer == 2 && (sim.ringBlend < 0.01 || sim.anchorDepth(index: index) > 0)
            return front ? isFront : !isFront
        }.sorted { sim.specs[$0].layer < sim.specs[$1].layer }
        guard !order.isEmpty else { return }
        let strand = palette.primary.mix(with: palette.secondary, by: 0.45)
        for index in order {
            let spec = sim.specs[index]
            let color = spec.isArm ? palette.secondary : strand
            let frontFade = spec.isArm ? 1 - sim.ringBlend : 1.0
            let shade = frontFade * (sim.ringBlend > 0.01 && !spec.isArm ? (1 - 0.4 * sim.ringBlend * (0.5 - 0.5 * sim.anchorDepth(index: index))) : 1.0)
            let chain = sim.chains[index]
            let path = ribbon(chain, width: spec.width * scale)
            context.fill(path, with: .linearGradient(
                Gradient(colors: [color.opacity(spec.alpha * shade), color.opacity(spec.alpha * 0.1 * shade)]),
                startPoint: chain.first?.point ?? .zero,
                endPoint: chain.last?.point ?? .zero
            ))
        }
    }

    static func ribbon(_ chain: [Vec], width: Double) -> Path {
        let count = chain.count
        guard count > 2 else { return Path() }
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for index in 0..<count {
            var tangent = chain[min(count - 1, index + 1)] - chain[max(0, index - 1)]
            let length = max(tangent.length, 0.0001)
            tangent /= length
            let normal = Vec(-tangent.y, tangent.x)
            let t = Double(index) / Double(count - 1)
            let half = (width * (1 - 0.88 * pow(t, 0.85)) + 0.5) / 2
            left.append((chain[index] + normal * half).point)
            right.append((chain[index] - normal * half).point)
        }
        var path = Path()
        path.move(to: left[0])
        appendSmooth(&path, left)
        path.addLine(to: right[count - 1])
        appendSmooth(&path, Array(right.reversed()))
        path.closeSubpath()
        return path
    }

    private static func appendSmooth(_ path: inout Path, _ points: [CGPoint]) {
        let count = points.count
        for index in 0..<(count - 1) {
            let p0 = points[max(0, index - 1)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(count - 1, index + 2)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
    }

    private static func drawFace(in context: inout GraphicsContext, sim: JellyfishSimulation, appearance: JellyfishAppearance, half: Double, height: Double, time: Double) {
        let scale = sim.effectiveScale
        let mood = appearance.mood
        let surprised = sim.surprise > 0
        let eyeCenterY = -height * 0.42
        let eyeX = half * 0.21
        if let expression = sim.expression, sim.expressionFade > 0.35 {
            drawExpression(expression, in: &context, sim: sim, half: half, height: height, time: time)
            return
        }
        let drowsyAwake = sim.drowsy > 0.5 && sim.asleepAmount < 0.5
        let yawnCycle = time.truncatingRemainder(dividingBy: 9)
        let yawn = drowsyAwake && yawnCycle < 1.8 ? sin(.pi * yawnCycle / 1.8) : 0
        let open = sim.eyeOpenness
        for side in [-1.0, 1.0] {
            let local = Vec(side * eyeX + sim.look.x, eyeCenterY + sim.look.y)
            if sim.asleepAmount > 0.5 {
                var arc = Path()
                arc.move(to: CGPoint(x: -4.5 * scale, y: 0))
                arc.addQuadCurve(to: CGPoint(x: 4.5 * scale, y: 0), control: CGPoint(x: 0, y: 4.5 * scale))
                context.stroke(place(arc, local: local, sim: sim, scale: scale), with: .color(ink.opacity(0.8)), style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round))
            } else if mood == .radiant && !surprised && sim.drowsy < 0.5 {
                var arc = Path()
                arc.move(to: CGPoint(x: -4.5 * scale, y: 1.5 * scale))
                arc.addQuadCurve(to: CGPoint(x: 4.5 * scale, y: 1.5 * scale), control: CGPoint(x: 0, y: -5 * scale))
                context.stroke(place(arc, local: local, sim: sim, scale: scale), with: .color(ink.opacity(0.85)), style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round))
            } else {
                let lid = sim.drowsy > 0.5 ? max(0.06, (0.14 + 0.2 * (0.5 + 0.5 * sin(time * 0.9))) * (1 - 0.85 * yawn)) : (mood == .calm ? 0.62 : 1.0)
                let grow = surprised ? 1.3 : 1.0
                let w = 8 * scale * grow
                let h = 10.5 * scale * grow * open * lid
                let eye = Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: max(0.8, h)))
                context.fill(place(eye, local: local, sim: sim, scale: scale), with: .color(ink.opacity(0.88)))
                if open > 0.5 {
                    let shine = Path(ellipseIn: CGRect(x: -w * 0.3, y: -h * 0.36, width: w * 0.34, height: w * 0.34))
                    context.fill(place(shine, local: local, sim: sim, scale: scale), with: .color(.white.opacity(0.9)))
                }
            }
            if mood >= .happy {
                let blush = Path(ellipseIn: CGRect(x: -5 * scale, y: -3 * scale, width: 10 * scale, height: 6 * scale))
                context.fill(place(blush, local: Vec(side * half * 0.34, -height * 0.28), sim: sim, scale: scale), with: .color(Palette.coral.opacity(0.4)))
            }
        }
        let mouthLocal = Vec(sim.look.x * 0.6, -height * 0.27 + sim.look.y * 0.5)
        if yawn > 0.05 {
            let mouth = Path(ellipseIn: CGRect(x: -(3 + 2 * yawn) * scale, y: -2 * scale, width: (6 + 4 * yawn) * scale, height: (2 + 9 * yawn) * scale))
            context.fill(place(mouth, local: mouthLocal, sim: sim, scale: scale), with: .color(ink.opacity(0.8)))
        } else if surprised || sim.munch > 0.05 || sim.mouthOpen > 0.4 {
            let chewing = sim.munch > 0.05
            let open = surprised ? 1.0 : (chewing ? 0.25 + 0.75 * abs(sin(time * 11)) : 0.7)
            let mouth = Path(ellipseIn: CGRect(x: -(3.4 + 1.2 * open) * scale, y: -2 * scale, width: (6.8 + 2.4 * open) * scale, height: (2.5 + 6 * open) * scale))
            context.fill(place(mouth, local: mouthLocal, sim: sim, scale: scale), with: .color(ink.opacity(0.8)))
        } else {
            let smile = sim.smile
            let widthM = (9 + 6 * smile) * scale
            var curve = Path()
            curve.move(to: CGPoint(x: -widthM / 2, y: 0))
            curve.addQuadCurve(to: CGPoint(x: widthM / 2, y: 0), control: CGPoint(x: 0, y: (2.2 + 7 * smile) * scale))
            context.stroke(place(curve, local: mouthLocal, sim: sim, scale: scale), with: .color(ink.opacity(0.8)), style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round))
        }
        if sim.asleepAmount > 0.5 {
            for index in 0..<2 {
                let phase = (time * 0.18 + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
                let origin = sim.world(Vec(half * 0.55 + phase * 14 * scale, -height * 0.85 - phase * 34 * scale), scale: scale)
                context.draw(
                    Text("z").font(.system(size: (10 + 6 * Double(index)) * scale, weight: .semibold, design: .rounded)).foregroundStyle(Palette.ink.opacity(0.7 * (1 - phase))),
                    at: origin.point
                )
            }
        }
    }
}
