import KinetDesign
import SwiftUI

enum DecorRenderer {
    static func decay(_ age: Double?, _ rate: Double) -> Double {
        guard let age else { return 0 }
        return exp(-age * rate)
    }

    static func smooth(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x * x * (3 - 2 * x)
    }

    static func draw(id: String, in context: inout GraphicsContext, base: CGPoint, scale: Double, time: Double, isDark: Bool, age: Double?, width: Double) {
        var layer = context
        layer.translateBy(x: base.x, y: base.y)
        switch id {
        case "seaweed": seaweed(&layer, s: scale, t: time, age: age)
        case "pebbles": pebbles(&layer, s: scale, age: age)
        case "shells": shells(&layer, s: scale, age: age)
        case "bubbler": bubbler(&layer, s: scale, t: time, age: age)
        case "coral": coral(&layer, s: scale, t: time, age: age)
        case "glowMushroom": mushroom(&layer, s: scale, t: time, isDark: isDark, age: age)
        case "amphora": amphora(&layer, s: scale, age: age, riseTo: base.y + 80)
        case "moonstone": moonstone(&layer, s: scale, t: time, isDark: isDark, age: age)
        case "shipwreck": shipwreck(&layer, s: scale, t: time, age: age, baseX: base.x, width: width)
        case "starfish": starfish(&layer, s: scale, age: age)
        case "chest": chest(&layer, s: scale, age: age)
        case "anemone": anemone(&layer, s: scale, t: time, age: age)
        default: break
        }
    }

    private static func seaweed(_ c: inout GraphicsContext, s: Double, t: Double, age: Double?) {
        let swirl = decay(age, 0.5)
        let clock = age ?? 0
        for index in 0..<5 {
            let i = Double(index)
            let height = (74 + 20 * Double(index % 3)) * s
            let x0 = (i - 2) * 9 * s
            let sway = sin(t * 0.9 + i * 0.7) * 11 * s + sin(clock * 3.2 - i * 0.7) * 26 * s * swirl
            var blade = Path()
            blade.move(to: CGPoint(x: x0, y: 0))
            blade.addQuadCurve(to: CGPoint(x: x0 + sway, y: -height), control: CGPoint(x: x0 - sway * 0.6 + (index % 2 == 0 ? 9 : -9) * s * (1 + 1.6 * swirl), y: -height * (0.5 - 0.06 * swirl)))
            c.stroke(blade, with: .color((index % 2 == 0 ? Palette.sage : Palette.seaBlue.mix(with: Palette.sage, by: 0.5)).opacity(0.85)), style: StrokeStyle(lineWidth: 6 * s, lineCap: .round))
        }
    }

    private static func pebbles(_ c: inout GraphicsContext, s: Double, age: Double?) {
        let items: [(Double, Double, Double, Double)] = [(-22, -4, 16, 9), (-4, -6, 20, 11), (16, -3, 13, 7), (30, -2, 9, 5)]
        for (index, item) in items.enumerated() {
            var hop = 0.0
            var roll = 0.0
            if let age {
                let local = age - Double(index) * 0.14
                if local > 0 {
                    hop = abs(sin(local * 7.5)) * exp(-local * 1.3) * 11 * s
                    roll = sin(local * 7.5) * exp(-local * 1.3) * 2.4 * s
                }
            }
            let rect = CGRect(x: item.0 * s - item.2 * s / 2 + roll, y: item.1 * s - item.3 * s / 2 - hop, width: item.2 * s, height: item.3 * s)
            c.fill(Path(ellipseIn: rect), with: .color((index % 2 == 0 ? Palette.mist : Palette.sand).opacity(0.9)))
            c.fill(Path(ellipseIn: rect.insetBy(dx: rect.width * 0.25, dy: rect.height * 0.35).offsetBy(dx: -1, dy: -1.5)), with: .color(.white.opacity(0.25)))
        }
    }

