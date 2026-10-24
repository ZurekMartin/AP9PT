import KinetDesign
import SwiftUI

struct SceneExperience: Equatable {
    var id: String
    var start: Date
}

enum ExperienceTiming {
    static func duration(for id: String) -> Double {
        id == "silverShoal" ? 6 : 12
    }

    static func envelope(_ elapsed: Double, id: String) -> Double {
        let progress = min(1, max(0, elapsed / duration(for: id)))
        return pow(sin(progress * .pi), 0.6)
    }
}

struct ExperienceFrame {
    let id: String
    let t: Double
    let e: Double
    let side: Double
    let seed: Double

    init?(_ experience: SceneExperience?, now: Date) {
        guard let experience else { return nil }
        let elapsed = now.timeIntervalSince(experience.start)
        guard elapsed >= 0, elapsed < ExperienceTiming.duration(for: experience.id) else { return nil }
        id = experience.id
        t = elapsed
        e = ExperienceTiming.envelope(elapsed, id: experience.id)
        let seed = experience.start.timeIntervalSinceReferenceDate
        self.seed = seed
        side = unit(seed) > 0.5 ? 1 : -1
    }
}

private func unit(_ value: Double) -> Double {
    let s = sin(value * 12.9898) * 43758.5453
    return s - s.rounded(.down)
}

private func cycle(_ value: Double) -> Double { value - value.rounded(.down) }

extension AquariumScene {
    static func lightTint(_ t: Double) -> Color {
        let a = 0.5 + 0.5 * sin(t * 0.55)
        let b = 0.5 + 0.5 * sin(t * 0.37 + 2)
        return Palette.seaBlue.mix(with: Palette.coral, by: a * 0.6).mix(with: Palette.sage, by: b * 0.4)
    }

