import KinetDesign
import SwiftUI

struct LandingView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false
    private let themeID: String

    init(themeID: String = UserDefaults.standard.string(forKey: "pet.activeThemeID") ?? "lagoon") {
        self.themeID = themeID
    }

    private var palette: ThemeColors { ThemeColors.resolve(themeID, dark: scheme == .dark) }
    private var water: Color { AppTheme.make(skinID: "coralSkin", themeID: themeID).water }

    var body: some View {
        ZStack {
            LinearGradient(colors: [palette.top, palette.mid, palette.bottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            dots
                .opacity(breathing ? 1 : 0.6)
            ScrollView {
                VStack(spacing: 18) {
                    header
                    donut
                    todayCard
                    historyCard
                }
                .padding(.horizontal, KinetLayout.pageMargin)
                .padding(.top, 8)
            }
            .scrollDisabled(true)
            .scrollIndicators(.hidden)
            .opacity(breathing ? 1 : 0.7)
            bar
                .opacity(breathing ? 1 : 0.7)
        }
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { breathing = true; return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { breathing = true }
        }
    }

    private func bone(_ width: CGFloat? = nil, _ height: CGFloat, radius: CGFloat? = nil, opacity: Double = 0.12) -> some View {
        RoundedRectangle(cornerRadius: radius ?? height / 2, style: .continuous)
            .fill(Palette.ink.opacity(opacity))
            .frame(width: width, height: height)
    }

    private func line<Content: View>(_ height: CGFloat, alignment: Alignment = .leading, @ViewBuilder _ content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: alignment)
    }

    private var header: some View {
        VStack(spacing: 2) {
            line(41) { bone(82, 30, radius: 10, opacity: 0.2) }
            line(20) { bone(93, 13, radius: 6, opacity: 0.12) }
        }
    }

    private var donut: some View {
        VStack(spacing: 22) {
            ZStack {
                arc(0.003, 0.620, Palette.sage)
                arc(0.626, 0.997, Palette.sand)
                Circle()
                    .fill(water.opacity(0.4))
                    .mask(alignment: .bottom) { Rectangle().frame(height: 70) }
                    .padding(46)
                bone(148, 28, radius: 10, opacity: 0.22)
                    .offset(y: -8)
                bone(64, 12, radius: 6, opacity: 0.12)
                    .offset(y: 18)
            }
            .frame(width: 270, height: 270)
            pill
        }
        .frame(maxWidth: .infinity)
    }

    private func arc(_ from: Double, _ to: Double, _ color: Color) -> some View {
        Circle()
            .trim(from: from, to: to)
            .stroke(color.opacity(0.62), style: StrokeStyle(lineWidth: 35, lineCap: .butt))
            .rotationEffect(.degrees(-90))
            .padding(17.5)
    }

    private var pill: some View {
        HStack(spacing: 10) {
            chipItem(34)
            chipItem(46)
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(Palette.surface, in: .capsule)
    }

    private func chipItem(_ width: CGFloat) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Palette.ink.opacity(0.25)).frame(width: 7, height: 7)
            bone(width, 8, opacity: 0.18)
            bone(14, 8, opacity: 0.18)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: .rect(cornerRadius: 30, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1) }
    }

    private var todayCard: some View {
        card {
            VStack(alignment: .leading, spacing: 18) {
                line(15) { bone(37, 10, opacity: 0.16) }
                VStack(alignment: .leading, spacing: 8) {
                    line(28) {
                        HStack(alignment: .center, spacing: 10) {
                            bone(59, 19, radius: 7, opacity: 0.22)
                            bone(97, 12, radius: 6, opacity: 0.12)
                        }
                    }
                    Capsule().fill(Palette.sage.opacity(0.2)).frame(height: 10)
                        .overlay(alignment: .leading) { Capsule().fill(Palette.sage.opacity(0.5)).frame(width: 70, height: 10) }
                }
                .padding(.top, -4)
                line(20) {
                    HStack(spacing: 10) {
                        bone(56, 13, radius: 6, opacity: 0.18)
                        bone(102, 13, radius: 6, opacity: 0.12)
                    }
                }
            }
        }
    }

    private var historyCard: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                line(15) { bone(68, 10, opacity: 0.16) }
                line(20) { bone(108, 14, radius: 6, opacity: 0.2) }
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(Array([0.9, 0.3, 0.0, 0.0, 0.0, 0.0, 0.0].enumerated()), id: \.offset) { _, fraction in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Palette.sage.opacity(fraction > 0 ? 0.3 : 0.08))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(8, 150 * fraction))
                    }
                }
                .frame(height: 204, alignment: .bottom)
                bone(nil, 36, radius: 12, opacity: 0.08)
            }
        }
    }

    private var bar: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                barCircle
                ZStack {
                    Capsule().fill(Palette.ink.opacity(0.14))
                    Capsule().strokeBorder(Palette.ink.opacity(0.22), lineWidth: 1)
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { item in
                            ZStack {
                                if item == 1 {
                                    Capsule().fill(Palette.ink.opacity(0.16)).padding(5)
                                }
                                VStack(spacing: 6) {
                                    Circle().fill(Palette.ink.opacity(item == 1 ? 0.42 : 0.3)).frame(width: 22, height: 22)
                                    bone(34, 6, opacity: item == 1 ? 0.4 : 0.26)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: 62)
                barCircle
            }
            .padding(.horizontal, KinetLayout.pageMargin)
            .padding(.bottom, KinetLayout.pageMargin)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var barCircle: some View {
        ZStack {
            Circle().fill(Palette.ink.opacity(0.14))
            Circle().strokeBorder(Palette.ink.opacity(0.22), lineWidth: 1)
            Circle().fill(Palette.ink.opacity(0.3)).frame(width: 22, height: 22)
        }
        .frame(width: KinetLayout.barHeight, height: KinetLayout.barHeight)
    }

    private var dots: some View {
        GeometryReader { proxy in
            ForEach(Array(Self.dotSpecs.enumerated()), id: \.offset) { _, dot in
                Circle()
                    .fill((dot.warm ? Palette.sage : water).opacity(0.38))
                    .frame(width: dot.size, height: dot.size)
                    .position(x: proxy.size.width * dot.x, y: proxy.size.height * dot.y)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private static let dotSpecs: [(x: Double, y: Double, size: Double, warm: Bool)] = [
        (0.08, 0.12, 5, true), (0.86, 0.09, 8, false), (0.93, 0.31, 4, true), (0.05, 0.38, 7, false),
        (0.78, 0.47, 5, true), (0.14, 0.58, 4, false), (0.9, 0.62, 6, true), (0.32, 0.74, 5, false),
        (0.7, 0.8, 4, true), (0.06, 0.86, 6, true), (0.52, 0.9, 5, false), (0.95, 0.9, 4, false)
    ]
}
