import SwiftUI
import UIKit

public struct ContentCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: .rect(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            }
    }
}

public struct PageHeader<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let trailing: Trailing

    public init(title: String, subtitle: String?, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(KinetFont.pageTitle)
                    .foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

public struct Eyebrow: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text.uppercased())
            .font(KinetFont.eyebrow)
            .tracking(1.4)
            .foregroundStyle(Palette.inkSecondary)
    }
}

public struct SettingsGroup<Content: View>: View {
    private let title: String
    private let hint: String?
    private let content: Content

    public init(_ title: String, hint: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.hint = hint
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 10) {
            Eyebrow(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: .rect(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            }
            if let hint {
                SheetHint(hint)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

public struct TideFill: View {
    private let level: Double
    private let tint: Color
    private let isFrozen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pageActive) private var pageActive
    @Environment(\.colorScheme) private var scheme

    public init(level: Double, tint: Color = Palette.seaBlue, isFrozen: Bool = false) {
        self.level = level
        self.tint = tint
        self.isFrozen = isFrozen
    }

    public var body: some View {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let resolved = tint.resolve(in: environment)
        return TideLayer(
            level: 0.12 + 0.78 * min(1, max(0, level)),
            back: resolved.opacity(0.30).cgColor,
            front: resolved.opacity(0.18).cgColor,
            isRunning: !reduceMotion && pageActive && !isFrozen,
            isStatic: reduceMotion
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension Color.Resolved {
    func opacity(_ value: Float) -> Color.Resolved {
        var copy = self
        copy.opacity *= value
        return copy
    }
}

private struct TideLayer: UIViewRepresentable {
    let level: Double
    let back: CGColor
    let front: CGColor
    let isRunning: Bool
    let isStatic: Bool

    func makeUIView(context: Context) -> TideLayerView {
        TideLayerView()
    }

    func updateUIView(_ view: TideLayerView, context: Context) {
        view.update(level: level, back: back, front: front, isRunning: isRunning, isStatic: isStatic)
    }
}

final class TideLayerView: UIView {
    private struct Wave {
        let amplitude: Double
        let phase: Double
        let speed: Double
    }

    private static let waves = [Wave(amplitude: 4, phase: 0, speed: 0.9), Wave(amplitude: 6, phase: 1.6, speed: 1.3)]

    private let levelLayer = CALayer()
    private let wavesLayer = CALayer()
    private let shapes = [CAShapeLayer(), CAShapeLayer()]
    private var level: Double?
    private var builtSize: CGSize = .zero
    private var isRunning = false
    private var isStatic = false
    private var isPaused = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.masksToBounds = true
        layer.addSublayer(levelLayer)
        levelLayer.addSublayer(wavesLayer)
        for shape in shapes { wavesLayer.addSublayer(shape) }
    }

    required init?(coder: NSCoder) { nil }

    func update(level next: Double, back: CGColor, front: CGColor, isRunning running: Bool, isStatic still: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapes[0].fillColor = back
        shapes[1].fillColor = front
        CATransaction.commit()
        let modeChanged = still != isStatic
        isStatic = still
        isRunning = running
        if modeChanged { builtSize = .zero; setNeedsLayout() }
        applyLevel(next, animated: level != nil && builtSize != .zero)
        applyRunning()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
        guard bounds.size != builtSize, bounds.width > 0, bounds.height > 0 else { return }
        builtSize = bounds.size
        rebuild()
    }

    private func rebuild() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let width = bounds.width
        let height = bounds.height
        levelLayer.removeAnimation(forKey: "level")
        levelLayer.setAffineTransform(.identity)
        levelLayer.frame = bounds
        wavesLayer.frame = levelLayer.bounds
        for (index, wave) in Self.waves.enumerated() {
            let shape = shapes[index]
            shape.removeAllAnimations()
            shape.setAffineTransform(.identity)
            shape.frame = CGRect(x: 0, y: 0, width: width * 2, height: height)
            shape.path = Self.path(width: width, height: height, wave: wave)
            guard !isStatic else { continue }
            let animation = CABasicAnimation(keyPath: "transform.translation.x")
            animation.fromValue = 0
            animation.toValue = -width
            animation.duration = 2 * .pi / wave.speed
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.isRemovedOnCompletion = false
            shape.add(animation, forKey: "drift")
        }
        if let level { levelLayer.setAffineTransform(CGAffineTransform(translationX: 0, y: height * (1 - level))) }
        CATransaction.commit()
        isPaused = false
        wavesLayer.speed = 1
        wavesLayer.timeOffset = 0
        wavesLayer.beginTime = 0
        applyRunning()
    }

    private static func path(width: Double, height: Double, wave: Wave) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: height + 12))
        var x = 0.0
        while x <= width * 2 {
            path.addLine(to: CGPoint(x: x, y: sin(x / width * .pi * 2 + wave.phase) * wave.amplitude))
            x += 3
        }
        path.addLine(to: CGPoint(x: width * 2, y: sin(.pi * 4 + wave.phase) * wave.amplitude))
        path.addLine(to: CGPoint(x: width * 2, y: height + 12))
        path.closeSubpath()
        return path
    }

    private func applyLevel(_ next: Double, animated: Bool) {
        let previous = level
        level = next
        let height = bounds.height
        guard height > 0 else { return }
        let target = CGAffineTransform(translationX: 0, y: height * (1 - next))
        let jump = abs((previous ?? next) - next)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if animated, jump > 0.02 {
            let current = levelLayer.presentation()?.affineTransform() ?? levelLayer.affineTransform()
            let animation = CASpringAnimation(perceptualDuration: 1.2, bounce: 0)
            animation.keyPath = "transform.translation.y"
            animation.duration = animation.settlingDuration
            animation.fromValue = current.ty
            animation.toValue = target.ty
            levelLayer.add(animation, forKey: "level")
        } else if jump > 0 {
            levelLayer.removeAnimation(forKey: "level")
        }
        levelLayer.setAffineTransform(target)
        CATransaction.commit()
    }

    private func applyRunning() {
        let shouldRun = isRunning && !isStatic
        if shouldRun, isPaused {
            let paused = wavesLayer.timeOffset
            wavesLayer.speed = 1
            wavesLayer.timeOffset = 0
            wavesLayer.beginTime = 0
            wavesLayer.beginTime = wavesLayer.convertTime(CACurrentMediaTime(), from: nil) - paused
            isPaused = false
        } else if !shouldRun, !isPaused {
            let now = wavesLayer.convertTime(CACurrentMediaTime(), from: nil)
            wavesLayer.speed = 0
            wavesLayer.timeOffset = now
            isPaused = true
        }
    }
}
