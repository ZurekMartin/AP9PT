import CoreImage
import SwiftUI
import UIKit

public struct OceanBackdrop: View {
    private let calm: Double
    @State private var clock = BackdropClock()
    @Environment(PageTracker.self) private var tracker: PageTracker?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    public init(calm: Double) {
        self.calm = calm
    }

    public var body: some View {
        let position = tracker?.position ?? 1
        let paused = reduceMotion || position >= 1.98 || scenePhase != .active
        GeometryReader { proxy in
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: paused)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let state = clock.advance(calm: calm, position: position, at: time)
                    mesh(t: reduceMotion ? 0 : time, calm: state.calm, position: state.position)
                }
                TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: paused)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let state = clock.advance(calm: calm, position: position, at: time)
                    let t = reduceMotion ? 0 : time
                    ZStack {
                        rays(size: proxy.size, t: t, calm: state.calm, position: state.position)
                        drift(t: t, calm: state.calm, position: state.position, flow: reduceMotion ? 0 : state.flow)
                        ThemeColors.resolve(theme.themeID, dark: scheme == .dark).top.opacity(0.42 * state.calm)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func mesh(t: Double, calm: Double, position: Double) -> some View {
        let amp = Float(1 - 0.65 * calm)
        let shift = Float((1 - position) * 0.1)
        func w(_ speed: Double, _ phase: Double) -> Float { Float(sin(t * speed + phase)) * amp }
        let points: [SIMD2<Float>] = [
            [0, 0], [0.5 + 0.08 * w(0.13, 0) + shift * 0.4, 0], [1, 0],
            [0, 0.5 + 0.06 * w(0.11, 1)], [0.5 + shift + 0.10 * w(0.17, 2), 0.5 + 0.08 * w(0.14, 3)], [1, 0.5 + 0.06 * w(0.12, 4)],
            [0, 1], [0.5 + 0.08 * w(0.10, 5) + shift * 0.4, 1], [1, 1]
        ]
        let palette = ThemeColors.resolve(theme.themeID, dark: scheme == .dark)
        let accent = theme.water.opacity(scheme == .dark ? 0.35 : 0.25)
        let colors: [Color] = [
            palette.top, palette.top, palette.top,
            palette.mid, accent.mix(with: palette.mid, by: 0.5), palette.mid,
            palette.bottom, palette.bottom, palette.bottom
        ]
        return MeshGradient(width: 3, height: 3, points: points, colors: colors, smoothsColors: true)
    }

    private func rays(size: CGSize, t: Double, calm: Double, position: Double) -> some View {
        let template = RayTemplate.shared(height: size.height)
        let image = template.map { Image(decorative: $0.image, scale: 1) }
        let frame = template?.frame ?? .zero
        let top = template?.top ?? 0
        let span = max(1, template?.span ?? 1)
        let strength = scheme == .dark ? 0.05 : 0.22
        return Canvas { context, canvasSize in
            guard let image else { return }
            let offset = -position * canvasSize.width * 0.08
            for index in 0..<4 {
                let base = canvasSize.width * (0.12 + 0.24 * Double(index)) + offset
                let sway = sin(t * 0.18 + Double(index) * 1.7) * 18
                let pulse = 0.65 + 0.35 * sin(t * 0.3 + Double(index))
                let shear = sway / span
                var layer = context
                layer.concatenate(CGAffineTransform(a: 1, b: 0, c: shear, d: 1, tx: base + sway + shear * top, ty: 0))
                layer.opacity = strength * pulse
                layer.draw(image, in: frame)
            }
        }
        .opacity(1 - 0.7 * calm)
    }

    private func drift(t: Double, calm: Double, position: Double, flow: Double) -> some View {
        let isDark = scheme == .dark
        let glow = theme.water
        return Canvas { context, canvasSize in
            let parallax = -position * canvasSize.width * 0.14
            for index in 0..<26 {
                let seed = Double(index)
                let sx = fract(sin(seed * 12.9898) * 43758.5453)
                let sy = fract(sin(seed * 78.233) * 12345.6789)
                let speed = 0.012 + 0.02 * fract(sin(seed * 3.7) * 999.1)
                let radius = 1.2 + 3.2 * fract(sin(seed * 9.1) * 777.7)
                let layer = 0.5 + 0.8 * fract(sin(seed * 5.3) * 321.3)
                let y = canvasSize.height * (1 - fract(sy + flow * speed))
                let rawX = canvasSize.width * sx + parallax * layer + sin(t * 0.4 + seed) * 10
                let x = (rawX.truncatingRemainder(dividingBy: canvasSize.width + 40) + canvasSize.width + 40).truncatingRemainder(dividingBy: canvasSize.width + 40) - 20
                let twinkle = 0.55 + 0.45 * sin(t * 0.9 + seed * 2)
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                if isDark {
                    context.fill(Path(ellipseIn: rect.insetBy(dx: -radius, dy: -radius)), with: .color(glow.opacity(0.10 * twinkle)))
                    context.fill(Path(ellipseIn: rect), with: .color(Palette.sage.opacity(0.65 * twinkle)))
                } else {
                    context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.55)), lineWidth: 1)
                    context.fill(Path(ellipseIn: CGRect(x: rect.minX + radius * 0.35, y: rect.minY + radius * 0.35, width: radius * 0.6, height: radius * 0.6)), with: .color(.white.opacity(0.7)))
                }
            }
        }
        .opacity(1 - 0.5 * calm)
    }

    private func fract(_ value: Double) -> Double {
        value - value.rounded(.down)
    }
}

