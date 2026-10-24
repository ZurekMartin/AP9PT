import KinetDesign
import SwiftUI

extension JellyfishRenderer {
    static func starPath(radius: Double, rotation: Double = 0) -> Path {
        var path = Path()
        for index in 0..<8 {
            let angle = rotation + Double(index) * .pi / 4
            let r = index % 2 == 0 ? radius : radius * 0.32
            let point = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    static func drawExpression(_ expression: JellyfishSimulation.Expression, in context: inout GraphicsContext, sim: JellyfishSimulation, half: Double, height: Double, time: Double) {
        let scale = sim.effectiveScale
        let fade = sim.expressionFade
        let eyeY = -height * 0.42
        let eyeX = half * 0.21
        let mouthLocal = Vec(sim.look.x * 0.6, -height * 0.27 + sim.look.y * 0.5)

        func stroke(_ path: Path, local: Vec, width: Double = 1.9, alpha: Double = 0.85) {
            context.stroke(place(path, local: local, sim: sim, scale: scale), with: .color(ink.opacity(alpha)), style: StrokeStyle(lineWidth: width * scale, lineCap: .round))
        }
        func fill(_ path: Path, local: Vec, color: Color) {
            context.fill(place(path, local: local, sim: sim, scale: scale), with: .color(color))
        }
        func eye(local: Vec, width: Double, height eyeHeight: Double, shift: Vec = Vec(0, 0), shine: Bool = true) {
            let w = width * scale
            let h = eyeHeight * scale * max(0.1, sim.eyeOpenness)
            fill(Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: max(0.8, h))), local: local + shift, color: ink.opacity(0.9))
            if sim.eyeOpenness > 0.5 && shine {
                fill(Path(ellipseIn: CGRect(x: -w * 0.3, y: -h * 0.36, width: w * 0.34, height: w * 0.34)), local: local + shift, color: .white.opacity(0.92))
            }
        }
        func blush() {
            for side in [-1.0, 1.0] {
                fill(Path(ellipseIn: CGRect(x: -5 * scale, y: -3 * scale, width: 10 * scale, height: 6 * scale)), local: Vec(side * half * 0.34, -height * 0.28), color: Palette.coral.opacity(0.4))
            }
        }
        func sparkle(at point: CGPoint, radius: Double, rotation: Double, alpha: Double) {
            var c = context
            c.translateBy(x: point.x, y: point.y)
            c.fill(starPath(radius: radius, rotation: rotation), with: .color(Color.white.opacity(alpha)))
        }

        switch expression {
        case .thinking:
            for side in [-1.0, 1.0] {
                eye(local: Vec(side * eyeX + sim.look.x, eyeY + sim.look.y), width: 7.5, height: 9, shift: Vec(2.6 * scale, -2.4 * scale))
            }
            var mouth = Path()
            mouth.move(to: CGPoint(x: -3.5 * scale, y: 1 * scale))
            mouth.addQuadCurve(to: CGPoint(x: 4 * scale, y: -0.6 * scale), control: CGPoint(x: 0, y: 2 * scale))
            stroke(mouth, local: mouthLocal + Vec(2 * scale, 0), width: 1.7)
            let head = sim.world(Vec(half * 0.1, -height * 0.95), scale: scale)
            let lag = Vec(max(-14, min(14, -sim.smoothVelocity.x * 0.12)), max(-8, min(8, -sim.smoothVelocity.y * 0.08))) * scale
            let lean = sin(sim.renderAngle) * height * 0.5
            let anchor = head + Vec(half * 0.5 + lean, -height * 0.1) + lag
            let cycle = (time * 0.45).truncatingRemainder(dividingBy: 1)
            let reveal = min(1, cycle * 4)
            let outline = 1.1 * scale
            let small: [(Double, Double, Double)] = [(0.0, 0.0, 1.8), (6.0, -6.5, 3.0)]
            for (index, item) in small.enumerated() {
                let appear = max(0, min(1, reveal * 3 - Double(index)))
                let r = item.2 * scale * appear
                let center = anchor + Vec(item.0, item.1) * scale + Vec(sin(time * 1.4 + Double(index)) * 1.1 * scale, 0)
                context.fill(Path(ellipseIn: CGRect(x: center.x - r - outline, y: center.y - r - outline, width: (r + outline) * 2, height: (r + outline) * 2)), with: .color(ink.opacity(0.85 * fade)))
                context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(fade)))
            }
            let cloudCenter = anchor + Vec(23 * scale, -23 * scale + sin(time * 1.1) * 1.2 * scale)
            let grow = max(0, min(1, reveal * 3 - 2)) * fade
            let pulse = 1 + 0.025 * sin(time * 2)
            let lobes: [(Double, Double, Double)] = [(-15, 1, 6), (-10, -5.5, 6.5), (-2, -8, 7.5), (7, -6.5, 6.5), (14, -1.5, 6), (12, 4.5, 5.5), (4, 6.5, 6), (-5, 6, 6), (-12, 5, 5.5)]
            let k = scale * pulse * grow
            for lobe in lobes {
                let r = lobe.2 * k + outline * grow
                context.fill(Path(ellipseIn: CGRect(x: cloudCenter.x + lobe.0 * k - r, y: cloudCenter.y + lobe.1 * k - r, width: r * 2, height: r * 2)), with: .color(ink.opacity(0.85 * fade)))
            }
            context.fill(Path(ellipseIn: CGRect(x: cloudCenter.x - 16 * k - outline, y: cloudCenter.y - 8.5 * k - outline, width: 32 * k + outline * 2, height: 17 * k + outline * 2)), with: .color(ink.opacity(0.85 * fade)))
            for lobe in lobes {
                let r = lobe.2 * k
                context.fill(Path(ellipseIn: CGRect(x: cloudCenter.x + lobe.0 * k - r, y: cloudCenter.y + lobe.1 * k - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(fade)))
            }
            context.fill(Path(ellipseIn: CGRect(x: cloudCenter.x - 16 * k, y: cloudCenter.y - 8.5 * k, width: 32 * k, height: 17 * k)), with: .color(.white.opacity(fade)))
            for dot in 0..<3 {
                let wave = 0.5 + 0.5 * sin(time * 3.2 - Double(dot) * 1.0)
                let r = (1.3 + 0.8 * wave) * scale * grow
                context.fill(Path(ellipseIn: CGRect(x: cloudCenter.x + (Double(dot) - 1) * 6.5 * scale - r, y: cloudCenter.y - r, width: r * 2, height: r * 2)), with: .color(ink.opacity((0.4 + 0.45 * wave) * fade)))
            }
        case .dreaming:
            for side in [-1.0, 1.0] {
                var arc = Path()
                arc.move(to: CGPoint(x: -4.5 * scale, y: 0))
                arc.addQuadCurve(to: CGPoint(x: 4.5 * scale, y: 0), control: CGPoint(x: 0, y: 4.5 * scale))
                stroke(arc, local: Vec(side * eyeX + sim.look.x, eyeY + sim.look.y), width: 1.8, alpha: 0.8)
            }
            var smile = Path()
            smile.move(to: CGPoint(x: -4 * scale, y: 0))
            smile.addQuadCurve(to: CGPoint(x: 4 * scale, y: 0), control: CGPoint(x: 0, y: 4.2 * scale))
            stroke(smile, local: mouthLocal, width: 1.6, alpha: 0.75)
            blush()
            for index in 0..<3 {
                let phase = (time * 0.22 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                let origin = sim.world(Vec(half * (0.2 + 0.45 * Double(index) - 0.4) + sin(time + Double(index) * 2) * 6 * scale, -height * 1.0 - phase * 46 * scale), scale: scale)
                sparkle(at: origin.point, radius: (3.2 + Double(index)) * scale, rotation: time * 0.6 + Double(index), alpha: 0.8 * sin(phase * .pi) * fade)
            }
        case .astonished:
            for side in [-1.0, 1.0] {
                eye(local: Vec(side * eyeX + sim.look.x, eyeY + sim.look.y), width: 10.5, height: 13.5)
            }
            fill(Path(ellipseIn: CGRect(x: -3 * scale, y: -2.5 * scale, width: 6 * scale, height: 7.5 * scale)), local: mouthLocal, color: ink.opacity(0.82))
            for index in 0..<3 {
                let a = -Double.pi / 2 + (Double(index) - 1) * 0.5
                let start = sim.world(Vec(cos(a) * half * 1.05, sin(a) * height * 1.05 - height * 0.05), scale: scale)
                let end = sim.world(Vec(cos(a) * half * 1.3, sin(a) * height * 1.28 - height * 0.05), scale: scale)
                var ray = Path()
                ray.move(to: start.point)
                ray.addLine(to: end.point)
                context.stroke(ray, with: .color(ink.opacity(0.55 * fade)), style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round))
            }
        case .curious:
            eye(local: Vec(-eyeX + sim.look.x, eyeY + sim.look.y), width: 9.5, height: 12, shift: Vec(1.6 * scale, -1.6 * scale))
            eye(local: Vec(eyeX + sim.look.x, eyeY + sim.look.y), width: 6.5, height: 8, shift: Vec(1.6 * scale, -1.2 * scale))
            var brow = Path()
            brow.move(to: CGPoint(x: -4.5 * scale, y: 0))
            brow.addQuadCurve(to: CGPoint(x: 4.5 * scale, y: -1.5 * scale), control: CGPoint(x: 0, y: -3.5 * scale))
            stroke(brow, local: Vec(-eyeX, eyeY - 11 * scale), width: 1.6, alpha: 0.75)
            var lowBrow = Path()
            lowBrow.move(to: CGPoint(x: -3 * scale, y: 0))
            lowBrow.addQuadCurve(to: CGPoint(x: 3 * scale, y: 0.6 * scale), control: CGPoint(x: 0, y: -1 * scale))
            stroke(lowBrow, local: Vec(eyeX + 3 * scale, eyeY - 8.8 * scale), width: 1.3, alpha: 0.7)
            var smile = Path()
            smile.move(to: CGPoint(x: -3.5 * scale, y: 0.5 * scale))
            smile.addQuadCurve(to: CGPoint(x: 4.5 * scale, y: -1 * scale), control: CGPoint(x: 0.5 * scale, y: 3.8 * scale))
            stroke(smile, local: mouthLocal + Vec(1.5 * scale, 0), width: 1.7)
            for index in 0..<3 {
                let phase = (time * 0.28 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                let origin = sim.world(Vec(half * (0.2 + 0.5 * Double(index)) - half * 0.3 + sin(time * 1.8 + Double(index) * 2) * 5 * scale, -height * 1.05 - phase * 44 * scale), scale: scale)
                var c = context
                c.translateBy(x: origin.x, y: origin.y)
                c.rotate(by: .radians(sin(time * 2.2 + Double(index) * 1.7) * 0.28))
                c.draw(
                    Text("?").font(.system(size: (13 + 4 * Double(index % 2)) * scale, weight: .bold, design: .rounded)).foregroundStyle(Palette.ink.opacity(0.85 * sin(phase * .pi) * fade)),
                    at: .zero
                )
            }
        case .joy:
            for side in [-1.0, 1.0] {
                var arc = Path()
                arc.move(to: CGPoint(x: -4.5 * scale, y: 1.5 * scale))
                arc.addQuadCurve(to: CGPoint(x: 4.5 * scale, y: 1.5 * scale), control: CGPoint(x: 0, y: -5 * scale))
                stroke(arc, local: Vec(side * eyeX + sim.look.x, eyeY + sim.look.y), width: 2, alpha: 0.9)
            }
            var mouth = Path()
            mouth.move(to: CGPoint(x: -6 * scale, y: -1 * scale))
            mouth.addLine(to: CGPoint(x: 6 * scale, y: -1 * scale))
            mouth.addQuadCurve(to: CGPoint(x: -6 * scale, y: -1 * scale), control: CGPoint(x: 0, y: 11 * scale))
            fill(mouth, local: mouthLocal, color: ink.opacity(0.82))
            blush()
            for index in 0..<3 {
                let a = time * 2.2 + Double(index) * 2.09
                let origin = sim.world(Vec(cos(a) * half * 1.15, sin(a) * height * 0.5 - height * 0.5), scale: scale)
                sparkle(at: origin.point, radius: 3.4 * scale, rotation: a, alpha: 0.85 * fade)
            }
        }
    }
}