    func drawExperienceBackdrop(_ context: inout GraphicsContext, size: CGSize, frame: ExperienceFrame, dark: Bool) {
        guard frame.id == "warmCurrent" else { return }
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(stops: [
                .init(color: Palette.coral.opacity(0.03 * frame.e), location: 0),
                .init(color: Palette.coral.opacity((dark ? 0.16 : 0.12) * frame.e), location: 0.5),
                .init(color: Palette.sand.opacity(0.04 * frame.e), location: 1)
            ]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)
        ))
    }

    func drawExperienceLayer(_ context: inout GraphicsContext, layer: Int, size: CGSize, frame: ExperienceFrame, dark: Bool, haze: Color, topY: Double) {
        let width = Double(size.width)
        let height = Double(size.height)
        let scale = Self.layerScales[layer] * width / 390
        switch frame.id {
        case "warmCurrent":
            drawWarmCurrent(&context, layer: layer, width: width, height: height, scale: scale, frame: frame, size: size, topY: topY)
        case "bubbleSky":
            drawBubbleColumns(&context, layer: layer, width: width, scale: scale, frame: frame, size: size, topY: topY)
        default:
            break
        }
    }

    func drawExperienceGround(_ context: inout GraphicsContext, layer: Int, size: CGSize, frame: ExperienceFrame) {
        let width = Double(size.width)
        let scale = Self.layerScales[layer] * width / 390
        if frame.id == "warmCurrent" {
            let floor = Double(size.height) * 0.96
            drawWarmStreams(&context, seedBase: Double(40 + layer * 3), count: 3, width: width, scale: scale, frame: frame, alpha: 0.34,
                            top: { Self.baseline(layer: layer, x: $0, size: size) + 8 * scale },
                            bottom: { layer + 1 < Self.layerCount ? Self.baseline(layer: layer + 1, x: $0, size: size) - 4 * scale : floor })
            return
        }
        guard frame.id == "lightShow" else { return }
        var c = context
        c.blendMode = .plusLighter
        for index in 0..<5 {
            let seed = Double(layer * 5 + index)
            let x = width * cycle(unit(seed) + frame.t * 0.012 * (1 + unit(seed + 3)))
            let y = Self.baseline(layer: layer, x: x, size: size) + 10 * scale + unit(seed + 7) * 22 * scale
            let pulse = 0.5 + 0.5 * sin(frame.t * 1.3 + seed * 1.9)
            let w = (60 + 50 * unit(seed + 1)) * scale
            let tint = Self.lightTint(frame.t + seed)
            c.fill(Path(ellipseIn: CGRect(x: x - w / 2, y: y, width: w, height: 11 * scale)), with: .radialGradient(
                Gradient(colors: [tint.opacity(0.34 * frame.e * pulse), tint.opacity(0)]),
                center: CGPoint(x: x, y: y + 5 * scale), startRadius: 0, endRadius: w / 2
            ))
        }
    }

    func drawExperienceOverlay(_ context: inout GraphicsContext, size: CGSize, frame: ExperienceFrame, dark: Bool) {
        let width = Double(size.width)
        let height = Double(size.height)
        switch frame.id {
        case "lightShow":
            var c = context
            c.blendMode = .plusLighter
            for index in 0..<36 {
                let i = Double(index)
                let x = width * (0.5 + 0.48 * sin(i * 7.31 + frame.t * 0.12))
                let y = height * (0.14 + 0.56 * cycle(unit(i) + frame.t * 0.018))
                let twinkle = pow(max(0, sin(frame.t * 2.2 + i * 1.7)), 2)
                let tint = index % 3 == 0 ? Color.white : Self.lightTint(frame.t * 0.8 + i).mix(with: .white, by: 0.45)
                let r = 2 + 3 * unit(i + 9)
                c.fill(Path(ellipseIn: CGRect(x: x - r * 3, y: y - r * 3, width: r * 6, height: r * 6)), with: .radialGradient(
                    Gradient(colors: [tint.opacity(0.4 * twinkle * frame.e), tint.opacity(0)]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r * 3
                ))
                c.fill(Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)), with: .color(tint.opacity(0.9 * twinkle * frame.e)))
            }
        case "bubbleSky":
            let top = height * 0.1
            context.fill(Path(CGRect(x: 0, y: top - 30, width: width, height: 90)), with: .linearGradient(
                Gradient(colors: [.white.opacity(0), .white.opacity((dark ? 0.10 : 0.2) * frame.e), .white.opacity(0)]),
                startPoint: CGPoint(x: 0, y: top - 30), endPoint: CGPoint(x: 0, y: top + 60)
            ))
            var line = Path()
            for step in 0...24 {
                let x = width * Double(step) / 24
                let y = top + sin(x * 0.03 + frame.t * 1.1) * 3 + sin(x * 0.07 - frame.t * 0.8) * 1.5
                if step == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(line, with: .color(.white.opacity(0.32 * frame.e)), lineWidth: 1.4)
        default:
            break
        }
    }

    func drawJellyHalo(_ context: inout GraphicsContext, frame: ExperienceFrame) {
        guard frame.id == "lightShow" else { return }
        var c = context
        c.blendMode = .plusLighter
        let radius = 190 * sim.effectiveScale
        let center = sim.position.point
        let tint = Self.lightTint(frame.t)
        let pulse = 0.75 + 0.25 * sin(frame.t * 1.8)
        c.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .radialGradient(
            Gradient(colors: [tint.opacity(0.34 * frame.e * pulse), tint.opacity(0.1 * frame.e), tint.opacity(0)]),
            center: center, startRadius: 0, endRadius: radius
        ))
    }

    private func drawWarmStreams(_ context: inout GraphicsContext, seedBase: Double, count: Int, width: Double, scale: Double, frame: ExperienceFrame, alpha: Double, top: (Double) -> Double, bottom: (Double) -> Double) {
        var c = context
        c.addFilter(.blur(radius: 1.2 * scale))
        for k in 0..<count {
            let seed = seedBase + Double(k)
            let fraction = (Double(k) + 0.5 + (unit(seed + 4) - 0.5) * 0.5) / Double(count)
            let segments = 18
            var path = Path()
            for step in 0...segments {
                let x = -40 + (width + 80) * Double(step) / Double(segments)
                let clamped = min(max(x, 0), width)
                let yb = top(clamped) + (bottom(clamped) - top(clamped)) * fraction
                let y = yb + sin(x * 0.012 + frame.t * 0.9 + seed) * 8 * scale + sin(x * 0.031 - frame.t * 0.6 + seed) * 3 * scale
                if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            let head = cycle(frame.t * (0.07 + 0.03 * unit(seed + 2)) + unit(seed)) * 1.5
            let length = 0.42
            let parts = 6
            for part in 0..<parts {
                let from = head - length + length * Double(part) / Double(parts)
                let to = from + length / Double(parts) + 0.01
                let lower = max(0, from)
                let upper = min(1, to)
                guard upper > lower else { continue }
                let weight = sin((Double(part) + 0.5) / Double(parts) * .pi)
                let tint = (k % 2 == 0 ? Palette.coral : Palette.sand).mix(with: .white, by: 0.12)
                c.stroke(path.trimmedPath(from: lower, to: upper), with: .color(tint.opacity(alpha * frame.e * weight)), style: StrokeStyle(lineWidth: (2.6 + Double(k % 2)) * scale, lineCap: .round))
            }
        }
    }

    private func drawWarmCurrent(_ context: inout GraphicsContext, layer: Int, width: Double, height: Double, scale: Double, frame: ExperienceFrame, size: CGSize, topY: Double) {
        drawWarmStreams(&context, seedBase: Double(layer * 5), count: 5, width: width, scale: scale, frame: frame, alpha: 0.42,
                        top: { _ in topY }, bottom: { Self.baseline(layer: layer, x: $0, size: size) - 14 * scale })
        for index in 0..<8 {
            let seed = Double(layer * 8 + index)
            let x = (width + 60) * cycle(frame.t * (0.05 + 0.04 * unit(seed)) + unit(seed + 5)) - 30
            let floor = Self.baseline(layer: layer, x: min(max(x, 0), width), size: size)
            let y = topY + (floor - 10 * scale - topY) * unit(seed + 2) + sin(frame.t * 0.9 + seed) * 6 * scale
            let r = (1.1 + 1.4 * unit(seed + 8)) * scale
            let twinkle = 0.6 + 0.4 * sin(frame.t * 2.6 + seed)
            context.fill(Path(ellipseIn: CGRect(x: x - r * 2.2, y: y - r * 2.2, width: r * 4.4, height: r * 4.4)), with: .color(Palette.coral.opacity(0.14 * frame.e * twinkle)))
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(Palette.sand.opacity(0.85 * frame.e * twinkle)))
        }
    }

    private func drawBubbleColumns(_ context: inout GraphicsContext, layer: Int, width: Double, scale: Double, frame: ExperienceFrame, size: CGSize, topY: Double) {
        let top = Double(size.height) * 0.08
        let columns = 6
        for column in 0..<columns {
            let seed = Double(layer * columns + column)
            let x0 = width * ((Double(column) + 0.5 + (unit(seed * 3.7 + 1) - 0.5) * 0.7) / Double(columns))
            let originY = Self.baseline(layer: layer, x: x0, size: size) + 14 * scale
            for index in 0..<6 {
                let i = Double(index)
                let speed = 0.06 + 0.05 * unit(seed + i * 1.3)
                let p = cycle(frame.t * speed + unit(seed * 5 + i * 2.1))
                let y = originY - (originY - top) * p
                let x = x0 + sin(p * 11 + i + seed) * 8 * scale * (0.3 + p)
                let r = (2.6 + 3.6 * unit(seed * 2 + i * 4.3)) * scale * (0.7 + 0.5 * p)
                let alpha = frame.e * min(1, p * 8) * min(1, (1 - p) * 5)
                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.02 * alpha), .white.opacity(0.18 * alpha)]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r
                ))
                context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.6 * alpha)), lineWidth: 1)
                context.fill(Path(ellipseIn: CGRect(x: x - r * 0.55, y: y - r * 0.6, width: r * 0.55, height: r * 0.4)), with: .color(.white.opacity(0.8 * alpha)))
            }
        }
    }

    struct ShoalPath {
        let points: [SIMD3<Double>]
        let cumulative: [Double]
        var timeTable: [(time: Double, distance: Double)] = []
        var length: Double { cumulative.last ?? 0 }

        mutating func buildTimeTable(ringStart: Double, ringEnd: Double) {
            let samples = 240
            let blend = 260.0
            func speed(_ d: Double) -> Double {
                let outside = d < ringStart ? ringStart - d : (d > ringEnd ? d - ringEnd : 0)
                let t = min(1, outside / blend)
                let eased = t * t * (3 - 2 * t)
                return 1 + 0.35 * eased
            }
            var elapsed = 0.0
            var table: [(time: Double, distance: Double)] = [(0, 0)]
            let step = length / Double(samples)
            for k in 1...samples {
                let mid = (Double(k) - 0.5) * step
                elapsed += step / speed(mid)
                table.append((elapsed, Double(k) * step))
            }
            timeTable = table.map { ($0.time / elapsed, $0.distance) }
        }

        func distance(forTime tau: Double) -> Double {
            guard let last = timeTable.last else { return tau * length }
            if tau >= 1 { return last.distance }
            if tau <= 0 { return 0 }
            var low = 0
            var high = timeTable.count - 1
            while high - low > 1 {
                let mid = (low + high) / 2
                if timeTable[mid].time <= tau { low = mid } else { high = mid }
            }
            let a = timeTable[low]
            let b = timeTable[high]
            let f = (tau - a.time) / max(1e-9, b.time - a.time)
            return a.distance + (b.distance - a.distance) * f
        }

        init(points: [SIMD3<Double>]) {
            self.points = points
            var total = 0.0
            var sums = [0.0]
            for index in 1..<points.count {
                let d = points[index] - points[index - 1]
                total += (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
                sums.append(total)
            }
            cumulative = sums
        }

        func position(at distance: Double) -> SIMD3<Double> {
            let u = min(max(distance, 0), length)
            var j = 0
            while j < cumulative.count - 2 && cumulative[j + 1] < u { j += 1 }
            let span = max(0.001, cumulative[j + 1] - cumulative[j])
            let t = (u - cumulative[j]) / span
            let p0 = points[max(j - 1, 0)]
            let p1 = points[j]
            let p2 = points[j + 1]
            let p3 = points[min(j + 2, points.count - 1)]
            let t2 = t * t
            let t3 = t2 * t
            return 0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3)
        }
    }

    func shoalPath(size: CGSize, frame: ExperienceFrame) -> ShoalPath {
        let width = Double(size.width)
        let height = Double(size.height)
        let center = SIMD3<Double>(sim.position.x, sim.position.y, 0)
        let radius = max(92, 102 * sim.effectiveScale)
        let direction = frame.side
        let entry = SIMD3<Double>(direction > 0 ? -0.18 * width : 1.18 * width, center.y + (unit(frame.seed + 1) - 0.5) * height * 0.3, -radius)
        let exit = SIMD3<Double>(direction > 0 ? 1.18 * width : -0.18 * width, center.y + (unit(frame.seed + 2) - 0.5) * height * 0.3, -radius)
        var points: [SIMD3<Double>] = [entry]
        let steps = 16
        var ring: [SIMD3<Double>] = []
        for step in 0...steps {
            let u = 2 * .pi * Double(step) / Double(steps)
            ring.append(SIMD3<Double>(
                center.x + direction * radius * sin(u),
                center.y + sin(u) * radius * 0.1,
                -radius * cos(u)
            ))
        }
        points.append((entry + ring[0]) / 2)
        points.append(contentsOf: ring)
        points.append((ring[ring.count - 1] + exit) / 2)
        points.append(exit)
        var path = ShoalPath(points: points)
        path.buildTimeTable(ringStart: path.cumulative[2], ringEnd: path.cumulative[2 + steps])
        return path
    }

    func drawExperienceShoal(_ context: inout GraphicsContext, size: CGSize, frame: ExperienceFrame, path: ShoalPath, haze: Color, pass: Int) {
        guard frame.id == "silverShoal" else { return }
        let jellyPass = Self.layerDepths.firstIndex { sim.depth >= $0 } ?? Self.layerCount
        guard pass == jellyPass || pass == jellyPass - 1 else { return }
        let visual = min(Self.layerCount - 1, jellyPass)
        let unitSize = Double(size.width) / 390
        let progress = frame.t / ExperienceTiming.duration(for: frame.id)
        let count = 12
        for index in 0..<count {
            let i = Double(index)
            let lag = 0.09 * i / Double(count) + 0.012 * unit(i * 1.9)
            let tau = progress * 1.1 - lag
            guard tau > 0, tau < 1 else { continue }
            let distance = path.distance(forTime: tau)
            let offset = SIMD3<Double>((unit(i * 1.3) - 0.5) * 40, (unit(i * 2.1) - 0.5) * 34, (unit(i * 3.7) - 0.5) * 40)
            let p = path.position(at: distance) + offset
            let ahead = path.position(at: min(path.length, distance + 6))
            let behind = path.position(at: max(0, distance - 6))
            var heading = ahead - behind
            let norm = max(0.001, (heading.x * heading.x + heading.y * heading.y + heading.z * heading.z).squareRoot())
            heading /= norm
            guard (p.z >= 0 ? jellyPass : jellyPass - 1) == pass else { continue }
            let yaw = atan2(-heading.z, heading.x)
            let pitch = atan2(heading.y, (heading.x * heading.x + heading.z * heading.z).squareRoot())
            let perspective = 1 + p.z / 650
            Self.drawSilverFish(
                &context,
                at: CGPoint(x: p.x, y: p.y + 0.28 * p.z),
                yaw: yaw, pitch: pitch,
                scale: unitSize * Self.layerScales[visual] * 1.12 * perspective,
                swing: sin(frame.t * 9 + i * 1.7),
                flash: pow(0.5 + 0.5 * sin(frame.t * 1.4 + i * 2.3), 3),
                haze: haze, mix: min(0.5, Self.layerDepths[visual] * 0.5)
            )
        }
    }

    static func drawSilverFish(_ context: inout GraphicsContext, at point: CGPoint, yaw: Double, pitch: Double, scale: Double, swing: Double, flash: Double, haze: Color, mix: Double) {
        let cs = cos(yaw)
        let sn = sin(yaw)
        let facing = cs >= 0 ? 1.0 : -1.0
        let a = 11.0
        let hMax = 4.8
        let wMax = 3.4
        let back = Color(red: 0.34, green: 0.46, blue: 0.6).mix(with: haze, by: mix)
        let silver = Color(red: 0.82, green: 0.89, blue: 0.94).mix(with: haze, by: mix)
        let belly = Color(red: 0.96, green: 0.98, blue: 1).mix(with: haze, by: mix * 0.8)
        let ink = Color(red: 0.06, green: 0.09, blue: 0.13)
        func px(_ x: Double, _ z: Double = 0) -> Double { x * cs + z * sn }

        var c = context
        c.translateBy(x: point.x, y: point.y)
        c.scaleBy(x: scale, y: scale)
        c.rotate(by: .radians(pitch * facing * 0.8))

        var tail = Path()
        let sway = swing * 2.2 * abs(sn)
        tail.move(to: CGPoint(x: px(-a * 0.8), y: -1.3))
        tail.addLine(to: CGPoint(x: px(-a - 8) + sway, y: -6.8 + swing * 1.4))
        tail.addQuadCurve(to: CGPoint(x: px(-a - 8) + sway, y: 6.8 + swing * 1.4), control: CGPoint(x: px(-a - 3.4) + sway * 0.5, y: swing))
        tail.addLine(to: CGPoint(x: px(-a * 0.8), y: 1.3))
        tail.closeSubpath()
        let tailFill = GraphicsContext.Shading.color(back.opacity(0.92))
        if sn <= 0 { c.fill(tail, with: tailFill) }

        var dorsal = Path()
        dorsal.move(to: CGPoint(x: px(-3), y: -hMax * 0.8))
        dorsal.addQuadCurve(to: CGPoint(x: px(6), y: -hMax * 0.8), control: CGPoint(x: px(1.5), y: -hMax - 5))
        c.fill(dorsal, with: .color(back))

        var body = Path()
        let slices = 11
        for k in 0..<slices {
            let x = -a + 2 * a * Double(k) / Double(slices - 1)
            let f = max(0, 1 - (x / a) * (x / a)).squareRoot()
            let g = 0.6 + 0.4 * (x + a) / (2 * a)
            let h = max(0.8, hMax * f * g)
            let w = wMax * f * g
            let segment = 2 * a / Double(slices - 1)
            let rx = max(0.9, w * abs(sn) + segment * abs(cs) * 0.8)
            body.addEllipse(in: CGRect(x: px(x) - rx, y: -h, width: rx * 2, height: h * 2))
        }
        c.fill(body, with: .linearGradient(
            Gradient(stops: [.init(color: back, location: 0), .init(color: silver, location: 0.5), .init(color: belly, location: 1)]),
            startPoint: CGPoint(x: 0, y: -hMax), endPoint: CGPoint(x: 0, y: hMax)
        ))
        c.fill(body, with: .color(.white.opacity(0.22 * flash * abs(cs) + 0.1 * abs(sn))))
        var line = Path()
        line.move(to: CGPoint(x: px(-a * 0.7), y: -0.6))
        line.addLine(to: CGPoint(x: px(a * 0.75), y: -0.9))
        c.stroke(line, with: .color(.white.opacity(0.4 * abs(cs))), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))

        if sn > 0 { c.fill(tail, with: tailFill) }

        let z = facing * wMax * 0.8
        var fin = Path()
        fin.move(to: CGPoint(x: px(3.4, z), y: 1.6))
        fin.addQuadCurve(to: CGPoint(x: px(-2.4, facing * (wMax + 3.2 + swing)), y: 4.6), control: CGPoint(x: px(1, facing * (wMax + 1.5)), y: 4.4))
        fin.addLine(to: CGPoint(x: px(2.4, z), y: 2.6))
        fin.closeSubpath()
        c.fill(fin, with: .color(silver.opacity(0.9)))

        var eyes = c
        var clipped = false
        for side in [-1.0, 1.0] {
            let visibility = min(1, max(0, (0.85 * side * cs - 0.5 * sn) * 3))
            guard visibility > 0.02 else { continue }
            if !clipped {
                eyes.clip(to: body)
                clipped = true
            }
            let ex = px(7.4, side * 1.6)
            eyes.fill(Path(ellipseIn: CGRect(x: ex - 1.0, y: -2.1, width: 2.0, height: 2.0)), with: .color(ink.opacity(visibility)))
            eyes.fill(Path(ellipseIn: CGRect(x: ex - 0.15, y: -1.95, width: 0.6, height: 0.6)), with: .color(.white.opacity(0.7 * visibility)))
        }
    }
}