@MainActor
final class RayTemplate {
    let image: CGImage
    let frame: CGRect
    let top: Double
    let span: Double

    private static var cache: [Int: RayTemplate] = [:]
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let blur = 14.0

    static func shared(height: Double) -> RayTemplate? {
        guard height > 1 else { return nil }
        let key = Int(height.rounded())
        if let cached = cache[key] { return cached }
        guard let created = RayTemplate(height: height) else { return nil }
        cache = [key: created]
        return created
    }

    private init?(height: Double) {
        let bottom = height * 0.75
        let pad = Self.blur * 3
        let topY = -20.0
        let minX = 0.0
        let maxX = 190.0
        let size = CGSize(width: maxX - minX + pad * 2, height: bottom - topY + pad * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let cg = renderer.cgContext
            let dx = pad - minX
            let dy = pad - topY
            cg.translateBy(x: dx, y: dy)
            cg.move(to: CGPoint(x: 0, y: topY))
            cg.addLine(to: CGPoint(x: 46, y: topY))
            cg.addLine(to: CGPoint(x: 190, y: bottom))
            cg.addLine(to: CGPoint(x: 90, y: bottom))
            cg.closePath()
            cg.clip()
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 120, y: bottom), options: [])
        }
        guard let source = rendered.cgImage else { return nil }
        let input = CIImage(cgImage: source)
        let extent = input.extent
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: Self.blur).cropped(to: extent)
        guard let blurred = Self.context.createCGImage(output, from: extent) else { return nil }
        image = blurred
        frame = CGRect(x: minX - pad, y: topY - pad, width: size.width, height: size.height)
        top = -topY
        span = bottom - topY
    }
}

struct BackdropState {
    let calm: Double
    let position: Double
    let flow: Double
}

final class BackdropClock {
    private var calm = 0.0
    private var position: Double?
    private var flow = 0.0
    private var last: Double?

    func advance(calm target: Double, position targetPosition: Double, at time: Double) -> BackdropState {
        let previous = last ?? time
        guard time >= previous else {
            return BackdropState(calm: calm, position: position ?? targetPosition, flow: flow)
        }
        let dt = min(0.1, time - previous)
        last = time
        calm += (target - calm) * min(1, dt * 2.2)
        let current = position ?? targetPosition
        position = current + (targetPosition - current) * min(1, dt * 5)
        flow += dt * (1 - 0.6 * calm)
        return BackdropState(calm: calm, position: position ?? targetPosition, flow: flow)
    }
}