    private static func shells(_ c: inout GraphicsContext, s: Double, age: Double?) {
        let shells: [(x: Double, y: Double, r: Double, big: Bool)] = [(-9, 0, 18, true), (10, 4, 11, false)]
        for (index, shell) in shells.enumerated() {
            let center = CGPoint(x: shell.x * s, y: shell.y * s)
            let r = shell.r * s
            var fan = Path()
            fan.move(to: center)
            fan.addArc(center: center, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            fan.closeSubpath()
            c.fill(fan, with: .color((shell.big ? Palette.coral : Palette.sand).opacity(0.95)))
            for ridge in 1..<5 {
                let a = Double.pi + Double.pi * Double(ridge) / 5
                var line = Path()
                line.move(to: center)
                line.addLine(to: CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r))
                c.stroke(line, with: .color(.white.opacity(0.35)), lineWidth: 1)
            }
            guard let age else { continue }
            let local = age - Double(index) * 0.35
            guard local > 0 else { continue }
            let fade = exp(-local * 0.45)
            for wedge in 0..<5 {
                let glow = max(0, sin((local * 4.2 - Double(wedge) * 0.7))) * fade
                guard glow > 0.01 else { continue }
                let start = Double.pi + Double.pi * Double(wedge) / 5
                let end = Double.pi + Double.pi * Double(wedge + 1) / 5
                var sector = Path()
                sector.move(to: center)
                sector.addArc(center: center, radius: r, startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
                sector.closeSubpath()
                c.fill(sector, with: .color(.white.opacity(0.5 * glow)))
            }
            if shell.big {
                let phase = local * 0.6
                let cycle = phase.truncatingRemainder(dividingBy: 1)
                let alpha = sin(cycle * .pi) * fade
                if alpha > 0.02 {
                    var starContext = c
                    starContext.translateBy(x: center.x + r * 0.35, y: center.y - r * 0.6 - cycle * 8 * s)
                    starContext.fill(JellyfishRenderer.starPath(radius: 2.8 * s, rotation: local * 1.2), with: .color(Color.white.opacity(0.8 * alpha)))
                }
            }
        }
    }

    private static func unit(_ a: Double, _ b: Double) -> Double {
        let value = sin(a * 12.9898 + b * 78.233) * 43758.5453
        return value - value.rounded(.down)
    }

    private static func bubbler(_ c: inout GraphicsContext, s: Double, t: Double, age: Double?) {
        c.fill(Path(ellipseIn: CGRect(x: -16 * s, y: -9 * s, width: 32 * s, height: 16 * s)), with: .color(Palette.mist.opacity(0.9)))
        c.fill(Path(ellipseIn: CGRect(x: -7 * s, y: -11 * s, width: 14 * s, height: 6 * s)), with: .color(Palette.deep1.opacity(0.7)))
        let reach = 225.0
        for k in 0..<7 {
            let key = Double(k)
            let period = 3.4 + 3.6 * unit(key, 1.3)
            let cycle = t / period + unit(key, 2.1) * 3
            let n = cycle.rounded(.down)
            let q = cycle - n
            guard q < 0.62 else { continue }
            let progress = q / 0.62
            let x0 = (unit(key, n + 3.7) - 0.5) * 14 * s
            let drift = (unit(key, n + 5.9) - 0.5) * 16 * s
            let tremble = (unit(key, n + 8.3) - 0.5) * 3 * s * sin(progress * 5)
            let size = 1.6 + 2.6 * unit(key, n + 11.1)
            let height = reach * (0.55 + 0.45 * unit(key, n + 13.7))
            let x = x0 + drift * progress + tremble
            let y = -10 * s - progress * height * s
            let r = size * (0.8 + 0.6 * progress) * s
            c.stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.6 * pow(1 - progress, 1.2))), lineWidth: 1)
        }
        guard let age else { return }
        let count = 14
        for k in 0..<count {
            let key = Double(k) + 40
            let launch = unit(key, 1.9) * 1.8
            let local = age - launch
            guard local > 0 else { continue }
            let popHeight = (247 + 180 * unit(key, 4.4)) * s
            let rise = (157 + 68 * unit(key, 6.1)) * s
            let popTime = popHeight / rise
            let x0 = (unit(key, 7.7) - 0.5) * 18 * s
            let drift = (unit(key, 9.3) - 0.5) * 26 * s
            let size = 2.0 + 2.4 * unit(key, 10.9)
            if local < popTime {
                let progress = local / popTime
                let x = x0 + drift * progress
                let y = -10 * s - local * rise
                let r = size * (0.8 + 0.5 * progress) * s
                c.stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.7)), lineWidth: 1)
                c.fill(Path(ellipseIn: CGRect(x: x - r * 0.45, y: y - r * 0.55, width: r * 0.5, height: r * 0.5)), with: .color(.white.opacity(0.6)))
            } else {
                let q = (local - popTime) / 0.28
                guard q < 1 else { continue }
                let center = CGPoint(x: x0 + drift, y: -10 * s - popHeight)
                let ring = (size * 1.3 + 6 * q) * s
                c.stroke(Path(ellipseIn: CGRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2)), with: .color(.white.opacity(0.7 * (1 - q))), lineWidth: 1)
                for droplet in 0..<4 {
                    let angle = Double(droplet) * .pi / 2 + .pi / 4 + unit(key, 12.2)
                    let inner = ring * 0.9
                    let outer = ring + 4 * s * q
                    var spark = Path()
                    spark.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                    spark.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
                    c.stroke(spark, with: .color(.white.opacity(0.6 * (1 - q))), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                }
            }
        }
    }

    private static func coral(_ c: inout GraphicsContext, s: Double, t: Double, age: Double?) {
        let swirl = decay(age, 0.55)
        let clock = age ?? 0
        let stems: [(Double, Double, Double)] = [(-14, -52, 0), (0, -66, 1), (15, -48, 2)]
        for (index, stem) in stems.enumerated() {
            let sway = sin(t * 0.7 + stem.2) * 3 * s + sin(clock * 3.0 - stem.2) * 9 * s * swirl
            let color = (index == 1 ? Palette.coral : Palette.coral.mix(with: Palette.sand, by: 0.35)).opacity(0.92)
            var path = Path()
            path.move(to: CGPoint(x: stem.0 * 0.4 * s, y: 0))
            path.addQuadCurve(to: CGPoint(x: stem.0 * s + sway, y: stem.1 * s), control: CGPoint(x: stem.0 * 0.2 * s, y: stem.1 * 0.5 * s))
            c.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 8 * s, lineCap: .round))
            for branch in [-1.0, 1.0] {
                var small = Path()
                let start = CGPoint(x: stem.0 * 0.8 * s + sway * 0.6, y: stem.1 * 0.55 * s)
                small.move(to: start)
                small.addLine(to: CGPoint(x: start.x + branch * 12 * s, y: start.y - 18 * s))
                c.stroke(small, with: .color(color), style: StrokeStyle(lineWidth: 5 * s, lineCap: .round))
            }
        }
    }

    private static func mushroom(_ c: inout GraphicsContext, s: Double, t: Double, isDark: Bool, age: Double?) {
        let flash = age.map { max(0, sin($0 * 8)) * exp(-$0 * 0.9) } ?? 0
        let pulse = 0.65 + 0.35 * sin(t * 1.3) + 1.1 * flash
        let glowColor = Palette.seaBlue.mix(with: .purple, by: 0.35)
        let strength = min(1, (isDark ? 0.42 : 0.2) * pulse)
        c.fill(Path(ellipseIn: CGRect(x: -130 * s, y: -152 * s, width: 260 * s, height: 260 * s)), with: .radialGradient(
            Gradient(stops: [
                .init(color: glowColor.opacity(strength), location: 0),
                .init(color: glowColor.opacity(strength * 0.45), location: 0.3),
                .init(color: glowColor.opacity(strength * 0.14), location: 0.62),
                .init(color: glowColor.opacity(0), location: 1)
            ]),
            center: CGPoint(x: 0, y: -22 * s), startRadius: 0, endRadius: (78 + 38 * flash) * s
        ))
        c.fill(Path(roundedRect: CGRect(x: -3.5 * s, y: -26 * s, width: 7 * s, height: 26 * s), cornerRadius: 3 * s), with: .color(Palette.sand.opacity(0.9)))
        var cap = Path()
        cap.addArc(center: CGPoint(x: 0, y: -26 * s), radius: 18 * s, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        cap.closeSubpath()
        c.fill(cap, with: .color(glowColor.mix(with: .white, by: min(0.9, 0.2 * pulse + 0.3 * flash))))
        for dot in [(-8.0, -33.0), (3.0, -38.0), (9.0, -31.0)] {
            c.fill(Path(ellipseIn: CGRect(x: dot.0 * s - 2 * s, y: dot.1 * s - 2 * s, width: 4 * s, height: 4 * s)), with: .color(.white.opacity(0.7)))
        }
    }

    private static func amphora(_ c: inout GraphicsContext, s: Double, age: Double?, riseTo: Double) {
        var body = Path()
        body.move(to: CGPoint(x: -6 * s, y: -60 * s))
        body.addCurve(to: CGPoint(x: -22 * s, y: -26 * s), control1: CGPoint(x: -6 * s, y: -48 * s), control2: CGPoint(x: -24 * s, y: -44 * s))
        body.addCurve(to: CGPoint(x: -8 * s, y: 0), control1: CGPoint(x: -20 * s, y: -10 * s), control2: CGPoint(x: -12 * s, y: -2 * s))
        body.addLine(to: CGPoint(x: 8 * s, y: 0))
        body.addCurve(to: CGPoint(x: 22 * s, y: -26 * s), control1: CGPoint(x: 12 * s, y: -2 * s), control2: CGPoint(x: 20 * s, y: -10 * s))
        body.addCurve(to: CGPoint(x: 6 * s, y: -60 * s), control1: CGPoint(x: 24 * s, y: -44 * s), control2: CGPoint(x: 6 * s, y: -48 * s))
        body.closeSubpath()
        let clay = Palette.sand.mix(with: Palette.coral, by: 0.4)
        c.fill(body, with: .linearGradient(Gradient(colors: [clay, clay.mix(with: .black, by: 0.25)]), startPoint: CGPoint(x: -20 * s, y: -30 * s), endPoint: CGPoint(x: 22 * s, y: -20 * s)))
        c.fill(Path(roundedRect: CGRect(x: -9 * s, y: -64 * s, width: 18 * s, height: 6 * s), cornerRadius: 3 * s), with: .color(clay.mix(with: .black, by: 0.15)))
        var band = Path()
        band.move(to: CGPoint(x: -21 * s, y: -30 * s))
        band.addQuadCurve(to: CGPoint(x: 21 * s, y: -30 * s), control: CGPoint(x: 0, y: -22 * s))
        c.stroke(band, with: .color(.white.opacity(0.35)), lineWidth: 1.5)
        if let age {
            for k in 0..<9 {
                let local = age - Double(k) * 0.1
                guard local > 0 else { continue }
                let speed = 118 + Double(k % 3) * 22
                let rise = local * speed
                let y = -64 * s - rise
                guard -y < riseTo + 40 else { continue }
                let wobble = sin(local * 3.1 + Double(k) * 1.7) * (4 + min(rise * 0.03, 9)) * s
                let r = (2.0 + min(rise * 0.01, 2.2)) * s
                c.fill(Path(ellipseIn: CGRect(x: wobble - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.1)))
                c.stroke(Path(ellipseIn: CGRect(x: wobble - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.7)), lineWidth: 1)
            }
        }
    }

    private static func moonstone(_ c: inout GraphicsContext, s: Double, t: Double, isDark: Bool, age: Double?) {
        var hop = 0.0
        if let age {
            let rise: Double = max(0, sin(age * 2.1)) * exp(-age * 0.55) * 22 * s
            let settle: Double = sin(age * 1.6) * exp(-age * 0.9) * 2 * s
            hop = rise + settle
        }
        let pulse = 0.7 + 0.3 * sin(t * 0.8) + 0.4 * decay(age, 0.8)
        var c = c
        c.translateBy(x: 0, y: -hop)
        c.fill(Path(ellipseIn: CGRect(x: -80 * s, y: -94 * s, width: 160 * s, height: 160 * s)), with: .radialGradient(
            Gradient(stops: [
                .init(color: Color.white.opacity((isDark ? 0.34 : 0.16) * pulse), location: 0),
                .init(color: Color.white.opacity((isDark ? 0.12 : 0.06) * pulse), location: 0.45),
                .init(color: Color.white.opacity(0), location: 1)
            ]),
            center: CGPoint(x: 0, y: -14 * s), startRadius: 0, endRadius: 56 * s
        ))
        let rect = CGRect(x: -14 * s, y: -28 * s, width: 28 * s, height: 28 * s)
        c.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [.white, Palette.seaBlue.mix(with: .white, by: 0.6), Palette.mist]),
            center: CGPoint(x: -4 * s, y: -20 * s), startRadius: 1, endRadius: 18 * s
        ))
    }

    private static func shipwreck(_ c: inout GraphicsContext, s: Double, t: Double, age: Double?, baseX: Double, width: Double) {
        let dir: Double = baseX > width / 2 ? 1 : -1
        let outDistance = (dir > 0 ? width - baseX : baseX) + 170 * s
        let inDistance = (dir > 0 ? baseX : width - baseX) + 170 * s
        var offset = 0.0
        var flutter = 0.0
        var visible = true
        if let age {
            if age < 2.2 {
                let p = age / 2.2
                offset = dir * outDistance * smooth(p) * smooth(p)
                flutter = 0.6 + 0.4 * sin(p * .pi)
            } else if age < 3.2 {
                visible = false
            } else if age < 6.2 {
                let p = (age - 3.2) / 3.0
                offset = -dir * inDistance * (1 - smooth(p))
                flutter = sin(p * .pi) * (1 - 0.5 * smooth(p))
            }
        }
        var layer = c
        layer.rotate(by: .degrees(-9))
        let tilt = CGAffineTransform(rotationAngle: -9 * .pi / 180)
        func tilted(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s).applying(tilt) }
        var hull = Path()
        hull.move(to: tilted(-52, -26))
        hull.addLine(to: tilted(54, -30))
        hull.addQuadCurve(to: CGPoint(x: tilted(30, 4).x, y: 0), control: tilted(52, -6))
        hull.addLine(to: CGPoint(x: tilted(-34, 4).x, y: 0))
        hull.addQuadCurve(to: tilted(-52, -26), control: tilted(-50, -8))
        let wood = Palette.mist.mix(with: Color(red: 0.25, green: 0.17, blue: 0.12), by: 0.65)
        c.fill(hull, with: .color(wood))
        for plank in 1..<3 {
            var line = Path()
            line.move(to: CGPoint(x: -46 * s, y: (-26 + Double(plank) * 9) * s))
            line.addLine(to: CGPoint(x: 48 * s, y: (-28 + Double(plank) * 9) * s))
            layer.stroke(line, with: .color(.black.opacity(0.25)), lineWidth: 1.2)
        }
        var mast = Path()
        mast.move(to: CGPoint(x: -6 * s, y: -28 * s))
        mast.addLine(to: CGPoint(x: -2 * s, y: -86 * s))
        layer.stroke(mast, with: .color(wood), style: StrokeStyle(lineWidth: 4 * s, lineCap: .round))
        guard visible else { return }

        let steps = 12
        let anchorTop = CGPoint(x: -2 * s, y: -84 * s)
        let anchorBottom = CGPoint(x: 0, y: -50 * s)
        var top: [CGPoint] = []
        var bottom: [CGPoint] = []
        for index in 0...steps {
            let u = Double(index) / Double(steps)
            let inverse = 1 - u
            let tipX = 30 * s
            let tipY = -52 * s
            let controlX = 26 * s
            let controlY = -80 * s
            var point = CGPoint(
                x: inverse * inverse * anchorTop.x + 2 * inverse * u * controlX + u * u * tipX,
                y: inverse * inverse * anchorTop.y + 2 * inverse * u * controlY + u * u * tipY
            )
            var low = CGPoint(x: anchorBottom.x + (tipX - anchorBottom.x) * u, y: anchorBottom.y + (tipY - anchorBottom.y) * u)
            let ripple = sin(t * 7 + u * 5) * 4 * s * flutter * u
            let stretch = 1 + 1.1 * flutter
            point.x = anchorTop.x + (point.x - anchorTop.x) * stretch + offset
            point.y += ripple
            low.x = anchorBottom.x + (low.x - anchorBottom.x) * stretch + offset
            low.y += ripple * 0.6 + sin(t * 6 + u * 4) * 2 * s * flutter * u
            top.append(point)
            bottom.append(low)
        }
        var sail = Path()
        sail.move(to: top[0])
        for point in top.dropFirst() { sail.addLine(to: point) }
        for point in bottom.reversed() { sail.addLine(to: point) }
        sail.closeSubpath()
        layer.fill(sail, with: .color(Palette.sand.opacity(0.45)))
    }

    private static func starfish(_ c: inout GraphicsContext, s: Double, age: Double?) {
        let wave = age.map { sin($0 * 7.5) * exp(-$0 * 0.8) } ?? 0
        var path = Path()
        let center = CGPoint(x: 0, y: -7 * s)
        for index in 0..<10 {
            let waving = index == 8
            let radius = (index % 2 == 0 ? 17.0 : 7.0) * s * (waving ? 1 + 0.18 * abs(wave) : 1)
            let angle = Double(index) / 10 * .pi * 2 - .pi / 2 + (waving ? wave * 0.5 : 0)
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius * 0.55)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        c.fill(path, with: .color(Palette.coral.mix(with: Palette.sand, by: 0.25).opacity(0.95)))
        c.stroke(path, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
        for index in 0..<5 {
            let waving = index == 4
            let angle = Double(index) / 5 * .pi * 2 - .pi / 2 + (waving ? wave * 0.5 : 0)
            let reach = waving ? 1 + 0.18 * abs(wave) : 1
            c.fill(Path(ellipseIn: CGRect(x: center.x + cos(angle) * 8 * s * reach - 1.2 * s, y: center.y + sin(angle) * 4.4 * s * reach - 1.2 * s, width: 2.4 * s, height: 2.4 * s)), with: .color(.white.opacity(0.55)))
        }
    }

    private static func chest(_ c: inout GraphicsContext, s: Double, age: Double?) {
        let wood = Color(red: 0.42, green: 0.27, blue: 0.17).mix(with: Palette.mist, by: 0.2)
        let darkWood = wood.mix(with: .black, by: 0.3)
        let gold = Palette.sand.mix(with: Palette.coral, by: 0.15)
        var open = 0.0
        if let age {
            if age < 0.9 { open = smooth(age / 0.9) } else if age < 4.0 { open = 1 } else if age < 5.0 { open = 1 - smooth((age - 4.0) / 1.0) }
        }
        let angle = open * 1.9
        let hingeY = -24.0 * s
        let depthLength = 16.0 * s
        let freeY = hingeY + 0.25 * depthLength * cos(angle) - 0.95 * depthLength * sin(angle)
        let bulge = 20.0 * s * (1 - open)
        let body = Path(roundedRect: CGRect(x: -22 * s, y: -20 * s, width: 44 * s, height: 20 * s), cornerRadius: 3 * s)

        func drawLid() {
            var lid = Path()
            lid.move(to: CGPoint(x: -22 * s, y: hingeY))
            lid.addQuadCurve(to: CGPoint(x: 22 * s, y: hingeY), control: CGPoint(x: 0, y: hingeY - bulge))
            lid.addLine(to: CGPoint(x: 22 * s, y: freeY))
            lid.addLine(to: CGPoint(x: -22 * s, y: freeY))
            lid.closeSubpath()
            let inner = angle > 1.5
            c.fill(lid, with: .color(inner ? darkWood.mix(with: gold, by: 0.12) : wood.mix(with: .white, by: 0.08)))
            for x in [-14.0, 14.0] {
                var strap = Path()
                strap.move(to: CGPoint(x: x * s - 2 * s, y: hingeY - bulge * 0.28))
                strap.addLine(to: CGPoint(x: x * s + 2 * s, y: hingeY - bulge * 0.28))
                strap.addLine(to: CGPoint(x: x * s + 2 * s, y: freeY))
                strap.addLine(to: CGPoint(x: x * s - 2 * s, y: freeY))
                strap.closeSubpath()
                c.fill(strap, with: .color(gold.opacity(inner ? 0.55 : 0.9)))
            }
            var rim = Path()
            rim.move(to: CGPoint(x: -22 * s, y: hingeY))
            rim.addQuadCurve(to: CGPoint(x: 22 * s, y: hingeY), control: CGPoint(x: 0, y: hingeY - bulge))
            c.stroke(rim, with: .color(.black.opacity(0.28)), lineWidth: 1)
        }

        func drawInterior() {
            c.fill(Path(ellipseIn: CGRect(x: -20 * s, y: -26 * s, width: 40 * s, height: 10 * s)), with: .color(Color(red: 0.1, green: 0.06, blue: 0.04).opacity(0.9)))
            guard open > 0.02 else { return }
            c.fill(Path(ellipseIn: CGRect(x: -48 * s, y: -70 * s, width: 96 * s, height: 84 * s)), with: .radialGradient(
                Gradient(stops: [
                    .init(color: gold.opacity(0.5 * open), location: 0),
                    .init(color: gold.opacity(0.16 * open), location: 0.5),
                    .init(color: gold.opacity(0), location: 1)
                ]),
                center: CGPoint(x: 0, y: -24 * s), startRadius: 0, endRadius: 46 * s
            ))
            let coins: [(Double, Double)] = [(-14, 0), (-8, -2), (-1, 0), (6, -2), (13, 0), (-11, -5), (-3, -6), (5, -6), (11, -4), (-6, -9), (2, -10), (8, -9), (-1, -13)]
            let shown = min(1, open * 1.5)
            for (index, coin) in coins.enumerated() where Double(index) / Double(coins.count) <= shown {
                let rect = CGRect(x: coin.0 * s * 0.9 - 3.4 * s, y: (-22 + coin.1 * 0.8) * s - 1.8 * s, width: 6.8 * s, height: 3.6 * s)
                c.fill(Path(ellipseIn: rect), with: .color(gold.mix(with: .white, by: index % 3 == 0 ? 0.3 : 0.05)))
                c.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.2)), lineWidth: 0.6)
            }
            for k in 0..<4 {
                let phase = ((age ?? 0) * 0.55 + Double(k) / 4).truncatingRemainder(dividingBy: 1)
                let x = (Double(k) - 1.5) * 9 * s + sin(phase * 6 + Double(k)) * 3 * s
                let y = -34 * s - phase * 30 * s
                c.fill(Path(ellipseIn: CGRect(x: x - 1.5 * s, y: y - 1.5 * s, width: 3 * s, height: 3 * s)), with: .color(.white.opacity(0.85 * open * (1 - phase))))
            }
        }

        func drawBody() {
            c.fill(body, with: .color(wood))
            c.fill(Path(CGRect(x: -16 * s, y: -20 * s, width: 4 * s, height: 20 * s)), with: .color(gold.opacity(0.9)))
            c.fill(Path(CGRect(x: 12 * s, y: -20 * s, width: 4 * s, height: 20 * s)), with: .color(gold.opacity(0.9)))
            c.fill(Path(roundedRect: CGRect(x: -3 * s, y: -17 * s, width: 6 * s, height: 8 * s), cornerRadius: 1.5 * s), with: .color(gold.opacity(1 - 0.7 * open)))
            c.stroke(body, with: .color(.black.opacity(0.25)), lineWidth: 1)
        }

        if open < 0.4 {
            drawBody()
            drawInterior()
            drawLid()
        } else {
            drawLid()
            drawBody()
            drawInterior()
        }
    }

    private static func anemone(_ c: inout GraphicsContext, s: Double, t: Double, age: Double?) {
        let swirl = decay(age, 0.5)
        let clock = age ?? 0
        c.fill(Path(ellipseIn: CGRect(x: -11 * s, y: -9 * s, width: 22 * s, height: 11 * s)), with: .color(Palette.coral.mix(with: Palette.mist, by: 0.35).opacity(0.95)))
        for index in 0..<9 {
            let i = Double(index)
            let spread = (i - 4) * 3.4 * s
            let sway = sin(t * 0.9 + i * 0.8) * 5 * s + sin(clock * 3.4 + i * 0.7) * 15 * s * swirl
            let curl = 1 - 0.28 * swirl * (0.5 + 0.5 * sin(clock * 4.6))
            var tentacle = Path()
            tentacle.move(to: CGPoint(x: spread * 0.6, y: -6 * s))
            tentacle.addQuadCurve(to: CGPoint(x: spread * 1.3 + sway, y: -(26 + 6 * sin(i * 1.7)) * s * curl), control: CGPoint(x: spread * 1.1 - sway * 0.4, y: -14 * s))
            c.stroke(tentacle, with: .color((index % 2 == 0 ? Palette.coral : Palette.sand).opacity(0.9)), style: StrokeStyle(lineWidth: 3.4 * s, lineCap: .round))
        }
    }
}
