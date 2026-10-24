import SwiftUI

public struct GuideRow: Sendable, Equatable {
    public let symbol: String
    public let text: String

    public init(_ symbol: String, _ text: String) {
        self.symbol = symbol
        self.text = text
    }
}

public struct GuideStep: Sendable, Equatable {
    public let page: Int
    public let title: String
    public let lead: String?
    public let rows: [GuideRow]
    public let targets: [String]
    public let scrollsProfile: Bool
    public let isWelcome: Bool

    public init(page: Int, title: String, lead: String? = nil, rows: [GuideRow] = [], targets: [String] = [], scrollsProfile: Bool = false, isWelcome: Bool = false) {
        self.page = page
        self.title = title
        self.lead = lead
        self.rows = rows
        self.targets = targets
        self.scrollsProfile = scrollsProfile
        self.isWelcome = isWelcome
    }
}

public struct GuideWelcomeContext {
    public let donut: CGRect
    public let textArea: CGRect
    public let showsMascot: Bool
    public let advance: () -> Void

    public init(donut: CGRect, textArea: CGRect, showsMascot: Bool, advance: @escaping () -> Void) {
        self.donut = donut
        self.textArea = textArea
        self.showsMascot = showsMascot
        self.advance = advance
    }
}

public struct GuideAnchorKey: PreferenceKey {
    public static let defaultValue: [String: Anchor<CGRect>] = [:]

    public static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

public extension EnvironmentValues {
    @Entry var guideScrollsProfile: Bool = false
}

public extension View {
    func guideTarget(_ id: String) -> some View {
        anchorPreference(key: GuideAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

public struct GuideOverlay<Welcome: View>: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.screenInsets) private var insets
    @Environment(PageTracker.self) private var tracker: PageTracker?
    private let steps: [GuideStep]
    private let frames: [String: CGRect]
    private let isSettled: Bool
    private let onFinish: () -> Void
    private let welcome: (GuideWelcomeContext) -> Welcome
    @Binding private var index: Int

    public init(steps: [GuideStep], index: Binding<Int>, frames: [String: CGRect], isSettled: Bool, onFinish: @escaping () -> Void, @ViewBuilder welcome: @escaping (GuideWelcomeContext) -> Welcome) {
        self.steps = steps
        self._index = index
        self.frames = frames
        self.isSettled = isSettled
        self.onFinish = onFinish
        self.welcome = welcome
    }

    public var body: some View {
        GeometryReader { proxy in
            let step = steps[index]
            let bounds = CGRect(origin: .zero, size: proxy.size).insetBy(dx: 8, dy: 8)
            let rects = isSettled && !step.isWelcome ? step.targets.compactMap { frames[$0] }.map { $0.insetBy(dx: -8, dy: -8).intersection(bounds) }.filter { !$0.isNull && !$0.isEmpty } : []
            ZStack {
                if step.isWelcome {
                    Rectangle().fill(.clear).glassEffect(.regular, in: .rect)
                        .transition(.opacity)
                    welcomeLayer(proxy: proxy)
                        .transition(.opacity)
                } else {
                    ZStack {
                        Color.black.opacity(0.6)
                            .mask {
                                Rectangle()
                                    .overlay {
                                        ForEach(Array(rects.enumerated()), id: \.offset) { _, rect in
                                            RoundedRectangle(cornerRadius: min(rect.height / 2, 28), style: .continuous)
                                                .frame(width: rect.width, height: rect.height)
                                                .position(x: rect.midX, y: rect.midY)
                                                .blendMode(.destinationOut)
                                        }
                                    }
                                    .compositingGroup()
                            }
                        ForEach(Array(rects.enumerated()), id: \.offset) { _, rect in
                            RoundedRectangle(cornerRadius: min(rect.height / 2, 28), style: .continuous)
                                .strokeBorder(.white.opacity(0.55), lineWidth: 1.5)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                    }
                    .animation(nil, value: index)
                }
                if !step.isWelcome {
                    VStack {
                        Spacer(minLength: 0)
                        card(step)
                            .id(index)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                            .opacity(isSettled ? 1 : 0)
                    }
                    .padding(.horizontal, KinetLayout.pageMargin)
                    .padding(.top, insets.top + 16)
                    .padding(.bottom, KinetLayout.barHeight + KinetLayout.pageMargin * 2)
                }
            }
            .contentShape(.rect)
            .onTapGesture {}
            .animation(.smooth(duration: 0.45), value: index)
            .animation(.smooth(duration: 0.3), value: isSettled)
        }
        .ignoresSafeArea()
    }

    private func welcomeLayer(proxy: GeometryProxy) -> some View {
        let donut = frames["donut"] ?? CGRect(x: proxy.size.width / 2 - 135, y: proxy.size.height * 0.2, width: 270, height: 270)
        let showsMascot = tracker?.profileAtTop ?? true
        let width = proxy.size.width - KinetLayout.pageMargin * 2
        let area: CGRect
        if showsMascot {
            let top = donut.maxY + 8
            let bottom = proxy.size.height - insets.bottom - 24
            area = CGRect(x: KinetLayout.pageMargin, y: top, width: width, height: max(160, bottom - top))
        } else {
            area = CGRect(x: KinetLayout.pageMargin, y: 0, width: width, height: proxy.size.height)
        }
        return welcome(GuideWelcomeContext(donut: donut, textArea: area, showsMascot: showsMascot, advance: { go(1) }))
            .animation(.smooth(duration: 0.4), value: showsMascot)
    }

    private func card(_ step: GuideStep) -> some View {
        let offset = steps.first?.isWelcome == true ? 1 : 0
        let last = index == steps.count - 1
        return VStack(alignment: .leading, spacing: 14) {
            do {
                HStack(spacing: 10) {
                    Capsule()
                        .fill(Palette.mist.opacity(0.35))
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            GeometryReader { bar in
                                Capsule().fill(theme.water).frame(width: bar.size.width * Double(index + 1 - offset) / Double(steps.count - offset))
                            }
                        }
                    Text("\(index + 1 - offset) / \(steps.count - offset)")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.inkSecondary)
                }
                Text(step.title)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Palette.ink)
                if let lead = step.lead {
                    Text(lead)
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(step.rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 12) {
                            Image(systemName: row.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.water)
                                .frame(width: 30, height: 30)
                                .background(theme.water.opacity(0.16), in: .circle)
                            Text(row.text)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    if index > offset {
                        Button { go(-1) } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Palette.ink)
                                .frame(width: 52, height: 52)
                                .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .disabled(!isSettled)
                        .accessibilityLabel("Zpět")
                    }
                    if last {
                        Button { onFinish() } label: {
                            Text("Hotovo")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(theme.water.opacity(0.55)).interactive(), in: .capsule)
                    } else {
                        Button { onFinish() } label: {
                            Text("Zavřít")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        Button { go(1) } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Palette.ink)
                                .frame(width: 52, height: 52)
                                .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(theme.water.opacity(0.55)).interactive(), in: .circle)
                        .disabled(!isSettled)
                        .accessibilityLabel("Dál")
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
    }

    private func go(_ delta: Int) {
        let next = index + delta
        if next >= steps.count {
            onFinish()
        } else if next >= 0 {
            index = next
        }
    }
}
